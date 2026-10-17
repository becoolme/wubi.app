import Cocoa
import MobiCore

struct PanelContent {
    var code = ""
    var pageText = ""
    var items: [Candidate] = []
    /// The small text after each word; when nil, the part of its code still to be typed.
    var hints: [String]?
    /// Shown instead of candidates, e.g. when the code matches nothing.
    var message: String?
}

private struct Palette {
    let background: NSColor
    let border: NSColor
    let ink: NSColor
    let secondary: NSColor
    let code: NSColor
    let accent: NSColor

    static var current: Palette {
        let s = Settings.shared
        if s.isDark {
            return Palette(background: NSColor(hex: "#2C3038")!, border: NSColor(white: 1, alpha: 0.18),
                           ink: NSColor(hex: "#F5F5F7")!, secondary: NSColor(hex: "#A9ADB5")!,
                           code: NSColor(hex: "#F5F5F7")!, accent: s.accent)
        }
        return Palette(background: NSColor(hex: "#FCFCFD")!, border: NSColor(white: 0, alpha: 0.2),
                       ink: NSColor(hex: "#1D1D1F")!, secondary: NSColor(hex: "#5C5C61")!,
                       code: s.accent, accent: s.accent)
    }
}

private func makePanel(content: NSView) -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.contentView = content
    return panel
}

/// Puts a panel just below the caret, or above it when there is no room.
/// Puts the panel under the caret, or over it where there is no room below or `above` asks.
private func place(_ panel: NSPanel, size: NSSize, caret: NSRect, above: Bool = false) {
    let screen = NSScreen.screens.first { $0.frame.contains(caret.origin) } ?? NSScreen.main
    let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    var origin = NSPoint(x: caret.minX - 10, y: caret.minY - 6 - size.height)
    if above || origin.y < bounds.minY { origin.y = caret.maxY + 6 }
    if origin.y + size.height > bounds.maxY { origin.y = caret.minY - 6 - size.height }
    origin.x = max(bounds.minX + 4, min(origin.x, bounds.maxX - size.width - 4))
    panel.setFrame(NSRect(origin: origin, size: size), display: true)
    panel.invalidateShadow()
    panel.orderFront(nil)
}

final class CandidateView: NSView {
    var content = PanelContent() { didSet { needsDisplay = true } }
    var onPick: ((Int) -> Void)?
    private var hitRects: [NSRect] = []

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private struct Piece {
        let text: NSAttributedString
        let origin: NSPoint
    }

    private struct Layout {
        var size = NSSize.zero
        var pieces: [Piece] = []
        var itemRects: [NSRect] = []
    }

    private let pad: CGFloat = 6
    private let headerHeight: CGFloat = 20
    private let mono12 = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    private func text(_ s: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    private func measure() -> Layout {
        let p = Palette.current
        let s = Settings.shared
        let wordFont = NSFont(name: "PingFangSC-Regular", size: s.fontSize) ?? NSFont.systemFont(ofSize: s.fontSize)
        let vertical = s.layout == .vertical
        var l = Layout()

        let code = text(content.code, NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), p.code, kern: 1)
        let page = text(content.pageText, NSFont.systemFont(ofSize: 11), p.secondary)
        let headerWidth = code.size().width + 28 + page.size().width + 16
        let bodyTop = pad + headerHeight + 4

        struct Item { let n, word, hint: NSAttributedString; let width: CGFloat }
        var items: [Item] = []
        for (i, c) in content.items.enumerated() {
            let first = i == 0
            let sub = first ? NSColor.white : p.secondary
            let n = text("\(i + 1)", mono12, sub)
            let word = text(c.word, wordFont, first ? .white : p.ink)
            let rest = content.hints.map { i < $0.count ? $0[i] : "" } ?? String(c.code.dropFirst(content.code.count))
            let hint = text(rest, mono12, sub)
            let gap: CGFloat = vertical ? 10 : 6
            var w = 10 + n.size().width + gap + word.size().width + 10
            if hint.length > 0 { w += gap + hint.size().width }
            items.append(Item(n: n, word: word, hint: hint, width: w))
        }

        let rowHeight: CGFloat = max(vertical ? 28 : 26, ceil(s.fontSize) + 12)
        var bodyWidth: CGFloat = 0
        var bodyHeight: CGFloat = rowHeight
        var message: NSAttributedString?
        if let m = content.message {
            let t = text(m, NSFont.systemFont(ofSize: 13), p.secondary)
            message = t
            bodyWidth = t.size().width + 20
        } else if vertical {
            bodyWidth = max(180, items.map(\.width).max() ?? 0)
            bodyHeight = CGFloat(items.count) * rowHeight + CGFloat(max(0, items.count - 1)) * 2
        } else {
            bodyWidth = items.reduce(0) { $0 + $1.width } + CGFloat(max(0, items.count - 1)) * 2
        }
        let innerWidth = ceil(max(headerWidth, bodyWidth))
        l.size = NSSize(width: innerWidth + pad * 2, height: ceil(bodyTop + bodyHeight + pad))

        func centered(_ t: NSAttributedString, x: CGFloat, in rect: NSRect) -> Piece {
            Piece(text: t, origin: NSPoint(x: x, y: rect.midY - t.size().height / 2))
        }

        let header = NSRect(x: pad, y: pad, width: innerWidth, height: headerHeight)
        l.pieces.append(centered(code, x: header.minX + 8, in: header))
        l.pieces.append(centered(page, x: header.maxX - 8 - page.size().width, in: header))

        if let message {
            let rect = NSRect(x: pad, y: bodyTop, width: innerWidth, height: rowHeight)
            l.pieces.append(centered(message, x: rect.minX + 10, in: rect))
            return l
        }

        var x = pad
        var y = bodyTop
        for item in items {
            let rect = vertical
                ? NSRect(x: pad, y: y, width: innerWidth, height: rowHeight)
                : NSRect(x: x, y: y, width: item.width, height: rowHeight)
            l.itemRects.append(rect)
            let gap: CGFloat = vertical ? 10 : 6
            var cx = rect.minX + 10
            l.pieces.append(centered(item.n, x: cx, in: rect))
            cx += item.n.size().width + gap
            l.pieces.append(centered(item.word, x: cx, in: rect))
            if item.hint.length > 0 {
                let hx = vertical ? rect.maxX - 10 - item.hint.size().width : cx + item.word.size().width + gap
                l.pieces.append(centered(item.hint, x: hx, in: rect))
            }
            if vertical { y += rowHeight + 2 } else { x += item.width + 2 }
        }
        return l
    }

