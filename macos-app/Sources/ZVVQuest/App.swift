import SwiftUI

@main
enum EntryPoint {
    static func main() {
        if CommandLine.arguments.contains(where: { $0 == "--generate" || $0 == "--help" || $0 == "-h" }) {
            CLI.run()
            exit(0)
        }
        ZVVQuestApp.main()
    }
}

struct ZVVQuestApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var coordinator = GenerationCoordinator()
    @StateObject private var monitor = HardwareMonitor()

    var body: some Scene {
        Window("ZVV 连续对话表情包生成器", id: "main") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(coordinator)
                .environmentObject(monitor)
        }
        .defaultSize(width: 1240, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("生成") {
                Button("清空预览") { coordinator.clearResult() }
                    .keyboardShortcut("k", modifiers: [.command])
                Button("刷新图库") { coordinator.store.reload() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
