import Foundation

/// 把候选台词编排成一段“连续对话”：
/// 1. 用 MMR（最大边际相关）挑出既贴合语义又不重复的一组素材；
/// 2. 用相邻相似度贪心链给出最顺的先后顺序；
/// 3. 校正首尾角色，让结尾落在最有梗的那句上。
struct DialoguePlanner {
    var maxImages: Int = 15
    var diversity: Double = 0.62

    func plan(query: String, candidates: [MemeCandidate]) -> [PlannedLine] {
        let limit = max(1, min(maxImages, 15))
        let selected = selectDiverse(candidates: Array(candidates.prefix(120)), count: limit)
        guard !selected.isEmpty else { return [] }
        return sequence(selected)
    }

    /// 用台词本身生成一个语义化的文件名词缀
    func semanticName(query: String, lines: [PlannedLine], topics: [String]) -> String {
        var parts: [String] = []
        let queryTopics = topics.isEmpty ? TopicLexicon.matchTopics(in: TopicLexicon.normalized(query)) : topics
        parts.append(contentsOf: queryTopics.prefix(2))
        if let top = lines.max(by: { $0.score < $1.score }) {
            parts.append(top.item.title)
        }
        if parts.isEmpty { parts.append("张维为表情包") }
        var name = parts.joined(separator: "-")
        name = name.replacingOccurrences(of: " ", with: "")
        name = name.replacingOccurrences(of: "/", with: "_")
        if name.count > 24 { name = String(name.prefix(24)) }
        return name.isEmpty ? "ZVV表情包" : name
    }

    // MARK: - 选材

    private func selectDiverse(candidates: [MemeCandidate], count: Int) -> [MemeCandidate] {
        guard candidates.count > count else { return candidates }
        var picked: [MemeCandidate] = [candidates[0]]
        var remaining = Array(candidates.dropFirst())
        while picked.count < count, !remaining.isEmpty {
            var bestIndex = 0
            var bestValue = -Double.infinity
            for (index, candidate) in remaining.enumerated() {
                let redundancy = picked.map { similarity(candidate, $0) }.max() ?? 0
                let value = diversity * candidate.score - (1 - diversity) * redundancy
                if value > bestValue {
                    bestValue = value
                    bestIndex = index
                }
            }
            picked.append(remaining.remove(at: bestIndex))
        }
        return picked
    }

    private func similarity(_ lhs: MemeCandidate, _ rhs: MemeCandidate) -> Double {
        let lhsBigrams = MemeLibrary.bigrams(lhs.item.title)
        let rhsBigrams = MemeLibrary.bigrams(rhs.item.title)
        let union = lhsBigrams.union(rhsBigrams)
        let intersection = lhsBigrams.intersection(rhsBigrams)
        let lexical = union.isEmpty ? 0 : Double(intersection.count) / Double(union.count)
        let topicUnion = Set(lhs.item.topics).union(rhs.item.topics)
        let topicIntersection = Set(lhs.item.topics).intersection(rhs.item.topics)
        let topic = topicUnion.isEmpty ? 0 : Double(topicIntersection.count) / Double(topicUnion.count)
        let scoreGap = 1 - abs(lhs.score - rhs.score)
        return lexical * 0.45 + topic * 0.40 + scoreGap * 0.15
    }

    // MARK: - 排序

    private func sequence(_ items: [MemeCandidate]) -> [PlannedLine] {
        guard items.count > 1 else {
            return items.map { makeLine($0, role: .punchline) }
        }

        let opener = items.max { openerScore($0) < openerScore($1) } ?? items[0]
        let punchline = items
            .filter { $0.item.id != opener.item.id }
            .max { punchlineScore($0) + $0.score * 0.5 < punchlineScore($1) + $1.score * 0.5 }
            ?? items[items.count - 1]

        var middles = items.filter { $0.item.id != opener.item.id && $0.item.id != punchline.item.id }
        var ordered: [MemeCandidate] = [opener]
        var current = opener
        while !middles.isEmpty {
            var bestIndex = 0
            var bestValue = -Double.infinity
            for (index, candidate) in middles.enumerated() {
                let value = similarity(candidate, current) * 0.7 + candidate.score * 0.3
                if value > bestValue {
                    bestValue = value
                    bestIndex = index
                }
            }
            let next = middles.remove(at: bestIndex)
            ordered.append(next)
            current = next
        }
        if punchline.item.id != opener.item.id { ordered.append(punchline) }

        return ordered.enumerated().map { index, candidate in
            let role: LineRole
            if index == 0 {
                role = .opener
            } else if index == ordered.count - 1 {
                role = .punchline
            } else {
                role = .middle
            }
            return makeLine(candidate, role: role)
        }
    }

    private func makeLine(_ candidate: MemeCandidate, role: LineRole) -> PlannedLine {
        PlannedLine(
            item: candidate.item,
            line: candidate.item.title,
            subline: nil,
            score: candidate.score,
            role: role
        )
    }

    private func openerScore(_ candidate: MemeCandidate) -> Double {
        let openers = ["我觉得", "说实话", "坦率地讲", "大家", "人家", "我一直", "我老说", "我看了", "什么问题"]
        var score = candidate.score * 0.6
        if openers.contains(where: { candidate.item.title.hasPrefix($0) }) { score += 0.5 }
        if candidate.item.title.count > 14 { score += 0.1 }
        return score
    }

    private func punchlineScore(_ candidate: MemeCandidate) -> Double {
        let punchlines = ["难绷", "笑", "乐", "鼓掌", "震惊", "震撼", "完蛋", "投降", "输掉", "笑话", "自信", "大牙", "尴尬", "傻", "完了", "不屑"]
        var score = 0.0
        if punchlines.contains(where: { candidate.item.title.contains($0) }) { score += 0.7 }
        if candidate.item.title.count <= 8 { score += 0.2 }
        if !TopicLexicon.punchlineTones.isDisjoint(with: candidate.item.tones) { score += 0.25 }
        return score
    }
}
