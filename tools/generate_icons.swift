import AppKit
import Foundation

enum IconStyle: String, CaseIterable {
    case calm
    case signal
    case switcher
    case mono

    var title: String {
        switch self {
        case .calm: return "Calm"
        case .signal: return "Signal"
        case .switcher: return "Switcher"
        case .mono: return "Mono"
        }
    }
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Lidless/Resources")
let defaultStyle: IconStyle = .calm
let iconsetURL = outputDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = outputDirectory.appendingPathComponent("AppIcon.icns")
let variantsDirectory = outputDirectory.deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("design/icon-variants", isDirectory: true)
let variantResourcesDirectory = outputDirectory.appendingPathComponent("IconVariants", isDirectory: true)

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: variantsDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: variantResourcesDirectory, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: red, green: green, blue: blue, alpha: alpha)
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func fill(_ path: NSBezierPath, _ color: NSColor) {
    color.setFill()
    path.fill()
}

func drawCanvas(size: CGFloat, start: NSColor, end: NSColor) {
    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let background = roundedRect(canvas, radius: size * 0.225)
    NSGradient(starting: start, ending: end)?.draw(in: background, angle: -38)

    NSColor.black.withAlphaComponent(0.12).setStroke()
    background.lineWidth = max(1, size * 0.006)
    background.stroke()
}

func drawCalm(size: CGFloat) {
    drawCanvas(
        size: size,
        start: color(0.045, 0.055, 0.082),
        end: color(0.020, 0.130, 0.145)
    )

    let haloPath = NSBezierPath(ovalIn: NSRect(x: size * 0.12, y: size * 0.18, width: size * 0.76, height: size * 0.72))
    NSGradient(colors: [
        color(0.17, 0.80, 0.88, 0.62),
        color(0.12, 0.42, 0.48, 0.22),
        .clear
    ])?.draw(in: haloPath, angle: 90)

    let external = NSRect(x: size * 0.23, y: size * 0.48, width: size * 0.54, height: size * 0.29)
    fill(roundedRect(external, radius: size * 0.042), color(0.60, 0.93, 0.94, 0.10))
    stroke(roundedRect(external, radius: size * 0.042), color: color(0.60, 0.94, 0.94, 0.88), width: max(3, size * 0.019))

    let laptop = NSRect(x: size * 0.19, y: size * 0.28, width: size * 0.62, height: size * 0.28)
    fill(roundedRect(laptop, radius: size * 0.047), color(0.014, 0.018, 0.026))
    stroke(roundedRect(laptop, radius: size * 0.047), color: color(0.91, 0.95, 0.95, 0.90), width: max(3, size * 0.018))

    let base = NSRect(x: size * 0.13, y: size * 0.20, width: size * 0.74, height: size * 0.062)
    fill(roundedRect(base, radius: size * 0.031), color(0.70, 0.76, 0.80, 0.96))

    let moon = NSBezierPath(ovalIn: NSRect(x: size * 0.60, y: size * 0.365, width: size * 0.095, height: size * 0.095))
    fill(moon, color(0.95, 0.76, 0.37, 0.98))
    fill(NSBezierPath(ovalIn: NSRect(x: size * 0.63, y: size * 0.39, width: size * 0.082, height: size * 0.082)), color(0.014, 0.018, 0.026))

    let sleepLine = NSBezierPath()
    sleepLine.move(to: NSPoint(x: size * 0.31, y: size * 0.41))
    sleepLine.line(to: NSPoint(x: size * 0.52, y: size * 0.41))
    sleepLine.lineCapStyle = .round
    stroke(sleepLine, color: color(0.38, 0.50, 0.55, 0.72), width: max(3, size * 0.018))
}

