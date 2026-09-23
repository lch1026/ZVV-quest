import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case compose
    case library
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compose: return "生成"
        case .library: return "图库"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .compose: return "wand.and.stars"
        case .library: return "photo.stack"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var coordinator: GenerationCoordinator
    @EnvironmentObject private var monitor: HardwareMonitor
    @State private var section: AppSection = .compose

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                detail
                Divider()
                MonitorStrip()
                    .environmentObject(monitor)
            }
        }
        .frame(minWidth: 1120, minHeight: 760)
        .onAppear {
            monitor.start()
            coordinator.prepareLibrary()
        }
        .onDisappear { monitor.stop() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ZVV")
                .font(.system(size: 22, weight: .heavy))
                .padding(.top, 18)
            Text("连续对话表情包生成器")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)

            ForEach(AppSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon).frame(width: 18)
                        Text(item.title)
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(section == item ? Color.accentColor.opacity(0.20) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text("素材库").font(.caption).foregroundStyle(.secondary)
                Text(coordinator.libraryInfo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 14)
        .frame(width: 208)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .compose:
            ComposeView()
                .environmentObject(settings)
                .environmentObject(coordinator)
        case .library:
            LibraryView()
                .environmentObject(coordinator)
        case .settings:
            SettingsView()
                .environmentObject(settings)
                .environmentObject(coordinator)
        }
    }
}
