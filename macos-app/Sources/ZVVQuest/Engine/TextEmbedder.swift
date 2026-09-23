import Foundation
import NaturalLanguage

/// 本地语义向量：使用系统 NaturalLanguage 的中文句向量。
/// 完全不联网，也不需要下载模型。
final class TextEmbedder {
    private let sentence: NLEmbedding?
    private let word: NLEmbedding?
    private var cache: [String: [Float]] = [:]
    private let lock = NSLock()

    let dimension: Int
    let backendDescription: String

    init() {
        let sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
        let wordEmbedding = NLEmbedding.wordEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.wordEmbedding(for: .english)
        self.sentence = sentenceEmbedding
        self.word = wordEmbedding
        if let sentenceEmbedding {
            dimension = sentenceEmbedding.dimension
            backendDescription = "NaturalLanguage 句向量（\(sentenceEmbedding.dimension) 维）"
        } else if let wordEmbedding {
            dimension = wordEmbedding.dimension
            backendDescription = "NaturalLanguage 词向量平均（\(wordEmbedding.dimension) 维）"
        } else {
            dimension = 0
            backendDescription = "系统未提供中文词向量，已退化为纯关键词匹配"
        }
    }

    var isAvailable: Bool { dimension > 0 }

    func vector(for text: String) -> [Float]? {
        let key = TextEmbedder.normalizeKey(text)
        guard !key.isEmpty else { return nil }

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let vector = computeVector(for: key)
        if let vector {
            lock.lock()
            cache[key] = vector
            lock.unlock()
        }
        return vector
    }

    private func computeVector(for key: String) -> [Float]? {
        if let sentence, let raw = sentence.vector(for: key) {
            return raw.map(Float.init)
        }
        guard let word else { return nil }
        var accumulator = [Double](repeating: 0, count: word.dimension)
        var count = 0.0
        MemeLibrary.tokenize(key).forEach { token in
            guard let vector = word.vector(for: token) else { return }
            for index in 0..<min(vector.count, accumulator.count) {
                accumulator[index] += vector[index]
            }
            count += 1
        }
        guard count > 0 else { return nil }
        return accumulator.map { Float($0 / count) }
    }

    static func normalizeKey(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    static func normalize(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        for value in vector { norm += value * value }
        norm = sqrt(norm)
        guard norm > 1e-8 else { return vector }
        return vector.map { $0 / norm }
    }
}
