import SwiftUI
import AppKit

struct ComposeView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @State private var query: String = ""

    private let samples = [
        "美国人的生活水平其实没有想象中那么好",
        "我们的制度优势是实实在在的",
        "西方媒体的双标已经到了可笑的地步",
        "中国年轻人的自信超出预期",
    ]

    var body: some View {
        HSplitView {
            inputColumn
                .frame(minWidth: 400, idealWidth: 430, maxWidth: 520)
            resultColumn
                .frame(minWidth: 420)
        }
        .padding(14)
    }

    // MARK: - 左栏

    private var inputColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("输入一句话").font(.headline)
            TextEditor(text: $query)
                .font(.system(size: 14))
                .frame(minHeight: 96)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))

            HStack(spacing: 6) {
                ForEach(samples, id: \.self) { sample in
                    Button {
                        query = sample
                    } label: {
                        Text(sample.prefix(12) + "…")
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }

            GroupBox("拼接方式") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $settings.stitchMode) {
                        ForEach(StitchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(settings.stitchMode.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            GroupBox("语义设置") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("台词段数", selection: $settings.maxImages) {
                        ForEach(1...settings.maxImagesLimit, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("单次拼接上限 \(settings.maxImagesLimit) 张，避免生成图片过大")
                        .font(.caption2).foregroundStyle(.secondary)

                    Picker("理解来源", selection: $settings.engine) {
                        ForEach(EngineMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.engine.detail)
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("推理硬件", selection: $settings.backend) {
                        ForEach(ComputeBackend.allCases) { backend in Text(backend.title).tag(backend) }
                    }
                    .pickerStyle(.segmented)
                    Text("\(settings.backend.detail) · 当前设备：\(VectorMath.backendName(VectorMath.effectiveBackend(settings.backend)))")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }

            HStack {
                Button {
                    coordinator.generate(query: query)
                } label: {
                    Label(coordinator.isWorking ? "生成中…" : "生成连续对话表情包", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.isWorking || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if coordinator.isWorking || coordinator.progress > 0 {
                ProgressView(value: coordinator.progress)
                Text(coordinator.statusText).font(.caption).foregroundStyle(.secondary)
            }

            if let error = coordinator.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            semanticBreakdown
            Spacer(minLength: 0)
        }
    }

    private var semanticBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("语义打分 Top 8").font(.subheadline).bold()
                Spacer()
                if let timing = coordinator.timingSummary {
                    Text(timing).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if coordinator.candidates.isEmpty {
                Text("生成一次后这里会显示本地语义理解的结果，方便判断是否选错了素材。")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(coordinator.candidates.prefix(8)) { candidate in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(candidate.item.title).font(.caption).lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.2f", candidate.score))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.secondary.opacity(0.15))
                                        Capsule()
                                            .fill(Color.accentColor.opacity(0.75))
                                            .frame(width: geo.size.width * min(1, max(0.02, candidate.score)))
                                    }
                                }
                                .frame(height: 4)
                                Text(candidate.reasons.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
    }

    // MARK: - 右栏

    private var resultColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("生成结果").font(.headline)
                Spacer()
                if let record = coordinator.lastRecord {
                    Text(record.displayName).font(.caption).foregroundStyle(.secondary)
                }
            }

            if let data = coordinator.lastPNG, let image = NSImage(data: data) {
                ScrollView([.vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .cornerRadius(6)
                        .shadow(radius: 4)
                        .padding(.bottom, 8)
                }
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))

                if let note = coordinator.noteMessage {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let plan = coordinator.lastPlan {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(plan.lines) { line in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.role.title).font(.system(size: 9)).foregroundStyle(.secondary)
                                    Text(line.line).font(.caption).lineLimit(2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                                .frame(width: 148, alignment: .leading)
                            }
                        }
                    }
                    .frame(height: 62)
                }

                HStack(spacing: 8) {
                    Button {
                        _ = coordinator.copyLastResult()
                    } label: {
                        Label("复制到剪贴板", systemImage: "doc.on.doc")
                    }
                    if let record = coordinator.lastRecord {
                        Button {
                            Clipboard.reveal(coordinator.store.url(for: record))
                        } label: {
                            Label("在访达中显示", systemImage: "folder")
                        }
                    }
                    Button {
                        Clipboard.open(coordinator.store.directory)
                    } label: {
                        Label("打开缓存目录", systemImage: "shippingbox")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        coordinator.clearResult()
                    } label: {
                        Label("清空预览", systemImage: "xmark.circle")
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42))
                        .foregroundStyle(.tertiary)
                    Text("还没有生成结果").foregroundStyle(.secondary)
                    Text("左边写一句话，点「生成连续对话表情包」即可")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            }
        }
    }
}
