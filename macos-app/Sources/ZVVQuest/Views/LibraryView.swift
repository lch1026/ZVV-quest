import SwiftUI
import AppKit

/// 缓存的生成结果：浏览、复制、删除
struct LibraryView: View {
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @State private var selection: Set<String> = []
    @State private var confirmingClear = false

    private var records: [GenerationRecord] { coordinator.store.records }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已保存的表情包").font(.headline)
                Text("\(records.count) 张").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    coordinator.store.reload()
                } label: { Label("刷新", systemImage: "arrow.clockwise") }
                Button {
                    Clipboard.open(coordinator.store.directory)
                } label: { Label("打开缓存目录", systemImage: "folder") }
                Button(role: .destructive) {
                    confirmingClear = true
                } label: { Label("全部删除", systemImage: "trash") }
                    .disabled(records.isEmpty)
            }

            if !selection.isEmpty {
                HStack(spacing: 8) {
                    Text("已选 \(selection.count) 张").font(.caption)
                    Button("复制所选") {
                        let images: [NSImage] = selection.compactMap { id in
                            guard let record = records.first(where: { $0.id == id }) else { return nil }
                            return NSImage(contentsOf: coordinator.store.url(for: record))
                        }
                        guard !images.isEmpty else { return }
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.writeObjects(images)
                    }
                    Button("删除所选", role: .destructive) {
                        coordinator.store.delete(ids: selection)
                        selection.removeAll()
                    }
                    Spacer()
                    Button("取消选择") { selection.removeAll() }
                }
            }

            if records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(.tertiary)
                    Text("缓存目录里还没有文件").foregroundStyle(.secondary)
                    Text(coordinator.store.directory.path).font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
                        ForEach(records) { record in
                            thumbnail(record)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .onAppear { coordinator.store.reload() }
        .confirmationDialog("确定删除缓存目录里的全部表情包吗？", isPresented: $confirmingClear) {
            Button("全部删除", role: .destructive) {
                selection.removeAll()
                coordinator.store.deleteAll()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func thumbnail(_ record: GenerationRecord) -> some View {
        let url = coordinator.store.url(for: record)
        let selected = selection.contains(record.id)
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(height: 150)
            .clipped()
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2 : 1))

            Text(record.displayName).font(.caption).lineLimit(1)
            Text("\(record.modeTitle) · \(record.itemTitles.count) 段").font(.caption2).foregroundStyle(.secondary)
            Text(record.createdAt.formatted(date: .numeric, time: .shortened))
                .font(.caption2).foregroundStyle(.tertiary)
            HStack(spacing: 6) {
                Button(selected ? "取消" : "选择") {
                    if selected { selection.remove(record.id) } else { selection.insert(record.id) }
                }
                .font(.caption2)
                Button("复制") {
                    guard let data = try? Data(contentsOf: url) else { return }
                    _ = Clipboard.copy(pngData: data)
                }
                .font(.caption2)
                Button("删除", role: .destructive) {
                    selection.remove(record.id)
                    coordinator.store.delete(record)
                }
                .font(.caption2)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }
}
