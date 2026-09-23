import AppKit

// 生成 App 图标：红金渐变的圆角方块 + 白色 ZVV 字样
// 用法： swiftc -O tools/make-icon.swift -o build/make-icon && ./build/make-icon <输出目录>

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func renderIcon(size: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    let side = CGFloat(size)
    let inset = side * 0.055
    let body = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let corner = body.width * 0.225
    let path = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)

    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.78, green: 0.10, blue: 0.13, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.42, green: 0.02, blue: 0.06, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    ) {
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: body.minX, y: body.maxY),
            end: CGPoint(x: body.maxX, y: body.minY),
            options: []
        )
    }
    cg.restoreGState()

    let font = NSFont(name: "PingFang SC Semibold", size: body.width * 0.40)
        ?? NSFont.systemFont(ofSize: body.width * 0.40, weight: .heavy)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = NSAttributedString(string: "ZVV", attributes: [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
        .kern: body.width * 0.012,
    ])
    let titleSize = title.boundingRect(with: body.size, options: [.usesLineFragmentOrigin, .usesFontLeading]).size
    let titleRect = CGRect(
        x: body.minX,
        y: body.midY - titleSize.height * 0.5 + body.height * 0.06,
        width: body.width,
        height: titleSize.height + 4
    )
    title.draw(with: titleRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

    let subFont = NSFont(name: "PingFang SC Medium", size: body.width * 0.135)
        ?? NSFont.systemFont(ofSize: body.width * 0.135, weight: .medium)
    let subtitle = NSAttributedString(string: "连续对话", attributes: [
        .font: subFont,
        .foregroundColor: NSColor(calibratedRed: 1, green: 0.86, blue: 0.55, alpha: 1),
        .paragraphStyle: paragraph,
        .kern: body.width * 0.02,
    ])
    let subtitleSize = subtitle.boundingRect(with: body.size, options: [.usesLineFragmentOrigin, .usesFontLeading]).size
    let subtitleRect = CGRect(
        x: body.minX,
        y: titleRect.minY - subtitleSize.height * 1.05,
        width: body.width,
        height: subtitleSize.height + 4
    )
    subtitle.draw(with: subtitleRect, options: [.usesLineFragmentOrigin, .usesFontLeading])

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for (name, size) in sizes {
    guard let data = renderIcon(size: size) else {
        FileHandle.standardError.write(Data("渲染 \(name) 失败\n".utf8))
        continue
    }
    try? data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
}
print("图标已生成：\(outputDirectory.path)")

// MARK: - 直接拼出 .icns（新版 iconutil 对 iconset 校验很严，这里自己写容器）

func writeICNS(to url: URL) -> Bool {
    let chunks: [(String, Int)] = [
        ("ic11", 32),    // 16@2x
        ("ic12", 64),    // 32@2x
        ("ic07", 128),
        ("ic13", 256),   // 128@2x
        ("ic08", 256),
        ("ic14", 512),   // 256@2x
        ("ic09", 512),
        ("ic10", 1024),  // 512@2x
    ]
    var body = Data()
    for (type, size) in chunks {
        guard let png = renderIcon(size: size) else { continue }
        var header = Data()
        header.append(type.data(using: .ascii)!)
        var length = UInt32(png.count + 8).bigEndian
        withUnsafeBytes(of: &length) { header.append(contentsOf: $0) }
        body.append(header)
        body.append(png)
    }
    guard !body.isEmpty else { return false }
    var file = Data("icns".utf8)
    var total = UInt32(body.count + 8).bigEndian
    withUnsafeBytes(of: &total) { file.append(contentsOf: $0) }
    file.append(body)
    do {
        try file.write(to: url)
        return true
    } catch {
        FileHandle.standardError.write(Data("写入 icns 失败：\(error.localizedDescription)\n".utf8))
        return false
    }
}

let icnsURL = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : outputDirectory.appendingPathComponent("AppIcon.icns").path)
if writeICNS(to: icnsURL) {
    print("icns 已生成：\(icnsURL.path)")
}
