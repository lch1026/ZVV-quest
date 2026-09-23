import Foundation

enum CloudError: LocalizedError {
    case missingAPIKey
    case invalidURL(String)
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "还没有填写 API Key，请到设置里填写 DeepSeek API Key"
        case .invalidURL(let value): return "接口地址不合法：\(value)"
        case .http(let code, let message): return "接口返回 HTTP \(code)：\(message)"
        case .decoding(let message): return "模型返回的内容不是预期的 json：\(message)"
        case .transport(let message): return "网络请求失败：\(message)"
        }
    }
}

/// 云端语义编排：一次请求完成“挑素材 + 排序 + 起名字”，尽量少调用 API。
final class CloudPlanner {
    struct Outcome {
        let lines: [PlannedLine]
        let semanticName: String?
        let note: String
    }

    private let cache = SkillCache()

    var cacheCount: Int { cache.entryCount }
    func clearCache() { cache.clear() }

    func plan(
        query: String,
        mode: StitchMode,
        candidates: [MemeCandidate],
        count: Int,
        settings: AppSettings
    ) async throws -> Outcome {
        let shortlist = Array(candidates.prefix(80))
        guard !shortlist.isEmpty else { throw CloudError.decoding("本地没有可用素材") }

        let key = cache.key(query: query, model: settings.cloudModel, count: count, mode: mode)
        if settings.useSkillCache, let entry = cache.lookup(key: key) {
            if let outcome = materialize(entry: entry, shortlist: shortlist, count: count) {
                return Outcome(
                    lines: outcome,
                    semanticName: entry.name,
                    note: "命中本地 skill 缓存（第 \(entry.hits + 1) 次复用），本次没有调用云端 API"
                )
            }
        }

        guard !settings.cloudAPIKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw CloudError.missingAPIKey
        }

        let prompt = SkillPrompt.resolve(settingsPath: settings.skillPromptPath)
        let payload = try await request(
            query: query,
            mode: mode,
            shortlist: shortlist,
            count: count,
            systemPrompt: prompt.text,
            settings: settings
        )

        var lines: [PlannedLine] = []
        for item in payload.sequence {
            guard item.index >= 0, item.index < shortlist.count else { continue }
            let candidate = shortlist[item.index]
            if lines.contains(where: { $0.item.id == candidate.item.id }) { continue }
            let line = item.line.isEmpty ? candidate.item.title : item.line
            lines.append(
                PlannedLine(
                    item: candidate.item,
                    line: line,
                    subline: item.english.isEmpty ? nil : item.english,
                    score: candidate.score,
                    role: .middle
                )
            )
        }
        guard !lines.isEmpty else { throw CloudError.decoding("模型没有返回可用的素材序号") }

        if settings.useSkillCache {
            cache.store(
                key: key,
                query: query,
                model: settings.cloudModel,
                name: payload.name ?? "",
                sequence: payload.sequence
            )
        }

        let styled = restyle(lines)
        return Outcome(
            lines: styled,
            semanticName: payload.name,
            note: "已调用 \(settings.cloudModel) 完成编排（提示词来源：\(prompt.source)）"
        )
    }

    /// 缓存里存的是素材序号，重新落到候选列表上
    private func materialize(entry: SkillCache.Entry, shortlist: [MemeCandidate], count: Int) -> [PlannedLine]? {
        var lines: [PlannedLine] = []
        for item in entry.sequence {
            guard item.index >= 0, item.index < shortlist.count else { continue }
            let candidate = shortlist[item.index]
            if lines.contains(where: { $0.item.id == candidate.item.id }) { continue }
            lines.append(
                PlannedLine(
                    item: candidate.item,
                    line: item.line.isEmpty ? candidate.item.title : item.line,
                    subline: item.english.isEmpty ? nil : item.english,
                    score: candidate.score,
                    role: .middle
                )
            )
        }
        guard !lines.isEmpty else { return nil }
        return restyle(lines)
    }

    private func restyle(_ lines: [PlannedLine]) -> [PlannedLine] {
        lines.enumerated().map { index, line in
            let role: LineRole
            if index == 0 {
                role = .opener
            } else if index == lines.count - 1 {
                role = .punchline
            } else {
                role = .middle
            }
            return PlannedLine(
                item: line.item,
                line: line.line,
                subline: line.subline,
                score: line.score,
                role: role
            )
        }
    }

    // MARK: - 网络

    private struct Payload: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct PlanResponse: Decodable {
        struct Item: Decodable {
            let index: Int
            let line: String?
            let en: String?
        }
        let name: String?
        let sequence: [Item]
    }

    private func request(
        query: String,
        mode: StitchMode,
        shortlist: [MemeCandidate],
        count: Int,
        systemPrompt: String,
        settings: AppSettings
    ) async throws -> (name: String?, sequence: [SkillCache.SequenceItem]) {
        let base = settings.cloudBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        if trimmed.isEmpty { trimmed = AppSettings.defaultBaseURL }
        guard let url = URL(string: trimmed + "/chat/completions") else {
            throw CloudError.invalidURL(settings.cloudBaseURL)
        }

        let listText = shortlist.enumerated()
            .map { "\($0.offset). \($0.element.item.title)" }
            .joined(separator: "\n")

        let userPrompt = """
        用户输入：\(query)
        拼接方式：\(mode.title)
        需要段数：\(count)

        素材清单（序号. 台词）：
        \(listText)

        请按系统提示的 json 格式输出结果，sequence 长度必须等于 \(count)，index 只能取自上面的序号。
        """

        var body: [String: Any] = [
            "model": settings.cloudModel,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "response_format": ["type": "json_object"],
            "temperature": 0.8,
            "max_tokens": 2000,
            "stream": false,
        ]
        if settings.cloudThinking {
            body["thinking"] = ["type": "enabled"]
            body["reasoning_effort"] = "low"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(settings.cloudAPIKey.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CloudError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw CloudError.http(http.statusCode, String(message.prefix(300)))
        }

        let decoded: Payload
        do {
            decoded = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw CloudError.decoding(error.localizedDescription)
        }
        let content = decoded.choices.first?.message.content ?? ""
        let json = CloudPlanner.extractJSON(from: content)
        guard let jsonData = json.data(using: .utf8) else {
            throw CloudError.decoding("返回内容为空")
        }
        let plan: PlanResponse
        do {
            plan = try JSONDecoder().decode(PlanResponse.self, from: jsonData)
        } catch {
            throw CloudError.decoding(String(json.prefix(200)))
        }
        let sequence = plan.sequence.map { SkillCache.SequenceItem(index: $0.index, line: $0.line ?? "", english: $0.en ?? "") }
        return (plan.name, sequence)
    }

    /// 兜底：模型偶尔会在 json 外面包一层说明文字
    static func extractJSON(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return text }
        return String(text[start...end])
    }
}
