import Cocoa
import InputMethodKit
import MobiCore

@objc(MobiInputController)
final class MobiInputController: IMKInputController {
    private let session = Session(table: Dictionary.table, usage: Dictionary.usage)
    private var punctuation = Punctuation()
    private var english = false
    /// Key code of a Shift that went down alone and has not been followed by another key yet.
    private var loneShift: UInt16?
    private var loneShiftTime: TimeInterval = 0
    private var lastWasDigit = false

    private static let noRange = NSRange(location: NSNotFound, length: NSNotFound)
    private static let leftShift: UInt16 = 56
    private static let rightShift: UInt16 = 60

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        configure()
    }

    private func configure() {
        session.options = Settings.shared.sessionOptions
        session.pinyin = Dictionary.pinyin
        session.onDefine = Dictionary.saveUserWord
    }

    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        ModeHUD.shared.hide()
        Dictionary.usage.save()
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        let letters = session.flushLetters()
        if !letters.isEmpty { insert(letters) }
        CandidatePanel.shared.hide()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        if event.type == .flagsChanged {
            trackShift(event)
            return false
        }
        guard event.type == .keyDown else { return false }
        loneShift = nil
        configure()

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if english || flags.contains(.capsLock) { return false }
        if !flags.intersection([.command, .control, .option]).isEmpty {
            // A shortcut ends the composition; the letters typed so far stay in the text.
            commitComposition(sender)
            return false
        }

        let handled = process(event, shift: flags.contains(.shift))
        refresh()
        return handled
    }

    // MARK: Keys

    private func process(_ event: NSEvent, shift: Bool) -> Bool {
        let wasDigit = lastWasDigit
        lastWasDigit = false
        let composing = session.isComposing

        switch event.keyCode {
        case 49: return apply(session.handle(.space))
        case 51: return apply(session.handle(.backspace))
        case 36, 76: return apply(session.handle(.enter))
        case 53: return apply(session.handle(.escape))
        case 48:
            guard composing else { return false }
            if Settings.shared.tabKey == .page { return apply(session.handle(shift ? .pageUp : .pageDown)) }
            return apply(session.handle(.define))
        case 116: return apply(session.handle(.pageUp))
        case 121: return apply(session.handle(.pageDown))
        case 123...126: return composing
        default: break
        }

        guard let ch = event.characters?.first, event.characters?.count == 1 else { return composing }

        if session.isDefining {
            // Only keys that build the new word count; nothing reaches the text until it is saved.
            if ch.isASCII, ch.isLetter {
                if ch.isLowercase { _ = apply(session.handle(.letter(ch))) }
            } else if let n = ch.wholeNumberValue, ch.isASCII {
                _ = apply(session.handle(.digit(n)))
            } else {
                switch ch {
                case ";": _ = apply(session.handle(.select(1)))
                case "'": _ = apply(session.handle(.select(2)))
                case "-": _ = apply(session.handle(.pageUp))
                case "=": _ = apply(session.handle(.pageDown))
                default: break
                }
            }
            return true
        }

        if ch.isASCII, ch.isLetter {
            if ch.isLowercase { return apply(session.handle(.letter(ch))) }
            guard composing else { return false }
            insert(commitPending() + String(ch))
            return true
        }

        if ch == "/", !composing, apply(session.handle(.slash)) { return true }

        if composing {
            if let n = ch.wholeNumberValue, ch.isASCII { return apply(session.handle(.digit(n))) }
            switch ch {
            case ";": return apply(session.handle(.select(1)))
            case "'": return apply(session.handle(.select(2)))
            case "-": return apply(session.handle(.pageUp))
            case "=": return apply(session.handle(session.canDefine && session.isLastPage ? .define : .pageDown))
            default: break
            }
        }

        if ch.isASCII, ch.isNumber {
            lastWasDigit = !composing
            return composing
        }

        // 3.14 keeps its ASCII point.
        if ch == ".", wasDigit, !composing { return false }

        if Settings.shared.chinesePunctuation, let mapped = punctuation.map(ch) {
            insert((composing ? commitPending() : "") + mapped)
            return true
        }
        guard composing else { return false }
        if ch.isASCII, ch.isPunctuation || ch.isSymbol {
            insert(commitPending() + String(ch))
        }
        return true
    }

    /// What a key that ends the composition leaves behind: the first candidate,
    /// or the typed text of a slash shortcut that never produced one.
    private func commitPending() -> String {
        session.isQuick && !session.hasCandidates ? session.flushLetters() : session.commitFirst()
    }

    private func apply(_ output: Session.Output) -> Bool {
        if !output.committed.isEmpty { insert(output.committed) }
        return output.handled
    }

    // MARK: Chinese / English

    private func trackShift(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        let code = event.keyCode
        guard code == Self.leftShift || code == Self.rightShift else {
            loneShift = nil
            return
        }
        if flags == .shift {
            loneShift = code
            loneShiftTime = event.timestamp
        } else if flags.isEmpty, loneShift == code, event.timestamp - loneShiftTime < 0.5 {
            loneShift = nil
            if switches(with: code) { toggleEnglish() }
        } else {
            loneShift = nil
        }
    }

    private func switches(with keyCode: UInt16) -> Bool {
        switch Settings.shared.switchKey {
        case .leftShift: return keyCode == Self.leftShift
        case .rightShift: return keyCode == Self.rightShift
        case .anyShift: return true
        case .off: return false
        }
    }

    private func toggleEnglish() {
        commitComposition(client())
        english.toggle()
        ModeHUD.shared.flash(english: english, caret: caretRect())
    }

    // MARK: Client

    private func insert(_ text: String) {
        guard !text.isEmpty else { return }
        client()?.insertText(text, replacementRange: Self.noRange)
    }

    private func caretRect() -> NSRect {
        var rect = NSRect.zero
        client()?.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
    }

    private func refresh() {
        guard let client = client() else { return }
        let buffer = session.buffer
        let pending = session.definedWord + buffer
        let marked = NSAttributedString(string: pending, attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .markedClauseSegment: 0,
        ])
        client.setMarkedText(marked, selectionRange: NSRange(location: pending.utf16.count, length: 0),
                             replacementRange: Self.noRange)

        guard session.isComposing else {
            CandidatePanel.shared.hide()
            return
        }
        var content = PanelContent(code: buffer)
        if let code = session.definingCode {
            content.code = "造词 \(code)" + (buffer.isEmpty ? "" : "    \(buffer)")
        }
        if session.hasCandidates {
            content.items = session.pageCandidates
            content.pageText = "\(session.page + 1) / \(session.pageCount)"
            if session.isPinyin {
                content.hints = content.items.map(\.code)
            } else {
                // A word found by its sound shows its whole code; a code hint, the keys still to type.
                content.hints = content.items.enumerated().map { i, item in
                    session.isByPinyin(i) ? item.code : String(item.code.dropFirst(buffer.count))
                }
            }
        } else if session.isDefining {
            if !buffer.isEmpty {
                content.message = "没有这个编码    ⌫ 修改"
            } else if session.definedWord.isEmpty {
                content.message = "照常打出这个词    ⎋ 取消"
            } else {
                content.message = "⏎ 保存「\(session.definedWord)」    ⌫ 删字    ⎋ 取消"
            }
        } else if let hint = session.hint {
            content.message = hint
        } else if session.isQuick {
            content.message = "没有这个代号    ⌫ 修改    ⏎ 上屏字符"
        } else {
            let enter = Settings.shared.enterKey == .letters ? "上屏字母" : "清空"
            content.message = "没有这个编码    ⌫ 修改    ⏎ \(enter)" + (session.canDefine ? (Settings.shared.tabKey == .define ? "    Tab 造词" : "    = 造词") : "")
        }
        CandidatePanel.shared.onPick = { [weak self] i in self?.pick(i) }
        CandidatePanel.shared.show(content, caret: caretRect())
    }

    private func pick(_ i: Int) {
        if i < 0 {
            // A click on the "no such code" message starts defining a word.
            guard session.canDefine else { return }
            _ = session.handle(.define)
        } else {
            _ = apply(session.handle(.select(i)))
        }
        refresh()
    }

    // MARK: Menu

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let item = NSMenuItem(title: "设置…", action: #selector(openSettings(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindow.shared.show()
    }
}
