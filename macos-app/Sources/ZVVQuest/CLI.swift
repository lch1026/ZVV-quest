import Foundation
import AppKit

/// 命令行入口：让脚本 / Codex 插件可以直接复用同一套语义引擎与渲染器。
/// 例：ZVVQuest --generate "美国生活水平很差" --mode subtitle --count 6 --out /tmp/a.png
enum CLI {
    struct Options {
        var query: String = ""
        var mode: StitchMode = .subtitle
        var count: Int = 6
        var engine: EngineMode = .local
        var backend: ComputeBackend = .auto
        var output: String = ""
        var library: String = ""
        var width: Int = 720
        var json: Bool = false
        var files: [String] = []
        var subtitles: [String] = []
    }

    static func run() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") || arguments.contains("-h") || arguments.isEmpty {
            printUsage()
            return
        }
        guard let options = parse(arguments) else {
            printUsage()
            return
        }
        if options.query.isEmpty {
            FileHandle.standardError.write(Data("缺少句子：--generate \"一句话\"\n".utf8))
            printUsage()
            return
        }

        let settings = AppSettings.shared
        settings.maxImages = min(max(options.count, 1), settings.maxImagesLimit)
        settings.stitchMode = options.mode
        settings.engine = options.engine
        settings.backend = options.backend
        settings.canvasWidth = options.width
        settings.autoCopyToPasteboard = false
        if !options.library.isEmpty { settings.libraryPath = options.library }

        guard let directory = LibraryLocator.resolve(settingsPath: settings.libraryPath) else {
            FileHandle.standardError.write(Data("找不到素材库，请用 --library 指定 vv 目录\n".utf8))
            return
        }

        let library = MemeLibrary()
        do {
            try library.load(from: directory)
        } catch {
            FileHandle.standardError.write(Data("素材库读取失败：\(error.localizedDescription)\n".utf8))
            return
        }

        var planner = DialoguePlanner()
        planner.maxImages = settings.maxImages

        var lines: [PlannedLine] = []
        var timing: BackendTiming?
        var ranking: [MemeCandidate] = []

        if !options.files.isEmpty {
            // 显式指定素材（Codex 插件按语义挑好素材后走这条路）
            lines = options.files.enumerated().compactMap { index, path -> PlannedLine? in
                let expanded = (path as NSString).expandingTildeInPath
                let url = expanded.hasPrefix("/")
                    ? URL(fileURLWithPath: expanded)
                    : directory.appendingPathComponent(expanded)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                let title = options.subtitles.indices.contains(index) && !options.subtitles[index].isEmpty
                    ? options.subtitles[index]
                    : url.deletingPathExtension().lastPathComponent
                let item = library.items.first { $0.url.path == url.path }
                    ?? MemeItem(
                        id: url.path,
                        url: url,
                        title: title,
                        tokens: MemeLibrary.tokenize(title),
                        topics: TopicLexicon.matchTopics(in: title),
                        tones: TopicLexicon.matchTones(in: title),
                        isTemplate: false
                    )
                let role: LineRole = index == 0 ? .opener : (index == options.files.count - 1 ? .punchline : .middle)
                return PlannedLine(item: item, line: title, subline: nil, score: 0, role: role)
            }
            if lines.isEmpty {
                FileHandle.standardError.write(Data("--files 里的文件都找不到\n".utf8))
                return
            }
        } else {
            let engine = SemanticEngine()
            engine.buildIndex(items: library.items)
            let ranked = engine.rank(query: options.query, backend: options.backend)
            ranking = ranked.candidates
            timing = ranked.timing
            lines = planner.plan(query: options.query, candidates: ranked.candidates)
        }
        guard !lines.isEmpty else {
            FileHandle.standardError.write(Data("没有匹配到任何素材\n".utf8))
            return
        }

        let name = planner.semanticName(
            query: options.query,
            lines: lines,
            topics: TopicLexicon.matchTopics(in: TopicLexicon.normalized(options.query))
        )
        let plan = StitchPlan(
            query: options.query,
            mode: options.mode,
            lines: lines,
            semanticName: name,
            source: options.files.isEmpty ? "本地语义引擎" : "外部指定素材",
            elapsed: 0,
            timing: timing,
            cloudNote: nil
        )

        do {
            let output = try MemeRenderer.render(plan: plan, settings: settings)
            let target: URL
            if options.output.isEmpty {
                let directory = URL(fileURLWithPath: settings.cacheDirectory, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                target = directory.appendingPathComponent("ZVV-\(GenerationStore.sanitize(name)).png")
            } else {
                target = URL(fileURLWithPath: (options.output as NSString).expandingTildeInPath)
            }
            try output.pngData.write(to: target, options: .atomic)

            if options.json {
                let payload: [String: Any] = [
                    "query": options.query,
                    "name": name,
                    "mode": options.mode.rawValue,
                    "output": target.path,
                    "size": ["width": Int(output.pixelSize.width), "height": Int(output.pixelSize.height)],
                    "backend": timing?.backend ?? "未使用向量后端",
                    "lines": lines.map { ["file": $0.item.url.path, "title": $0.item.title, "role": $0.role.rawValue, "subline": $0.subline ?? ""] },
                    "candidates": ranking.prefix(10).map { ["file": $0.item.url.path, "title": $0.item.title, "score": $0.score] },
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
                   let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            } else {
                print("句子：\(options.query)")
                print("命名：\(name)   模式：\(options.mode.title)   段数：\(lines.count)")
                for (index, line) in lines.enumerated() {
                    print(String(format: "%2d. [%@] %@  (%.2f)", index + 1, line.role.title, line.line, line.score))
                }
                print("输出：\(target.path)  \(Int(output.pixelSize.width))×\(Int(output.pixelSize.height))")
            }
        } catch {
            FileHandle.standardError.write(Data("渲染失败：\(error.localizedDescription)\n".utf8))
        }
    }

    private static func parse(_ arguments: [String]) -> Options? {
        var options = Options()
        var index = 0
        func next(_ key: String) -> String? {
            guard index + 1 < arguments.count else {
                FileHandle.standardError.write(Data("参数 \(key) 缺少取值\n".utf8))
                return nil
            }
            index += 1
            return arguments[index]
        }
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--generate":
                guard let value = next(argument) else { return nil }
                options.query = value
            case "--mode":
                guard let value = next(argument), let mode = StitchMode(rawValue: value) else { return nil }
                options.mode = mode
            case "--count":
                guard let value = next(argument), let count = Int(value) else { return nil }
                options.count = count
            case "--engine":
                guard let value = next(argument), let engine = EngineMode(rawValue: value) else { return nil }
                options.engine = engine
            case "--backend":
                guard let value = next(argument), let backend = ComputeBackend(rawValue: value) else { return nil }
                options.backend = backend
            case "--out":
                guard let value = next(argument) else { return nil }
                options.output = value
            case "--library":
                guard let value = next(argument) else { return nil }
                options.library = value
            case "--width":
                guard let value = next(argument), let width = Int(value) else { return nil }
                options.width = width
            case "--json":
                options.json = true
            case "--files":
                guard let value = next(argument) else { return nil }
                options.files = value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            case "--subtitles":
                guard let value = next(argument) else { return nil }
                options.subtitles = value.components(separatedBy: "|")
            default:
                if !argument.hasPrefix("-") { options.query = argument }
            }
            index += 1
        }
        return options
    }

    private static func printUsage() {
        print("""
        ZVV 连续对话表情包生成器 · 命令行模式

        用法：
          ZVVQuest --generate "一句话" [选项]

        选项：
          --mode     full | subtitle        拼接方式（默认 subtitle）
          --count    1-15                   台词段数（默认 6）
          --engine   local | cloud          语义来源（默认 local）
          --backend  auto | gpu | cpu       推理硬件（默认 auto）
          --out      /path/out.png          输出路径（默认写入缓存目录）
          --library  /path/to/vv            素材目录
          --width    480-1440               画布宽度
          --files    a.png,b.png            直接指定素材（按给定顺序拼接）
          --subtitles "台词1|台词2"          覆盖素材自带的台词
          --json                            以 json 输出结果
          --help                            显示帮助
        """)
    }
}
