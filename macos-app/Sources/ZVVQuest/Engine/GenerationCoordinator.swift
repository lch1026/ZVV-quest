import Foundation
import AppKit

/// 把「语义理解 → 选材排序 → 拼接渲染 → 落盘/剪贴板」串起来的中枢
final class GenerationCoordinator: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var statusText = ""
    @Published private(set) var libraryInfo = "尚未加载素材库"
    @Published private(set) var candidates: [MemeCandidate] = []
    @Published private(set) var lastPlan: StitchPlan?
    @Published private(set) var lastPNG: Data?
    @Published private(set) var lastRecord: GenerationRecord?
    @Published private(set) var noteMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var timingSummary: String?

    let engine = SemanticEngine()
    let planner = DialoguePlanner()
    let cloud = CloudPlanner()
    let store = GenerationStore()
    private let library = MemeLibrary()

    private let workQueue = DispatchQueue(label: "com.zvvquest.generate", qos: .userInitiated)
    private var indexSignature: String?

    var libraryItems: [MemeItem] { library.items }
    var libraryDirectory: URL? { library.loadedDirectory }

    // MARK: - 素材库

    func prepareLibrary(force: Bool = false, completion: (() -> Void)? = nil) {
        let settings = AppSettings.shared
        workQueue.async { [weak self] in
            guard let self else { return }
            let resolved = LibraryLocator.resolve(settingsPath: settings.libraryPath)
            guard let directory = resolved else {
                DispatchQueue.main.async {
                    self.libraryInfo = "未找到素材目录，请在设置中指定"
                    self.errorMessage = "没有找到素材库目录，请到「设置」里选择 vv 素材文件夹"
                }
                completion?()
                return
            }

            let signature = "\(directory.path)#\(self.fileCount(at: directory))"
            if !force, self.indexSignature == signature, self.engine.indexedCount > 0 {
                completion?()
                return
            }

            DispatchQueue.main.async {
                self.statusText = "正在索引素材库…"
                self.progress = 0.05
            }
            do {
                try self.library.load(from: directory)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.statusText = ""
                }
                completion?()
                return
            }

            self.engine.buildIndex(items: self.library.items)
            self.indexSignature = signature
            DispatchQueue.main.async {
                self.libraryInfo = "\(self.library.sourceDescription) · \(self.engine.vectorDescription)"
                self.statusText = ""
                self.progress = 0
                self.errorMessage = nil
                completion?()
            }
        }
    }

    private func fileCount(at directory: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
    }

    // MARK: - 生成

    func generate(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "先写一句想表达的话吧"
            return
        }
        guard !isWorking else { return }

        let settings = AppSettings.shared
        settings.clampMaxImages()
        isWorking = true
        errorMessage = nil
        noteMessage = nil
        progress = 0.02
        statusText = "准备素材库…"

        let start = DispatchTime.now()
        prepareLibrary { [weak self] in
            guard let self else { return }
            guard self.engine.indexedCount > 0 else {
                DispatchQueue.main.async {
                    self.isWorking = false
                    self.statusText = ""
                    self.progress = 0
                }
                return
            }
            self.workQueue.async {
                self.runPipeline(query: trimmed, settings: settings, start: start)
            }
        }
    }

    private func runPipeline(query: String, settings: AppSettings, start: DispatchTime) {
        update { $0.statusText = "本地语义理解中…"; $0.progress = 0.2 }

        let result = engine.rank(query: query, backend: settings.backend)
        update { _ in
            self.candidates = result.candidates
        }

        let limit = min(settings.maxImages, settings.maxImagesLimit)
        var lines: [PlannedLine] = []
        var semanticName: String?
        var source = "本地语义引擎"
        var note: String?

        if settings.engine == .cloud {
            update { $0.statusText = "请求云端模型编排台词…"; $0.progress = 0.35 }
            do {
                let outcome = try awaitPlan(
                    query: query,
                    mode: settings.stitchMode,
                    candidates: result.candidates,
                    count: limit,
                    settings: settings
                )
                lines = outcome.lines
                semanticName = outcome.semanticName
                source = "云端 \(settings.cloudModel)"
                note = outcome.note
            } catch {
                note = "云端编排失败（\(error.localizedDescription)），已回退本地语义引擎"
            }
        }

        if lines.isEmpty {
            update { $0.statusText = "编排连续对话…"; $0.progress = 0.45 }
            var localPlanner = planner
            localPlanner.maxImages = limit
            lines = localPlanner.plan(query: query, candidates: result.candidates)
        }

        let name = semanticName?.isEmpty == false
            ? semanticName!
            : planner.semanticName(query: query, lines: lines, topics: TopicLexicon.matchTopics(in: TopicLexicon.normalized(query)))

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        let plan = StitchPlan(
            query: query,
            mode: settings.stitchMode,
            lines: lines,
            semanticName: name,
            source: source,
            elapsed: elapsed,
            timing: result.timing,
            cloudNote: note
        )

        update {
            $0.statusText = "拼接渲染中…"
            $0.progress = 0.55
            $0.lastPlan = plan
        }

        do {
            let output = try MemeRenderer.render(plan: plan, settings: settings) { value in
                self.update { $0.progress = 0.55 + value * 0.3 }
            }
            update { $0.statusText = "写入缓存目录…"; $0.progress = 0.9 }
            let record = try store.save(
                pngData: output.pngData,
                semanticName: name,
                query: query,
                mode: settings.stitchMode,
                source: source,
                itemTitles: lines.map(\.item.title)
            )
            var copied = false
            if settings.autoCopyToPasteboard {
                copied = Clipboard.copy(pngData: output.pngData)
            }

            update { _ in
                self.lastPNG = output.pngData
                self.lastRecord = record
                self.timingSummary = result.timing?.summary
                self.noteMessage = self.composeNote(note: note, copied: copied, pixel: output.pixelSize)
                self.statusText = ""
                self.progress = 0
                self.isWorking = false
            }
        } catch {
            update { _ in
                self.errorMessage = error.localizedDescription
                self.statusText = ""
                self.progress = 0
                self.isWorking = false
            }
        }
    }

    private func awaitPlan(
        query: String,
        mode: StitchMode,
        candidates: [MemeCandidate],
        count: Int,
        settings: AppSettings
    ) throws -> CloudPlanner.Outcome {
        var outcome: CloudPlanner.Outcome?
        var thrown: Error?
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                outcome = try await cloud.plan(query: query, mode: mode, candidates: candidates, count: count, settings: settings)
            } catch {
                thrown = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let thrown { throw thrown }
        guard let outcome else { throw CloudError.transport("云端返回为空") }
        return outcome
    }

    private func composeNote(note: String?, copied: Bool, pixel: CGSize) -> String {
        var parts: [String] = []
        if let note { parts.append(note) }
        parts.append("输出 \(Int(pixel.width))×\(Int(pixel.height))")
        parts.append(copied ? "已复制到剪贴板" : "剪贴板未写入（可在结果区手动复制）")
        return parts.joined(separator: " · ")
    }

    /// 统一在主线程更新 @Published 状态
    private func update(_ block: @escaping (GenerationCoordinator) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            block(self)
        }
    }

    func clearResult() {
        lastPNG = nil
        lastRecord = nil
        lastPlan = nil
        noteMessage = nil
        timingSummary = nil
    }

    func copyLastResult() -> Bool {
        guard let data = lastPNG else { return false }
        return Clipboard.copy(pngData: data)
    }

    func runBackendSelfTest() -> String {
        let outcome = VectorMath.selfTest()
        var text = String(format: "CPU 基准 %.2f ms", outcome.cpu)
        if let gpu = outcome.gpu {
            text = String(format: "%@ · GPU %.2f ms", text, gpu)
        }
        if let drift = outcome.drift {
            text += String(format: " · 最大偏差 %.2e", drift)
        }
        text += " · \(outcome.note)"
        return text
    }
}
