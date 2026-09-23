import AppKit

enum Clipboard {
    /// 把生成的图片写入系统剪贴板
    @discardableResult
    static func copy(pngData: Data) -> Bool {
        guard let image = NSImage(data: pngData) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
