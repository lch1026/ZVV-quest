import Foundation
import AppKit

/// 生成结果落盘：cache 目录 + 语义化命名 + 索引，支持浏览与删除
final class GenerationStore: ObservableObject {
    @Published private(set) var records: [GenerationRecord] = []
    @Published private(set) var lastError: String?

    private var indexURL: URL {
        directory.appendingPathComponent("index.json")
    }

    var directory: URL {
        let path = AppSettings.shared.cacheDirectory
        if path.isEmpty { return AppPaths.defaultCacheDirectory }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func reload() {
        let manager = FileManager.default
        if !manager.fileExists(atPath: directory.path) {
            try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder.zvv.decode([GenerationRecord].self, from: data)
        else {
            records = []
            return
        }
        // 丢掉磁盘上已经不存在的记录
        let existing = decoded.filter { manager.fileExists(atPath: directory.appendingPathComponent($0.fileName).path) }
        records = existing.sorted { $0.createdAt > $1.createdAt }
        if existing.count != decoded.count { persist() }
    }

    @discardableResult
    func save(
        pngData: Data,
        semanticName: String,
        query: String,
        mode: StitchMode,
        source: String,
        itemTitles: [String]
    ) throws -> GenerationRecord {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let stamp = GenerationStore.fileStamp.string(from: Date())
        let safeName = GenerationStore.sanitize(semanticName)
        var fileName = "ZVV-\(safeName)-\(stamp).png"
        var counter = 2
        while manager.fileExists(atPath: directory.appendingPathComponent(fileName).path) {
            fileName = "ZVV-\(safeName)-\(stamp)-\(counter).png"
            counter += 1
        }

        let url = directory.appendingPathComponent(fileName)
        try pngData.write(to: url, options: .atomic)

        let record = GenerationRecord(
            id: fileName,
            fileName: fileName,
            displayName: safeName,
            query: query,
            mode: mode.rawValue,
            source: source,
            createdAt: Date(),
            itemTitles: itemTitles
        )
        records.insert(record, at: 0)
        persist()
        return record
    }

    func delete(_ record: GenerationRecord) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.fileName))
        records.removeAll { $0.id == record.id }
        persist()
    }

    func delete(ids: Set<String>) {
        for id in ids {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(id))
        }
        records.removeAll { ids.contains($0.id) }
        persist()
    }

    func deleteAll() {
        for record in records {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.fileName))
        }
        records.removeAll()
        persist()
    }

    func url(for record: GenerationRecord) -> URL {
        directory.appendingPathComponent(record.fileName)
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder.zvv.encode(records)
            try data.write(to: indexURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    static func sanitize(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(of: " ", with: "")
        if collapsed.isEmpty { return "表情包" }
        return String(collapsed.prefix(28))
    }

    private static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMdd-HHmmss"
        return formatter
    }()
}

extension JSONEncoder {
    static let zvv: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let zvv: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
