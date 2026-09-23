import Foundation

/// 本地语义引擎：句向量 + 关键词 + 主题三路打分融合。
final class SemanticEngine {
    struct Entry {
        let item: MemeItem
        let embedding: [Float]?
        let bigrams: Set<String>
        let tokenSet: Set<String>
    }

    struct Result {
        let candidates: [MemeCandidate]
        let timing: BackendTiming?
        let embedderInfo: String
    }

    let embedder = TextEmbedder()
    private var entries: [Entry] = []
    private var matrix: [[Float]] = []
    private var matrixIndices: [Int] = []

    var indexedCount: Int { entries.count }
    var vectorDescription: String { embedder.backendDescription }

    func buildIndex(items: [MemeItem], includeTemplates: Bool = false) {
        entries = items.filter { includeTemplates || !$0.isTemplate }.map { item in
            Entry(
                item: item,
                embedding: embedder.vector(for: item.title).map(TextEmbedder.normalize),
                bigrams: MemeLibrary.bigrams(item.title),
                tokenSet: Set(item.tokens)
            )
        }
        matrix = []
        matrixIndices = []
        for (index, entry) in entries.enumerated() {
            guard let embedding = entry.embedding, embedding.count == embedder.dimension else { continue }
            matrix.append(embedding)
            matrixIndices.append(index)
        }
    }

    func rank(query rawQuery: String, backend: ComputeBackend) -> Result {
        let query = TopicLexicon.normalized(rawQuery)
        guard !query.isEmpty, !entries.isEmpty else {
            return Result(candidates: [], timing: nil, embedderInfo: embedder.backendDescription)
        }

        let queryBigrams = MemeLibrary.bigrams(query)
        let queryTokens = Set(MemeLibrary.tokenize(query))
        let queryTopics = Set(TopicLexicon.matchTopics(in: query))
        let queryTones = Set(TopicLexicon.matchTones(in: query))

        var embeddingScores = [Double](repeating: 0, count: entries.count)
        var timing: BackendTiming?

        if let queryVector = embedder.vector(for: query)?.map({ Double($0) }), !matrix.isEmpty {
            let floatQuery = queryVector.map(Float.init)
            let normalizedQuery = TextEmbedder.normalize(floatQuery)
            do {
                let outcome = try VectorMath.cosineScores(query: normalizedQuery, matrix: matrix, backend: backend)
                var drift: Double? = nil
                if VectorMath.effectiveBackend(backend) == .gpu {
                    let cpuStart = DispatchTime.now()
                    let cpuScores = VectorMath.cpuCosine(query: normalizedQuery, matrix: matrix)
                    let cpuMS = Double(DispatchTime.now().uptimeNanoseconds - cpuStart.uptimeNanoseconds) / 1_000_000
                    var maxDrift = 0.0
                    for index in 0..<min(cpuScores.count, outcome.scores.count) {
                        maxDrift = max(maxDrift, abs(Double(cpuScores[index] - outcome.scores[index])))
                    }
                    drift = maxDrift
                    _ = cpuMS
                }
                for (position, index) in matrixIndices.enumerated() where position < outcome.scores.count {
                    embeddingScores[index] = Double(outcome.scores[position])
                }
                timing = BackendTiming(
                    backend: outcome.backend,
                    milliseconds: outcome.milliseconds,
                    rows: matrix.count,
                    columns: embedder.dimension,
                    drift: drift
                )
            } catch {
                timing = nil
            }
        }

        var rawEmbedding = embeddingScores
        var rawLexical = [Double](repeating: 0, count: entries.count)
        var rawTopic = [Double](repeating: 0, count: entries.count)
        var rawTone = [Double](repeating: 0, count: entries.count)

        for (index, entry) in entries.enumerated() {
            let bigramUnion = queryBigrams.union(entry.bigrams)
            let bigramIntersection = queryBigrams.intersection(entry.bigrams)
            let bigramScore = bigramUnion.isEmpty ? 0 : Double(bigramIntersection.count) / Double(bigramUnion.count)

            let tokenUnion = queryTokens.union(entry.tokenSet)
            let tokenIntersection = queryTokens.intersection(entry.tokenSet)
            let tokenScore = tokenUnion.isEmpty ? 0 : Double(tokenIntersection.count) / Double(tokenUnion.count)

            let phraseBonus = entry.item.title.contains(query) || query.contains(entry.item.title) ? 0.35 : 0.0
            rawLexical[index] = min(1.0, bigramScore * 0.65 + tokenScore * 0.35 + phraseBonus)

            if queryTopics.isEmpty {
                rawTopic[index] = 0.5
            } else {
                let entryTopics = Set(entry.item.topics)
                let union = queryTopics.union(entryTopics)
                rawTopic[index] = union.isEmpty ? 0 : Double(queryTopics.intersection(entryTopics).count) / Double(union.count)
            }

            if queryTones.isEmpty {
                rawTone[index] = 0.5
            } else {
                let entryTones = Set(entry.item.tones)
                let union = queryTones.union(entryTones)
                rawTone[index] = union.isEmpty ? 0 : Double(queryTones.intersection(entryTones).count) / Double(union.count)
            }
        }

        rawEmbedding = SemanticEngine.minMaxNormalize(rawEmbedding)
        rawLexical = SemanticEngine.minMaxNormalize(rawLexical)
        rawTopic = SemanticEngine.minMaxNormalize(rawTopic)
        rawTone = SemanticEngine.minMaxNormalize(rawTone)

        var candidates: [MemeCandidate] = []
        for (index, entry) in entries.enumerated() {
            let score = rawEmbedding[index] * 0.45 + rawLexical[index] * 0.28 + rawTopic[index] * 0.17 + rawTone[index] * 0.10
            var reasons: [String] = []
            let sharedTopics = queryTopics.intersection(Set(entry.item.topics)).sorted()
            if !sharedTopics.isEmpty { reasons.append("主题命中：" + sharedTopics.joined(separator: "、")) }
            let sharedTokens = queryTokens.intersection(entry.tokenSet).sorted()
            if !sharedTokens.isEmpty { reasons.append("关键词：" + sharedTokens.prefix(4).joined(separator: "、")) }
            let sharedTones = queryTones.intersection(Set(entry.item.tones)).sorted()
            if !sharedTones.isEmpty { reasons.append("口吻：" + sharedTones.joined(separator: "、")) }
            if rawEmbedding[index] > 0.6 { reasons.append("语义接近") }
            if reasons.isEmpty { reasons.append("话题相关度一般") }
            candidates.append(
                MemeCandidate(
                    item: entry.item,
                    score: score,
                    embeddingScore: rawEmbedding[index],
                    lexicalScore: rawLexical[index],
                    topicScore: rawTopic[index],
                    reasons: reasons
                )
            )
        }
        candidates.sort { $0.score > $1.score }
        return Result(candidates: candidates, timing: timing, embedderInfo: embedder.backendDescription)
    }

    static func minMaxNormalize(_ values: [Double]) -> [Double] {
        guard let minimum = values.min(), let maximum = values.max(), maximum - minimum > 1e-9 else {
            return values.map { _ in 0.5 }
        }
        return values.map { ($0 - minimum) / (maximum - minimum) }
    }
}