func drawSignal(size: CGFloat) {
    drawCanvas(
        size: size,
        start: color(0.035, 0.045, 0.075),
        end: color(0.080, 0.090, 0.135)
    )

    let external = NSRect(x: size * 0.20, y: size * 0.46, width: size * 0.60, height: size * 0.35)
    fill(roundedRect(external, radius: size * 0.050), color(0.12, 0.48, 0.58, 0.18))
    stroke(roundedRect(external, radius: size * 0.050), color: color(0.44, 0.90, 0.95, 0.95), width: max(3, size * 0.021))

    for index in 0..<3 {
        let inset = CGFloat(index) * size * 0.050
        let arcRect = NSRect(x: size * 0.34 + inset, y: size * 0.58 + inset, width: size * 0.32 - inset * 2, height: size * 0.20 - inset * 1.2)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: arcRect.midX, y: arcRect.minY), radius: arcRect.width / 2, startAngle: 32, endAngle: 148)
        arc.lineCapStyle = .round
        stroke(arc, color: color(0.70, 0.98, 0.88, 0.80 - CGFloat(index) * 0.18), width: max(2, size * 0.012))
    }

    let laptop = NSRect(x: size * 0.17, y: size * 0.25, width: size * 0.66, height: size * 0.30)
    fill(roundedRect(laptop, radius: size * 0.055), color(0.010, 0.013, 0.020))
    stroke(roundedRect(laptop, radius: size * 0.055), color: color(0.88, 0.94, 0.96, 0.92), width: max(3, size * 0.018))

    fill(roundedRect(NSRect(x: size * 0.11, y: size * 0.18, width: size * 0.78, height: size * 0.062), radius: size * 0.032), color(0.72, 0.77, 0.82, 0.98))

    let power = NSBezierPath()
    power.appendArc(withCenter: NSPoint(x: size * 0.50, y: size * 0.39), radius: size * 0.065, startAngle: 218, endAngle: -38, clockwise: true)
    power.lineCapStyle = .round
    stroke(power, color: color(1.0, 0.42, 0.34, 0.96), width: max(4, size * 0.025))

    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: size * 0.50, y: size * 0.46))
    stem.line(to: NSPoint(x: size * 0.50, y: size * 0.39))
    stem.lineCapStyle = .round
    stroke(stem, color: color(1.0, 0.42, 0.34, 0.96), width: max(4, size * 0.025))
}

func drawSwitcher(size: CGFloat) {
    drawCanvas(
        size: size,
        start: color(0.105, 0.115, 0.140),
        end: color(0.030, 0.035, 0.052)
    )

    let external = NSRect(x: size * 0.18, y: size * 0.49, width: size * 0.64, height: size * 0.32)
    fill(roundedRect(external, radius: size * 0.048), color(0.80, 0.90, 0.92, 0.12))
    stroke(roundedRect(external, radius: size * 0.048), color: color(0.78, 0.90, 0.93, 0.90), width: max(3, size * 0.018))

    let laptop = NSRect(x: size * 0.18, y: size * 0.24, width: size * 0.64, height: size * 0.30)
    fill(roundedRect(laptop, radius: size * 0.055), color(0.018, 0.022, 0.030))
    stroke(roundedRect(laptop, radius: size * 0.055), color: color(0.86, 0.89, 0.91, 0.94), width: max(3, size * 0.018))
    fill(roundedRect(NSRect(x: size * 0.11, y: size * 0.17, width: size * 0.78, height: size * 0.064), radius: size * 0.032), color(0.68, 0.72, 0.76, 0.98))

    let toggleTrack = NSRect(x: size * 0.34, y: size * 0.365, width: size * 0.32, height: size * 0.115)
    fill(roundedRect(toggleTrack, radius: size * 0.058), color(0.20, 0.26, 0.29, 1))
    stroke(roundedRect(toggleTrack, radius: size * 0.058), color: color(0.45, 0.54, 0.58, 0.72), width: max(1, size * 0.007))
    fill(NSBezierPath(ovalIn: NSRect(x: size * 0.365, y: size * 0.388, width: size * 0.070, height: size * 0.070)), color(0.95, 0.98, 0.98, 0.95))

    let indicator = NSBezierPath()
    indicator.move(to: NSPoint(x: size * 0.56, y: size * 0.43))
    indicator.line(to: NSPoint(x: size * 0.62, y: size * 0.43))
    indicator.lineCapStyle = .round
    stroke(indicator, color: color(1.0, 0.38, 0.32, 0.92), width: max(2, size * 0.013))
}

