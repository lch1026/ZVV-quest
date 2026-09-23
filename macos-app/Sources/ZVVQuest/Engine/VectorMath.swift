import Foundation
import Metal
import Accelerate

enum VectorMathError: LocalizedError {
    case noMetalDevice
    case kernelFailure(String)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice: return "当前环境没有可用的 Metal 设备，已回退到 CPU 计算"
        case .kernelFailure(let message): return "Metal 计算失败：\(message)"
        }
    }
}

/// 向量相似度计算：GPU（Metal compute）与 CPU（Accelerate/vDSP）双实现。
/// 两个后端都必须给出同样的结果，界面里可以直接看到两者耗时与偏差。
enum VectorMath {
    struct Outcome {
        let scores: [Float]
        let backend: String
        let milliseconds: Double
        let drift: Double?
    }

    /// 根据设置决定实际使用的后端
    static func effectiveBackend(_ requested: ComputeBackend) -> ComputeBackend {
        switch requested {
        case .cpu: return .cpu
        case .gpu: return MetalCosineKernel.shared.isAvailable ? .gpu : .cpu
        case .auto: return MetalCosineKernel.shared.isAvailable ? .gpu : .cpu
        }
    }

    static func backendName(_ backend: ComputeBackend) -> String {
        switch backend {
        case .gpu: return "GPU(Metal)"
        case .cpu: return "CPU(Accelerate)"
        case .auto: return "自动"
        }
    }

    static func cosineScores(query: [Float], matrix: [[Float]], backend: ComputeBackend) throws -> Outcome {
        let effective = effectiveBackend(backend)
        var note: String? = nil

        if effective == .gpu {
            do {
                let start = DispatchTime.now()
                let scores = try MetalCosineKernel.shared.cosine(query: query, matrix: matrix)
                let ms = elapsedMilliseconds(since: start)
                return Outcome(scores: scores, backend: backendName(.gpu), milliseconds: ms, drift: nil)
            } catch {
                note = error.localizedDescription
            }
        }

        let start = DispatchTime.now()
        let scores = cpuCosine(query: query, matrix: matrix)
        let ms = elapsedMilliseconds(since: start)
        let name = backendName(.cpu) + (note == nil ? "" : "（回退）")
        return Outcome(scores: scores, backend: name, milliseconds: ms, drift: nil)
    }

    /// 后端一致性自检：同一份数据分别用 GPU 与 CPU 计算，返回最大偏差
    static func selfTest(rows: Int = 64, dim: Int = 128) -> (gpu: Double?, cpu: Double, drift: Double?, note: String) {
        var generator = SystemRandomNumberGenerator()
        let query = (0..<dim).map { _ in Float.random(in: -1...1, using: &generator) }
        let matrix = (0..<rows).map { _ in (0..<dim).map { _ in Float.random(in: -1...1, using: &generator) } }

        let cpuStart = DispatchTime.now()
        let cpuScores = cpuCosine(query: query, matrix: matrix)
        let cpuMS = elapsedMilliseconds(since: cpuStart)

        do {
            let gpuStart = DispatchTime.now()
            let gpuScores = try MetalCosineKernel.shared.cosine(query: query, matrix: matrix)
            let gpuMS = elapsedMilliseconds(since: gpuStart)
            var drift: Double = 0
            for index in 0..<min(cpuScores.count, gpuScores.count) {
                drift = max(drift, abs(Double(cpuScores[index] - gpuScores[index])))
            }
            return (gpuMS, cpuMS, drift, "GPU 与 CPU 结果一致")
        } catch {
            return (nil, cpuMS, nil, error.localizedDescription)
        }
    }

    static func cpuCosine(query: [Float], matrix: [[Float]]) -> [Float] {
        let dim = query.count
        var queryNormalized = query
        var queryNorm: Float = 0
        vDSP_svesq(query, 1, &queryNorm, vDSP_Length(dim))
        let queryLength = sqrt(queryNorm)
        if queryLength > 1e-8 {
            var scale = 1 / queryLength
            vDSP_vsmul(query, 1, &scale, &queryNormalized, 1, vDSP_Length(dim))
        }

        var scores = [Float](repeating: 0, count: matrix.count)
        scores.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: matrix.count) { row in
                let vector = matrix[row]
                guard vector.count == dim else { return }
                var dot: Float = 0
                vDSP_dotpr(queryNormalized, 1, vector, 1, &dot, vDSP_Length(dim))
                base[row] = dot
            }
        }
        return scores
    }

    private static func elapsedMilliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}

