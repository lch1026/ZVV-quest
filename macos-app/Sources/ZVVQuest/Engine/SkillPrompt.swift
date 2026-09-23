import Foundation

/// 云端编排使用的提示词。
/// 优先读取项目里 xcode-tools/skills/zvv-meme/prompt.md（本地 skill），
/// 这样 App 和 Codex 插件共用同一份语义规则，也可以直接编辑 md 调整效果。
enum SkillPrompt {
    static let builtIn = """
    你是张维为表情包（ZVV）的台词编排助手。用户会给出一句中文，你要从给定的素材清单里挑选合适的表情包，
    把它们排成一段读起来连贯的“连续对话”，让整段拼接图能准确表达用户那句话的意思。

    要求：
    1. 只能使用清单中给出的素材序号，不能编造素材。
    2. 数量必须严格等于用户要求的段数。
    3. 顺序要有节奏：第一句像开场，中间层层递进，最后一句是最有梗、最点题的一句。
    4. 相邻两句最好属于同一话题，读起来像同一个人的连续发言。
    5. line 字段默认照抄素材原台词；只有在明显更贴合用户语境时才做极轻微润色，不能改变原意。
    6. en 字段给出该句的英文翻译（简短、口语化）；如果无法翻译就留空字符串。
    7. name 字段给这个拼接图起一个符合语义的中文短名字（不超过 12 个字，不要包含空格和斜杠）。

    输出必须是一个 json 对象，格式如下（不要输出任何额外文字）：
    {
      "name": "美国自信的真相",
      "sequence": [
        {"index": 12, "line": "我觉得这就是一种自信", "en": "I think this is a kind of confidence"},
        {"index": 45, "line": "这个盒饭确实比美国中产阶级吃的好", "en": "This boxed meal really beats the American middle class"}
      ]
    }
    """

    static func resolve(settingsPath: String) -> (text: String, source: String) {
        var candidates: [URL] = []
        if !settingsPath.isEmpty {
            candidates.append(URL(fileURLWithPath: settingsPath))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("skill/prompt.md"))
        }
        var current = Bundle.main.bundleURL
        for _ in 0..<4 {
            current = current.deletingLastPathComponent()
            candidates.append(current.appendingPathComponent("xcode-tools/skills/zvv-meme/prompt.md"))
        }
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (text, url.path)
            }
        }
        return (builtIn, "内置提示词")
    }
}
