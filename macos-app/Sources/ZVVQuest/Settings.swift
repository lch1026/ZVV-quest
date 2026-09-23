import Foundation
import SwiftUI

/// 全部可持久化设置，写入 UserDefaults
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let store: UserDefaults
    private var isLoading = false

    @Published var libraryPath: String { didSet { save("libraryPath", libraryPath) } }
    @Published var stitchMode: StitchMode { didSet { save("stitchMode", stitchMode.rawValue) } }
    @Published var backend: ComputeBackend { didSet { save("backend", backend.rawValue) } }
    @Published var engine: EngineMode { didSet { save("engine", engine.rawValue) } }
    @Published var maxImages: Int { didSet { save("maxImages", maxImages) } }
    @Published var canvasWidth: Int { didSet { save("canvasWidth", canvasWidth) } }
    @Published var imageGap: Int { didSet { save("imageGap", imageGap) } }
    @Published var subtitleFontSize: Double { didSet { save("subtitleFontSize", subtitleFontSize) } }
    @Published var subtitleBandRatio: Double { didSet { save("subtitleBandRatio", subtitleBandRatio) } }
    @Published var cloudBaseURL: String { didSet { save("cloudBaseURL", cloudBaseURL) } }
    @Published var cloudModel: String { didSet { save("cloudModel", cloudModel) } }
    @Published var cloudAPIKey: String { didSet { save("cloudAPIKey", cloudAPIKey) } }
    @Published var cloudThinking: Bool { didSet { save("cloudThinking", cloudThinking) } }
    @Published var useSkillCache: Bool { didSet { save("useSkillCache", useSkillCache) } }
    @Published var skillPromptPath: String { didSet { save("skillPromptPath", skillPromptPath) } }
    @Published var cacheDirectory: String { didSet { save("cacheDirectory", cacheDirectory) } }
    @Published var autoCopyToPasteboard: Bool { didSet { save("autoCopyToPasteboard", autoCopyToPasteboard) } }

    var maxImagesLimit: Int { 15 }

    private init(store: UserDefaults = .standard) {
        self.store = store
        isLoading = true
        libraryPath = store.string(forKey: "libraryPath") ?? ""
        stitchMode = StitchMode(rawValue: store.string(forKey: "stitchMode") ?? "") ?? .full
        backend = ComputeBackend(rawValue: store.string(forKey: "backend") ?? "") ?? .auto
        engine = EngineMode(rawValue: store.string(forKey: "engine") ?? "") ?? .local
        maxImages = store.object(forKey: "maxImages") as? Int ?? 6
        canvasWidth = store.object(forKey: "canvasWidth") as? Int ?? 720
        imageGap = store.object(forKey: "imageGap") as? Int ?? 8
        subtitleFontSize = store.object(forKey: "subtitleFontSize") as? Double ?? 34
        subtitleBandRatio = store.object(forKey: "subtitleBandRatio") as? Double ?? 0.60
        cloudBaseURL = store.string(forKey: "cloudBaseURL") ?? AppSettings.defaultBaseURL
        cloudModel = store.string(forKey: "cloudModel") ?? AppSettings.defaultModel
        cloudAPIKey = store.string(forKey: "cloudAPIKey") ?? ""
        cloudThinking = store.object(forKey: "cloudThinking") as? Bool ?? false
        useSkillCache = store.object(forKey: "useSkillCache") as? Bool ?? true
        skillPromptPath = store.string(forKey: "skillPromptPath") ?? ""
        cacheDirectory = store.string(forKey: "cacheDirectory") ?? AppPaths.defaultCacheDirectory.path
        autoCopyToPasteboard = store.object(forKey: "autoCopyToPasteboard") as? Bool ?? true
        isLoading = false
        maxImages = min(max(maxImages, 1), maxImagesLimit)
    }

    static let defaultBaseURL = "https://api.deepseek.com"
    static let defaultModel = "deepseek-flash"

    func clampMaxImages() {
        if maxImages > maxImagesLimit { maxImages = maxImagesLimit }
        if maxImages < 1 { maxImages = 1 }
    }

    private func save(_ key: String, _ value: Any) {
        guard !isLoading else { return }
        objectWillChange.send()
        store.set(value, forKey: key)
    }
}

enum AppPaths {
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.zvvquest.app"
    }

    static var defaultCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("ZVVQuest", isDirectory: true)
    }

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? defaultCacheDirectory
        return base.appendingPathComponent("ZVVQuest", isDirectory: true)
    }
}

/// UserDefaults 的实际写盘由 Foundation 处理，这里只做视图需要的格式化
extension Int {
    var clampedToMaxImages: Int { Swift.min(Swift.max(self, 1), 15) }
}