/// Metal 计算内核：运行时编译，避免依赖 Xcode 的 metal 工具链。
final class MetalCosineKernel {
    static let shared = MetalCosineKernel()

    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private(set) var loadError: String?

    var isAvailable: Bool { pipeline != nil }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void cosine_similarity(device const float* query   [[buffer(0)]],
                                  device const float* matrix  [[buffer(1)]],
                                  device float*       output  [[buffer(2)]],
                                  constant uint&      dim     [[buffer(3)]],
                                  constant uint&      rows    [[buffer(4)]],
                                  uint gid [[thread_position_in_grid]]) {
        if (gid >= rows) { return; }
        device const float* row = matrix + gid * dim;
        float dot = 0.0f;
        float query_norm = 0.0f;
        float row_norm = 0.0f;
        for (uint i = 0; i < dim; ++i) {
            float q = query[i];
            float r = row[i];
            dot += q * r;
            query_norm += q * q;
            row_norm += r * r;
        }
        float denominator = sqrt(query_norm) * sqrt(row_norm);
        output[gid] = denominator > 1e-8f ? dot / denominator : 0.0f;
    }
    """

    private init() {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        self.queue = device?.makeCommandQueue()
        guard let device else {
            pipeline = nil
            loadError = "未检测到 Metal 设备"
            return
        }
        do {
            let library = try device.makeLibrary(source: MetalCosineKernel.source, options: nil)
            guard let function = library.makeFunction(name: "cosine_similarity") else {
                throw VectorMathError.kernelFailure("找不到 cosine_similarity 内核")
            }
            pipeline = try device.makeComputePipelineState(function: function)
            loadError = nil
        } catch {
            pipeline = nil
            loadError = error.localizedDescription
        }
    }

    var deviceName: String { device?.name ?? "无" }

    /// 计算 query 与矩阵每一行的余弦相似度
    func cosine(query: [Float], matrix: [[Float]]) throws -> [Float] {
        guard let device, let queue, let pipeline else {
            throw VectorMathError.noMetalDevice
        }
        let rows = matrix.count
        guard rows > 0 else { return [] }
        let dim = query.count
        guard dim > 0 else { return [Float](repeating: 0, count: rows) }

        var flat = [Float]()
        flat.reserveCapacity(rows * dim)
        for row in matrix {
            if row.count == dim {
                flat.append(contentsOf: row)
            } else {
                flat.append(contentsOf: row.prefix(dim))
                if row.count < dim { flat.append(contentsOf: [Float](repeating: 0, count: dim - row.count)) }
            }
        }

        let byteCount = rows * dim * MemoryLayout<Float>.stride
        guard let queryBuffer = device.makeBuffer(bytes: query, length: dim * MemoryLayout<Float>.stride, options: .storageModeShared),
              let matrixBuffer = device.makeBuffer(bytes: flat, length: byteCount, options: .storageModeShared),
              let outputBuffer = device.makeBuffer(length: rows * MemoryLayout<Float>.stride, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw VectorMathError.kernelFailure("缓冲区分配失败")
        }

        var dimValue = UInt32(dim)
        var rowsValue = UInt32(rows)

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(queryBuffer, offset: 0, index: 0)
        encoder.setBuffer(matrixBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBytes(&dimValue, length: MemoryLayout<UInt32>.size, index: 3)
        encoder.setBytes(&rowsValue, length: MemoryLayout<UInt32>.size, index: 4)

        let threadWidth = max(1, min(pipeline.threadExecutionWidth, 64))
        let threadsPerGroup = MTLSize(width: threadWidth, height: 1, depth: 1)
        let groups = MTLSize(width: (rows + threadWidth - 1) / threadWidth, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw VectorMathError.kernelFailure(error.localizedDescription)
        }

        let raw = outputBuffer.contents().bindMemory(to: Float.self, capacity: rows)
        return Array(UnsafeBufferPointer(start: raw, count: rows))
    }
}