func drawMono(size: CGFloat) {
    drawCanvas(
        size: size,
        start: color(0.010, 0.012, 0.018),
        end: color(0.038, 0.044, 0.060)
    )

    let line = color(0.92, 0.96, 0.97, 0.95)
    let external = NSRect(x: size * 0.22, y: size * 0.50, width: size * 0.56, height: size * 0.28)
    stroke(roundedRect(external, radius: size * 0.050), color: line, width: max(4, size * 0.020))

    let laptop = NSRect(x: size * 0.18, y: size * 0.27, width: size * 0.64, height: size * 0.28)
    stroke(roundedRect(laptop, radius: size * 0.055), color: line, width: max(4, size * 0.020))

    let base = NSBezierPath()
    base.move(to: NSPoint(x: size * 0.12, y: size * 0.21))
    base.line(to: NSPoint(x: size * 0.88, y: size * 0.21))
    base.lineCapStyle = .round
    stroke(base, color: line, width: max(5, size * 0.032))

    fill(NSBezierPath(ovalIn: NSRect(x: size * 0.62, y: size * 0.35, width: size * 0.105, height: size * 0.105)), color(0.38, 0.92, 0.78, 0.96))
    fill(NSBezierPath(ovalIn: NSRect(x: size * 0.650, y: size * 0.382, width: size * 0.062, height: size * 0.062)), color(0.010, 0.012, 0.018))
}

func drawIcon(style: IconStyle, size: CGFloat) -> NSImage {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        return NSImage(size: NSSize(width: size, height: size))
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    switch style {
    case .calm:
        drawCalm(size: size)
    case .signal:
        drawSignal(size: size)
    case .switcher:
        drawSwitcher(size: size)
    case .mono:
        drawMono(size: size)
    }

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmap)
    return image
}

func pngData(from image: NSImage) throws -> Data {
    guard let bitmap = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LidlessIcon", code: 1)
    }
    return png
}

func writePNG(style: IconStyle, size: CGFloat, to url: URL) throws {
    try pngData(from: drawIcon(style: style, size: size)).write(to: url)
}

func createICNS(from iconset: URL, to icns: URL) throws {
    try? FileManager.default.removeItem(at: icns)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(domain: "LidlessIcon", code: Int(process.terminationStatus))
    }
}

func writeIconset(style: IconStyle, iconset: URL) throws {
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    let sizes: [(CGFloat, String)] = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]

    for item in sizes {
        try writePNG(style: style, size: item.0, to: iconset.appendingPathComponent(item.1))
    }
}

func writeContactSheet() throws {
    let tile: CGFloat = 280
    let padding: CGFloat = 34
    let labelHeight: CGFloat = 44
    let width = padding + CGFloat(IconStyle.allCases.count) * (tile + padding)
    let height = tile + labelHeight + padding * 2
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width),
        pixelsHigh: Int(height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "LidlessIcon", code: 2)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer {
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    color(0.93, 0.94, 0.95).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: NSColor.black.withAlphaComponent(0.82)
    ]

    for (index, style) in IconStyle.allCases.enumerated() {
        let x = padding + CGFloat(index) * (tile + padding)
        let icon = drawIcon(style: style, size: tile)
        icon.draw(in: NSRect(x: x, y: padding + labelHeight, width: tile, height: tile))

        let label = NSString(string: style.title)
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: x + (tile - labelSize.width) / 2, y: padding + (labelHeight - labelSize.height) / 2),
            withAttributes: attributes
        )
    }

    let sheet = NSImage(size: NSSize(width: width, height: height))
    sheet.addRepresentation(bitmap)
    try pngData(from: sheet).write(to: variantsDirectory.appendingPathComponent("contact-sheet.png"))
}

try writeIconset(style: defaultStyle, iconset: iconsetURL)
try createICNS(from: iconsetURL, to: icnsURL)

for style in IconStyle.allCases {
    let iconset = variantResourcesDirectory.appendingPathComponent("\(style.rawValue).iconset", isDirectory: true)
    let icns = variantResourcesDirectory.appendingPathComponent("\(style.rawValue).icns")
    try writeIconset(style: style, iconset: iconset)
    try createICNS(from: iconset, to: icns)
    try writePNG(style: style, size: 1024, to: variantsDirectory.appendingPathComponent("\(style.rawValue).png"))
}

try writeContactSheet()

print("Generated default \(defaultStyle.title) icon at \(icnsURL.path)")
print("Generated variants at \(variantsDirectory.path)")
