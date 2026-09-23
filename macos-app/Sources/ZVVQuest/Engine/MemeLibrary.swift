import Foundation
import NaturalLanguage

/// 素材库：扫描目录，把文件名当作台词含义，并预计算分词与主题。
final class MemeLibrary: ObservableObject {
    @Published private(set) var items: [MemeItem] = []
    @Published private(set) var sourceDescription: String = "未加载"
    @Published private(set) var loadedDirectory: URL?

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic", "bmp", "tiff"]

    func load(from directory: URL) throws {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LibraryError.directoryMissing(directory.path)
        }

        let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        var collected: [MemeItem] = []
        while let url = enumerator?.nextObject() as? URL {
            let ext = url.pathExtension.lowercased()
            guard MemeLibrary.imageExtensions.contains(ext) else { continue }
            guard !url.lastPathComponent.hasPrefix(".") else { continue }
            let title = url.deletingPathExtension().lastPathComponent
            let tokens = MemeLibrary.tokenize(title)
            let topics = TopicLexicon.matchTopics(in: title)
            let tones = TopicLexicon.matchTones(in: title)
            collected.append(
                MemeItem(
                    id: url.path,
                    url: url,
                    title: title,
                    tokens: tokens,
                    topics: topics,
                    tones: tones,
                    isTemplate: MemeLibrary.isTemplate(title)
                )
            )
        }

        collected.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        items = collected
        loadedDirectory = directory
        sourceDescription = "\(directory.lastPathComponent) · \(collected.count) 张素材"
    }

    /// 空白色板 / 万能模板这类素材没有台词含义，默认不参与语义匹配
    static func isTemplate(_ title: String) -> Bool {
        let cleaned = title.trimmingCharacters(in: .whitespaces)
        if cleaned.hasPrefix("空白") { return true }
        if cleaned.contains("万能模板") { return true }
        if cleaned.count <= 2 { return true }
        return false
    }

    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .tokenType,
            options: options
        ) { _, range in
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if token.count >= 1 { tokens.append(token) }
            return true
        }
        if tokens.isEmpty {
            tokens = text.split(whereSeparator: { $0 == " " || $0 == "，" || $0 == "," }).map(String.init)
        }
        return tokens
    }

    /// 字符二元组，用于中文短句的相似度计算
    static func bigrams(_ text: String) -> Set<String> {
        let chars = Array(text.filter { !$0.isWhitespace && !$0.isPunctuation })
        guard chars.count >= 2 else { return Set(chars.map(String.init)) }
        var result = Set<String>()
        for index in 0..<(chars.count - 1) {
            result.insert(String(chars[index...(index + 1)]))
        }
        return result
    }
}

enum LibraryError: LocalizedError {
    case directoryMissing(String)

    var errorDescription: String? {
        switch self {
        case .directoryMissing(let path): return "找不到素材目录：\(path)"
        }
    }
}

/// 定位素材库：优先用户设置，其次 App 包内置，最后项目目录
enum LibraryLocator {
    static func candidates(settingsPath: String) -> [URL] {
        var urls: [URL] = []
        if !settingsPath.isEmpty {
            urls.append(URL(fileURLWithPath: settingsPath))
        }
        if let resources = Bundle.main.resourceURL {
            urls.append(resources.appendingPathComponent("vv", isDirectory: true))
        }
        var current = Bundle.main.bundleURL
        for _ in 0..<4 {
            current = current.deletingLastPathComponent()
            urls.append(current.appendingPathComponent("vv", isDirectory: true))
        }
        urls.append(FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/文件/表情包/zvv连续对话表情包生成/vv", isDirectory: true))
        return urls
    }

    static func resolve(settingsPath: String) -> URL? {
        let manager = FileManager.default
        let unique = candidates(settingsPath: settingsPath).reduce(into: [URL]()) { result, url in
            let standardized = url.standardizedFileURL
            if !result.contains(standardized) { result.append(standardized) }
        }
        for url in unique {
            var isDirectory: ObjCBool = false
            if manager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let contents = (try? manager.contentsOfDirectory(atPath: url.path)) ?? []
                if contents.contains(where: { MemeLibrary.imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
                    return url
                }
            }
        }
        return nil
    }
}
