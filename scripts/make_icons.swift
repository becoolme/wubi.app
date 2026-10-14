// Draws the app icon set and the menu bar glyph: swift make_icons.swift <output dir>
// Draws the website's favicon and banner instead:  swift make_icons.swift --site <output dir>
import AppKit

let arguments = CommandLine.arguments.dropFirst().filter { $0 != "--site" }
let forSite = CommandLine.arguments.contains("--site")
let out = URL(fileURLWithPath: arguments.first ?? ".")
let accent = NSColor(srgbRed: 0xA9 / 255, green: 0x44 / 255, blue: 0x38 / 255, alpha: 1)

func glyphFont(_ size: CGFloat) -> NSFont {
    NSFont(name: "STSongti-SC-Black", size: size) ?? NSFont(name: "PingFangSC-Semibold", size: size)
        ?? NSFont.systemFont(ofSize: size, weight: .heavy)
}

func drawCentered(_ s: String, font: NSFont, color: NSColor, in rect: NSRect) {
    let text = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let size = text.size()
    text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
}

func bitmap(_ width: Int, _ height: Int, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// The logo: 末 in a red square with rounded corners, over the guide lines of a practice grid.
func drawLogo(in body: NSRect) {
    let s = body.width
    accent.setFill()
    NSBezierPath(roundedRect: body, xRadius: s * 0.225, yRadius: s * 0.225).fill()

    // 田字格
    let guide = NSBezierPath()
    guide.move(to: NSPoint(x: body.midX, y: body.minY + s * 0.09))
    guide.line(to: NSPoint(x: body.midX, y: body.maxY - s * 0.09))
    guide.move(to: NSPoint(x: body.minX + s * 0.09, y: body.midY))
    guide.line(to: NSPoint(x: body.maxX - s * 0.09, y: body.midY))
    guide.lineWidth = max(1, s / 200)
    guide.setLineDash([s / 50, s / 50], count: 2, phase: 0)
    NSColor(white: 1, alpha: 0.28).setStroke()
    if s >= 50 { guide.stroke() }

    drawCentered("末", font: glyphFont(s * 0.625), color: .white, in: body)
}

/// The app icon keeps the margin macOS icons have; a favicon fills its square.
func logo(_ px: Int, margin: CGFloat = 0.1) -> Data {
    bitmap(px, px) {
        let s = CGFloat(px)
        drawLogo(in: NSRect(x: s * margin, y: s * margin, width: s * (1 - margin * 2), height: s * (1 - margin * 2)))
    }
}

/// The banner at the top of the README, which is also the picture links to the website show.
func banner() -> Data {
    bitmap(1200, 630) {
        let ink = NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)
        let sub = NSColor(srgbRed: 0x55 / 255, green: 0x53 / 255, blue: 0x4E / 255, alpha: 1)
        let line = NSColor(srgbRed: 0xE2 / 255, green: 0xDE / 255, blue: 0xD5 / 255, alpha: 1)
        NSColor(srgbRed: 0xFA / 255, green: 0xF8 / 255, blue: 0xF4 / 255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 630).fill()

        func text(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, y: CGFloat, kern: CGFloat = 0) {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
                .draw(at: NSPoint(x: x, y: y))
        }
        let sans = { (size: CGFloat) in NSFont(name: "PingFangSC-Regular", size: size) ?? NSFont.systemFont(ofSize: size) }
        let mono = { (size: CGFloat) in NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }

        drawLogo(in: NSRect(x: 88, y: 478, width: 72, height: 72))
        text("末笔", glyphFont(36), ink, x: 180, y: 492)
        text("Mac 上的五笔 86 输入法", sans(24), sub, x: 272, y: 499)

        text("末笔落定，", glyphFont(104), ink, x: 82, y: 300)
        text("字已上屏。", glyphFont(104), accent, x: 82, y: 170)

        // A candidate bar, as it looks while typing.
        let bar = NSRect(x: 700, y: 196, width: 412, height: 108)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.14)
        shadow.shadowBlurRadius = 36
        shadow.shadowOffset = NSSize(width: 0, height: -14)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 18, yRadius: 18).fill()
        NSGraphicsContext.restoreGraphicsState()
        line.setStroke()
        NSBezierPath(roundedRect: bar, xRadius: 18, yRadius: 18).stroke()

        text("tt", mono(19), accent, x: bar.minX + 22, y: bar.maxY - 36, kern: 1.5)
        text("1 / 9", mono(15), sub, x: bar.maxX - 68, y: bar.maxY - 34)
        accent.setFill()
        NSBezierPath(roundedRect: NSRect(x: bar.minX + 12, y: bar.minY + 12, width: 78, height: 50), xRadius: 11, yRadius: 11).fill()
        var x = bar.minX + 26
        for (i, item) in [("笔", ""), ("笑", "d"), ("竹", "g"), ("禾", "t")].enumerated() {
            let color: NSColor = i == 0 ? .white : ink
            text("\(i + 1)", mono(15), i == 0 ? .white : sub, x: x, y: bar.minY + 28)
            text(item.0, sans(29), color, x: x + 17, y: bar.minY + 17)
            text(item.1, mono(15), sub, x: x + 52, y: bar.minY + 28)
            x += i == 0 ? 82 : 98
        }

        text("拼音反查 · 快捷输入 · 当场造词 · 不联网", sans(24), sub, x: 88, y: 76)
        text("wubi.app", mono(22), sub, x: 1000, y: 78)
    }
}

if forSite {
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try logo(96, margin: 0).write(to: out.appendingPathComponent("favicon.png"))
    try logo(180, margin: 0).write(to: out.appendingPathComponent("apple-touch-icon.png"))
    try banner().write(to: out.appendingPathComponent("og.png"))
    exit(0)
}

let iconset = out.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try logo(points * scale).write(to: iconset.appendingPathComponent(name))
}

// Menu bar glyph: a template PDF, tinted by the system.
var box = CGRect(x: 0, y: 0, width: 16, height: 16)
let pdf = CGContext(out.appendingPathComponent("MenuIcon.pdf") as CFURL, mediaBox: &box, nil)!
pdf.beginPDFPage(nil)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: false)
drawCentered("五", font: NSFont(name: "PingFangSC-Semibold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13),
             color: .black, in: box)
NSGraphicsContext.restoreGraphicsState()
pdf.endPDFPage()
pdf.closePDF()