    var fittingContentSize: NSSize { measure().size }

    override func draw(_ dirtyRect: NSRect) {
        let p = Palette.current
        let l = measure()
        hitRects = l.itemRects

        let frame = NSRect(origin: .zero, size: l.size)
        let shape = NSBezierPath(roundedRect: frame.insetBy(dx: 0.25, dy: 0.25), xRadius: 12, yRadius: 12)
        p.background.setFill()
        shape.fill()
        p.border.setStroke()
        shape.lineWidth = 0.5
        shape.stroke()

        if let first = l.itemRects.first {
            p.accent.setFill()
            NSBezierPath(roundedRect: first, xRadius: 8, yRadius: 8).fill()
        }
        for piece in l.pieces { piece.text.draw(at: piece.origin) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let i = hitRects.firstIndex(where: { $0.contains(point) }) {
            onPick?(i)
        } else if hitRects.isEmpty {
            // No candidates, only a message: -1 stands for a click on it.
            onPick?(-1)
        }
    }
}

final class CandidatePanel {
    static let shared = CandidatePanel()

    private let view = CandidateView(frame: .zero)
    private lazy var panel = makePanel(content: view)

    var onPick: ((Int) -> Void)? {
        get { view.onPick }
        set { view.onPick = newValue }
    }

    func show(_ content: PanelContent, caret: NSRect) {
        view.content = content
        let size = view.fittingContentSize
        view.frame = NSRect(origin: .zero, size: size)
        place(panel, size: size, caret: caret)
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// The pill that confirms a Chinese / English switch next to the caret.
final class ModeHUD {
    static let shared = ModeHUD()

    private final class HUDView: NSView {
        var english = false { didSet { needsDisplay = true } }
        /// Said in place of the mode, as after an update.
        var note: String? { didSet { needsDisplay = true } }
        override var isFlipped: Bool { true }

        private var badge: NSAttributedString {
            NSAttributedString(string: note != nil ? "新" : english ? "英" : "中", attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: english ? NSColor(hex: "#22262E")! : NSColor.white,
            ])
        }

        private var label: NSAttributedString {
            NSAttributedString(string: note ?? (english ? "English" : "五笔 86"), attributes: [
                .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(hex: "#F5F5F7")!,
            ])
        }

        var fittingContentSize: NSSize { NSSize(width: ceil(6 + 24 + 8 + label.size().width + 12), height: 36) }

        override func draw(_ dirtyRect: NSRect) {
            NSColor(hex: "#2C3038")!.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
            let box = NSRect(x: 6, y: 6, width: 24, height: 24)
            (english ? NSColor(hex: "#F5F5F7")! : Settings.shared.accent).setFill()
            NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
            let b = badge
            b.draw(at: NSPoint(x: box.midX - b.size().width / 2, y: box.midY - b.size().height / 2))
            let t = label
            t.draw(at: NSPoint(x: 38, y: bounds.midY - t.size().height / 2))
        }
    }

    private let view = HUDView(frame: .zero)
    private lazy var panel: NSPanel = {
        let p = makePanel(content: view)
        p.ignoresMouseEvents = true
        return p
    }()
    private var hideWork: DispatchWorkItem?

    func flash(english: Bool, caret: NSRect) {
        view.note = nil
        view.english = english
        show(caret: caret, for: 0.8)
    }

    /// Shown over the caret, as it comes up while typing and the candidates take the room below.
    func flash(note: String, caret: NSRect) {
        view.note = note
        view.english = false
        show(caret: caret, for: 3, above: true)
    }

    private func show(caret: NSRect, for seconds: TimeInterval, above: Bool = false) {
        let size = view.fittingContentSize
        view.frame = NSRect(origin: .zero, size: size)
        place(panel, size: size, caret: caret, above: above)
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }
}
