import Foundation

/// 拼接方式
enum StitchMode: String, CaseIterable, Codable, Identifiable {
    case full
    case subtitle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "整图竖向拼接"
        case .subtitle: return "台词拼接"
        }
    }

    var detail: String {
        switch self {
        case .full: return "每张表情包整张等比缩放后自上而下拼接"
        case .subtitle: return "裁切每张表情包的中部画面，并把台词压成字幕条（参考台词拼接实例）"
        }
    }
}

/// 语义推理硬件
enum ComputeBackend: String, CaseIterable, Codable, Identifiable {
    case auto
    case gpu
    case cpu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "自动选择"
        case .gpu: return "GPU（Metal）"
        case .cpu: return "CPU（Accelerate）"
        }
    }

    var detail: String {
        switch self {
        case .auto: return "Apple 芯片自动走 GPU，无 GPU 时回退 CPU"
        case .gpu: return "使用 M 系列芯片 GPU 做向量相似度计算"
        case .cpu: return "使用 CPU 的 SIMD/Accelerate 指令做向量计算"
        }
    }
}

/// 语义理解来源
enum EngineMode: String, CaseIterable, Codable, Identifiable {
    case local
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .local: return "本地语义引擎"
        case .cloud: return "云端大模型"
        }
    }

    var detail: String {
        switch self {
        case .local: return "NaturalLanguage 句向量 + 关键词/主题打分，完全离线"
        case .cloud: return "调用 DeepSeek API 编排台词顺序，命中本地 skill 缓存时不发请求"
        }
    }
}

/// 台词在整段对话中的角色
enum LineRole: String, Codable {
    case opener
    case middle
    case punchline

    var title: String {
        switch self {
        case .opener: return "开场"
        case .middle: return "承接"
        case .punchline: return "收尾"
        }
    }
}

/// 素材库中的一张表情包
struct MemeItem: Identifiable, Hashable {
    let id: String
    let url: URL
    let title: String
    let tokens: [String]
    let topics: [String]
    let tones: [String]
    /// 空白模板等无台词的素材，默认不参与语义匹配
    let isTemplate: Bool

    var displayTitle: String { title }
}

/// 语义打分结果
struct MemeCandidate: Identifiable {
    let item: MemeItem
    let score: Double
    let embeddingScore: Double
    let lexicalScore: Double
    let topicScore: Double
    let reasons: [String]

    var id: String { item.id }
}

/// 最终进入拼接的一条台词
struct PlannedLine: Identifiable {
    let item: MemeItem
    let line: String
    let subline: String?
    let score: Double
    let role: LineRole

    var id: String { item.id }
}

/// 向量计算耗时信息（用于展示 GPU / CPU 差异）
struct BackendTiming {
    let backend: String
    let milliseconds: Double
    let rows: Int
    let columns: Int
    let drift: Double?

    var summary: String {
        var text = String(format: "%@  %.2f ms  (%d×%d)", backend, milliseconds, rows, columns)
        if let drift { text += String(format: "  双后端最大偏差 %.2e", drift) }
        return text
    }
}

/// 一次生成任务的完整方案
struct StitchPlan {
    let query: String
    let mode: StitchMode
    let lines: [PlannedLine]
    let semanticName: String
    let source: String
    let elapsed: Double
    let timing: BackendTiming?
    let cloudNote: String?
}

/// 已生成并缓存到磁盘的表情包
struct GenerationRecord: Codable, Identifiable, Hashable {
    let id: String
    let fileName: String
    let displayName: String
    let query: String
    let mode: String
    let source: String
    let createdAt: Date
    let itemTitles: [String]

    var modeTitle: String { StitchMode(rawValue: mode)?.title ?? mode }
}

/// 设置页使用的轻量提示
struct StatusMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool

    static func info(_ text: String) -> StatusMessage { StatusMessage(text: text, isError: false) }
    static func error(_ text: String) -> StatusMessage { StatusMessage(text: text, isError: true) }
}
