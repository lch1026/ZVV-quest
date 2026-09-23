import Foundation
import Metal
import Observation

struct HardwareSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let cpuTotal: Double
    let memoryUsedGB: Double
    let memoryTotalGB: Double
    let gpuUsage: Double?
    let gpuMemoryGB: Double
}

/// 轮询本机硬件资源：CPU 占用、内存占用、GPU 利用率（无权限读取时退化为显存占用）
final class HardwareMonitor: ObservableObject {
    @Published private(set) var samples: [HardwareSample] = []
    @Published private(set) var gpuName: String = "未知 GPU"
    @Published private(set) var gpuUsageAvailable = false

    private let historyLimit = 90
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.zvvquest.hardware-monitor")
    private var previousTicks: [UInt32] = []
    private var iokitReader: IOKitGPUReader?
    private let metalDevice = MTLCreateSystemDefaultDevice()

    var latest: HardwareSample? { samples.last }

    func start(interval: TimeInterval = 1.0) {
        guard timer == nil else { return }
        gpuName = metalDevice?.name ?? "无 Metal 设备"
        iokitReader = IOKitGPUReader()
        gpuUsageAvailable = iokitReader?.isAvailable ?? false

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let sample = self.collect()
            DispatchQueue.main.async {
                self.samples.append(sample)
                if self.samples.count > self.historyLimit {
                    self.samples.removeFirst(self.samples.count - self.historyLimit)
                }
            }
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func collect() -> HardwareSample {
        let cpu = cpuLoad()
        let (used, total) = memoryLoad()
        var gpuUsage: Double? = nil
        if gpuUsageAvailable {
            gpuUsage = iokitReader?.utilization
        }
        let gpuMemory = (iokitReader?.inUseMemoryBytes.map { Double($0) / 1_073_741_824 })
            ?? Double(metalDevice?.currentAllocatedSize ?? 0) / 1_073_741_824
        return HardwareSample(
            timestamp: Date(),
            cpuTotal: cpu,
            memoryUsedGB: used,
            memoryTotalGB: total,
            gpuUsage: gpuUsage,
            gpuMemoryGB: gpuMemory
        )
    }

    private func cpuLoad() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousTicks = ticks }
        guard previousTicks.count == ticks.count else { return 0 }
        var deltas = [Double](repeating: 0, count: ticks.count)
        for index in 0..<ticks.count {
            deltas[index] = Double(ticks[index] &- previousTicks[index])
        }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return 0 }
        // host_cpu_load_info 的顺序是 user, system, idle, nice
        let idle = deltas[2]
        return max(0, min(1, (total - idle) / total))
    }

    private func memoryLoad() -> (Double, Double) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        guard result == KERN_SUCCESS else { return (0, totalBytes / 1_073_741_824) }
        let pageSize = Double(vm_kernel_page_size)
        let active = Double(stats.active_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        return (used / 1_073_741_824, totalBytes / 1_073_741_824)
    }
}
