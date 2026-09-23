import Foundation
import AppKit
import ImageIO

enum ImageLoader {
    /// 用 ImageIO 直接解码缩略图，避免把大图整张读进内存
    static func thumbnail(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func aspectRatio(of url: URL) -> Double? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else { return nil }
        return width / height
    }
}

enum TextStyle {
    static func font(size: CGFloat, weight: NSFont.Weight = .semibold) -> NSFont {
        if let font = NSFont(name: "PingFang SC Semibold", size: size) { return font }
        if let font = NSFont(name: "PingFang SC", size: size) { return font }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// 白字黑边，和常见的台词字幕一致
    static func subtitle(_ text: String, size: CGFloat, strokeWidth: CGFloat = 4) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        return NSAttributedString(string: text, attributes: [
            .font: font(size: size),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -strokeWidth,
            .paragraphStyle: paragraph,
        ])
    }

    static func secondary(_ text: String, size: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: font(size: size, weight: .regular),
            .foregroundColor: NSColor(white: 0.94, alpha: 1),
            .strokeColor: NSColor.black,
            .strokeWidth: -3,
            .paragraphStyle: paragraph,
        ])
    }

    static func caption(_ text: String, size: CGFloat, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        return NSAttributedString(string: text, attributes: [
            .font: font(size: size, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
    }

    /// 逐级缩小字号直到文字能放进给定宽高
    static func fittingSubtitle(_ text: String, maxWidth: CGFloat, maxHeight: CGFloat, startSize: CGFloat) -> NSAttributedString {
        var size = startSize
        while size > 12 {
            let candidate = subtitle(text, size: size)
            let bounds = candidate.boundingRect(
                with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            if bounds.height <= maxHeight, bounds.width <= maxWidth + 1 {
                return candidate
            }
            size -= 2
        }
        return subtitle(text, size: 12)
    }

    static func boundingSize(_ string: NSAttributedString, maxWidth: CGFloat) -> CGSize {
        string.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
    }
}

enum RenderError: LocalizedError {
    case emptyPlan
    case bitmapAllocationFailed
    case encodingFailed
    case imageUnreadable(String)

    var errorDescription: String? {
        switch self {
        case .emptyPlan: return "没有可用的台词，无法生成拼接图"
        case .bitmapAllocationFailed: return "位图分配失败（拼接尺寸过大）"
        case .encodingFailed: return "PNG 编码失败"
        case .imageUnreadable(let name): return "图片无法解码：\(name)"
        }
    }
}
