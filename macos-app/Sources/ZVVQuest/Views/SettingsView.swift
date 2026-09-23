import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @State private var selfTestResult: String = ""
    @State private var cloudTestResult: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                librarySection
                renderSection
                semanticsSection
                cloudSection
                storageSection
                aboutSection
            }
            .padding(16)
        }
    }

    private var librarySection: some View {
        GroupBox("素材库") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(settings.libraryPath.isEmpty ? "自动查找（App 内置 / 项目 vv 目录）" : settings.libraryPath)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("选择目录…") { pickDirectory { settings.libraryPath = $0 } }
                    Button("自动查找") {
                        settings.libraryPath = ""
                        coordinator.prepareLibrary(force: true)
                    }
                    Button("重新索引") { coordinator.prepareLibrary(force: true) }
                }
                Text(coordinator.libraryInfo).font(.caption2).foregroundStyle(.tertiary)
                Text("素材含义取自文件名，空白 / 万能模板类素材默认不参与匹配。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
        }
    }

    private var renderSection: some View {
        GroupBox("拼接参数") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("画布宽度").frame(width: 96, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(settings.canvasWidth) },
                        set: { settings.canvasWidth = Int($0) }
                    ), in: 480...1440, step: 20)
                    Text("\(settings.canvasWidth) px").font(.caption.monospacedDigit())
                }
                HStack {
                    Text("整图间距").frame(width: 96, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(settings.imageGap) },
                        set: { settings.imageGap = Int($0) }
                    ), in: 0...40, step: 2)
                    Text("\(settings.imageGap) px").font(.caption.monospacedDigit())
                }
                HStack {
                    Text("字幕字号").frame(width: 96, alignment: .leading)
                    Slider(value: $settings.subtitleFontSize, in: 18...64, step: 2)
                    Text("\(Int(settings.subtitleFontSize)) pt").font(.caption.monospacedDigit())
                }
                HStack {
                    Text("裁切比例").frame(width: 96, alignment: .leading)
                    Slider(value: $settings.subtitleBandRatio, in: 0.3...1.0, step: 0.05)
                    Text(String(format: "%.0f%%", settings.subtitleBandRatio * 100))
                        .font(.caption.monospacedDigit())
                }
                Toggle("生成后自动复制到剪贴板", isOn: $settings.autoCopyToPasteboard)
            }
            .padding(.top, 2)
        }
    }

    private var semanticsSection: some View {
        GroupBox("语义与硬件") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("默认理解来源", selection: $settings.engine) {
                    ForEach(EngineMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                Picker("默认推理硬件", selection: $settings.backend) {
                    ForEach(ComputeBackend.allCases) { backend in Text(backend.title).tag(backend) }
                }
                .pickerStyle(.segmented)
                Text("本地向量后端：\(coordinator.engine.vectorDescription) · Metal 设备：\(MetalCosineKernel.shared.deviceName)")
                    .font(.caption2).foregroundStyle(.secondary)
                if let loadError = MetalCosineKernel.shared.loadError {
                    Text("Metal 内核不可用：\(loadError)").font(.caption2).foregroundStyle(.orange)
                }
                HStack {
                    Button("运行 GPU / CPU 一致性自检") {
                        selfTestResult = coordinator.runBackendSelfTest()
                    }
                    if !selfTestResult.isEmpty {
                        Text(selfTestResult).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var cloudSection: some View {
        GroupBox("云端大模型（DeepSeek）") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("接口地址").frame(width: 96, alignment: .leading)
                    TextField("https://api.deepseek.com", text: $settings.cloudBaseURL)
                }
                HStack {
                    Text("模型").frame(width: 96, alignment: .leading)
                    TextField("deepseek-flash", text: $settings.cloudModel)
                }
                HStack {
                    Text("API Key").frame(width: 96, alignment: .leading)
                    SecureField("sk-…", text: $settings.cloudAPIKey)
                }
                Toggle("开启 thinking（更慢但更会挑梗）", isOn: $settings.cloudThinking)
                Toggle("启用本地 skill 缓存（同一句话不重复调用 API）", isOn: $settings.useSkillCache)
                HStack {
                    Text("skill 提示词").frame(width: 96, alignment: .leading)
                    Text(settings.skillPromptPath.isEmpty ? "内置提示词（可指向 xcode-tools/skills/zvv-meme/prompt.md）" : settings.skillPromptPath)
                        .font(.caption).lineLimit(2).foregroundStyle(.secondary)
                    Spacer()
                    Button("选择…") { pickFile { settings.skillPromptPath = $0 } }
                }
                HStack {
                    Button("清空 skill 缓存（当前 \(coordinator.cloud.cacheCount) 条）") {
                        coordinator.cloud.clearCache()
                    }
                    if !cloudTestResult.isEmpty {
                        Text(cloudTestResult).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("云端模式只把「用户句子 + 本地筛出的候选台词清单」发出去，一次请求完成挑选与排序，配合本地缓存进一步降低调用次数。")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var storageSection: some View {
        GroupBox("缓存目录") {
            VStack(alignment: .leading, spacing: 8) {
                Text(settings.cacheDirectory).font(.caption).lineLimit(2).foregroundStyle(.secondary)
                HStack {
                    Button("打开") { Clipboard.open(URL(fileURLWithPath: settings.cacheDirectory)) }
                    Button("选择…") { pickDirectory { settings.cacheDirectory = $0 } }
                    Button("恢复默认") {
                        settings.cacheDirectory = AppPaths.defaultCacheDirectory.path
                        coordinator.store.reload()
                    }
                    Button("刷新列表") { coordinator.store.reload() }
                }
                Text("生成的表情包按语义命名保存在这里，可在「图库」里浏览和删除。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
        }
    }

    private var aboutSection: some View {
        GroupBox("关于") {
            VStack(alignment: .leading, spacing: 6) {
                Text("ZVV 连续对话表情包生成器 · 本地版").font(.caption).bold()
                Text("素材含义来源：vv 素材目录的文件名。本地语义 = 系统 NaturalLanguage 句向量 + 关键词 + 主题词典。")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("开源协议：MIT。第三方代码引用情况见仓库根目录 THIRD-PARTY.md。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
    }

    private func pickDirectory(_ handler: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { handler(url.path) }
    }

    private func pickFile(_ handler: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.plainText, .text]
        if panel.runModal() == .OK, let url = panel.url { handler(url.path) }
    }
}
