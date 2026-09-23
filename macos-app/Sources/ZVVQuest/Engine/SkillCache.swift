import Foundation
import CryptoKit

/// 本地 skill 缓存：同一句话 + 同一套参数只调用一次云端模型。
/// 这是需求里“选择云模型时本地存在对应 skill 减少 api 调用次数”的落地方式。
final class SkillCache {
    struct Entry: Codable {
        let key: String
        let query: String
        let model: String
        let name: String
        let sequence: [SequenceItem]
        let createdAt: Date
        var hits: Int
    }

    struct SequenceItem: Codable {
        let index: Int
        let line: String
        let english: String
    }

    private let fileURL: URL
    private var entries: [String: Entry] = [:]
    private let lock = NSLock()
    private let capacity = 200

    init() {
        let directory = AppPaths.applicationSupport.appendingPathComponent("skill-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("cloud-plan-cache.json")
        load()
    }

    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func key(query: String, model: String, count: Int, mode: StitchMode) -> String {
        let raw = "\(model)|\(count)|\(mode.rawValue)|\(TopicLexicon.normalized(query))"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func lookup(key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key] else { return nil }
        entry.hits += 1
        entries[key] = entry
        scheduleSave()
        return entry
    }

    func store(key: String, query: String, model: String, name: String, sequence: [SequenceItem]) {
        lock.lock()
        entries[key] = Entry(
            key: key,
            query: query,
            model: model,
            name: name,
            sequence: sequence,
            createdAt: Date(),
            hits: 0
        )
        if entries.count > capacity {
            let sorted = entries.values.sorted { $0.createdAt < $1.createdAt }
            for entry in sorted.prefix(entries.count - capacity) {
                entries.removeValue(forKey: entry.key)
            }
        }
        lock.unlock()
        save()
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder.zvv.decode([String: Entry].self, from: data)
        else { return }
        entries = decoded
    }

    private var saveScheduled = false

    private func scheduleSave() {
        lock.lock()
        if saveScheduled {
            lock.unlock()
            return
        }
        saveScheduled = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.save()
        }
    }

    private func save() {
        lock.lock()
        let snapshot = entries
        saveScheduled = false
        lock.unlock()
        guard let data = try? JSONEncoder.zvv.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
