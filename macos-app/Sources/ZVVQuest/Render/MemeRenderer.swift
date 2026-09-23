import Foundation
import AppKit

/// 拼接渲染器：整图竖向拼接 / 台词拼接两种模式
enum MemeRenderer {
    struct Output {
        let pngData: Data
        let pixelSize: CGSize
    }

    static func render(plan: StitchPlan, settings: AppSettings, progress: ((Double) -> Void)? = nil) throws -> Output {
        guard !plan.lines.isEmpty else { throw RenderError.emptyPlan }
        switch plan.mode {
        case .full:
            return try renderFull(plan: plan, settings: settings, progress: progress)
        case .subtitle:
            return try renderSubtitle(plan: plan, settings: settings, progress: progress)
        }
    }

    // MARK: - 整图竖向拼接

    private static func renderFull(plan: StitchPlan, settings: AppSettings, progress: ((Double) -> Void)?) throws -> Output {
        let width = max(240, settings.canvasWidth)
        let gap = max(0, settings.imageGap)
        var images: [(CGImage, Int, Int)] = []

        for (index, line) in plan.lines.enumerated() {
            guard let image = ImageLoader.thumbnail(url: line.item.url, maxPixelSize: width * 2) else {
                throw RenderError.imageUnreadable(line.item.title)
            }
            let height = max(1, Int(Double(width) * Double(image.height) / Double(image.width)))
            images.append((image, width, height))
            progress?(Double(index + 1) / Double(plan.lines.count) * 0.7)
        }

        let totalHeight = images.reduce(0) { $0 + $1.2 } + gap * max(0, images.count - 1)
        guard let rep = makeBitmap(width: width, height: totalHeight) else { throw RenderError.bitmapAllocationFailed }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw RenderError.bitmapAllocationFailed }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.setFillColor(NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.07, alpha: 1).cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))

        var y = totalHeight
        for (image, imageWidth, imageHeight) in images {
            y -= imageHeight
            let rect = CGRect(x: 0, y: y, width: imageWidth, height: imageHeight)
            cg.saveGState()
            cg.interpolationQuality = .high
            cg.draw(image, in: rect)
            cg.restoreGState()
            y -= gap
        }
        NSGraphicsContext.restoreGraphicsState()
        progress?(0.85)

        guard let data = rep.representation(using: .png, properties: [:]) else { throw RenderError.encodingFailed }
        progress?(1)
        return Output(pngData: data, pixelSize: CGSize(width: width, height: totalHeight))
    }

    // MARK: - 台词拼接

    private static func renderSubtitle(plan: StitchPlan, settings: AppSettings, progress: ((Double) -> Void)?) throws -> Output {
        let width = max(240, settings.canvasWidth)
        let bandRatio = min(max(settings.subtitleBandRatio, 0.3), 1.0)
        let baseFontSize = CGFloat(settings.subtitleFontSize)
        let separator = 6
        let footerHeight = 56

        struct Band {
            let image: CGImage
            let height: Int
            let line: PlannedLine
        }

        var bands: [Band] = []
        for (index, line) in plan.lines.enumerated() {
            guard let image = ImageLoader.thumbnail(url: line.item.url, maxPixelSize: width * 3) else {
                throw RenderError.imageUnreadable(line.item.title)
            }
            let cropHeight = max(1, Int(Double(image.height) * bandRatio))
            // 素材本身大多把台词烧在画面底部，这里把裁切窗口往上贴一点，
            // 既保留人物，又尽量避免和素材自带字幕叠字。
            let topInset = Int(Double(image.height) * 0.06)
            let cropY = max(0, min(image.height - cropHeight, topInset))
            let cropped = image.cropping(to: CGRect(x: 0, y: cropY, width: image.width, height: cropHeight)) ?? image
            let height = max(1, Int(Double(width) * Double(cropped.height) / Double(cropped.width)))
            bands.append(Band(image: cropped, height: height, line: line))
            progress?(Double(index + 1) / Double(plan.lines.count) * 0.7)
        }

        let totalHeight = bands.reduce(0) { $0 + $1.height } + separator * max(0, bands.count - 1) + footerHeight
        guard let rep = makeBitmap(width: width, height: totalHeight) else { throw RenderError.bitmapAllocationFailed }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { throw RenderError.bitmapAllocationFailed }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let cg = context.cgContext
        cg.setFillColor(NSColor.black.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: width, height: totalHeight))

        var y = Double(totalHeight)
        for (index, band) in bands.enumerated() {
            y -= Double(band.height)
            let rect = CGRect(x: 0, y: y, width: Double(width), height: Double(band.height))
            cg.saveGState()
            cg.interpolationQuality = .high
            cg.draw(band.image, in: rect)
            cg.restoreGState()

            // 底部压暗，保证字幕可读
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor.black.withAlphaComponent(0.0).cgColor,
                    NSColor.black.withAlphaComponent(0.72).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) {
                let textArea = min(CGFloat(band.height) * 0.62, CGFloat(settings.subtitleFontSize) * 3.4)
                cg.saveGState()
                cg.clip(to: rect)
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: rect.minY + textArea),
                    end: CGPoint(x: 0, y: rect.minY),
                    options: []
                )
                cg.restoreGState()
            }

            let textInset: CGFloat = 18
            let maxTextWidth = CGFloat(width) - textInset * 2
            let primarySize = min(baseFontSize, CGFloat(band.height) * 0.30)
            let primary = TextStyle.fittingSubtitle(
                band.line.line,
                maxWidth: maxTextWidth,
                maxHeight: CGFloat(band.height) * 0.42,
                startSize: max(14, primarySize)
            )
            let primaryBounds = TextStyle.boundingSize(primary, maxWidth: maxTextWidth)

            var secondary: NSAttributedString?
            if let subline = band.line.subline, !subline.isEmpty {
                let candidate = TextStyle.secondary(subline, size: max(11, primarySize * 0.52))
                if TextStyle.boundingSize(candidate, maxWidth: maxTextWidth).height <= CGFloat(band.height) * 0.22 {
                    secondary = candidate
                }
            }

            var textHeight = primaryBounds.height
            if let secondary {
                textHeight += TextStyle.boundingSize(secondary, maxWidth: maxTextWidth).height + 2
            }
            let textBottom = rect.minY + max(10, (CGFloat(band.height) * 0.5 - textHeight) * 0.45)
            let primaryRect = CGRect(
                x: textInset,
                y: textBottom + (secondary == nil ? 0 : (TextStyle.boundingSize(secondary!, maxWidth: maxTextWidth).height + 2)),
                width: maxTextWidth,
                height: primaryBounds.height + 4
            )
            primary.draw(with: primaryRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            if let secondary {
                let secondaryRect = CGRect(
                    x: textInset,
                    y: textBottom,
                    width: maxTextWidth,
                    height: TextStyle.boundingSize(secondary, maxWidth: maxTextWidth).height + 4
                )
                secondary.draw(with: secondaryRect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
            y -= Double(separator)
            if index < bands.count - 1 {
                cg.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 1).cgColor)
                cg.fill(CGRect(x: 0, y: y, width: CGFloat(width), height: CGFloat(separator)))
            }
        }

        // 页脚说明
        let footer = TextStyle.caption(
            "ZVV 台词拼接 · \(plan.semanticName) · \(plan.lines.count) 段",
            size: 22,
            color: NSColor(calibratedWhite: 0.55, alpha: 1)
        )
        let footerRect = CGRect(x: 20, y: CGFloat(footerHeight) / 2 - 14, width: CGFloat(width) - 40, height: 28)
        footer.draw(with: footerRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

        NSGraphicsContext.restoreGraphicsState()
        progress?(0.85)

        guard let data = rep.representation(using: .png, properties: [:]) else { throw RenderError.encodingFailed }
        progress?(1)
        return Output(pngData: data, pixelSize: CGSize(width: width, height: totalHeight))
    }

    private static func makeBitmap(width: Int, height: Int) -> NSBitmapImageRep? {
        guard width > 0, height > 0, width * height < 400_000_000 else { return nil }
        return NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
    }
}
