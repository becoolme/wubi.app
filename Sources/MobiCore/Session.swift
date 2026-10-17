import Foundation

/// One composition: the code typed so far, its candidates, and the rules for committing them.
public final class Session {
    public struct Options {
        public var autoCommitUnique = true
        public var fifthKeyCommits = true
        public var clearEmptyCode = false
        public var enterCommitsLetters = true
        public var completions = true
        public var pageSize = 5
        /// Let the words picked most often lead among those sharing a code.
        public var adaptExact = false
        public var slashQuickInput = true
        /// `z` followed by pinyin looks characters up by sound.
        public var tempPinyin = true
        /// Whatever is typed is looked up as pinyin as well as Wubi, with no key to switch.
        /// Takes the place of the `z` prefix, since pinyin itself may start with "z".
        public var mixedPinyin = false

        public init() {}
    }

    public enum Key: Equatable {
        case letter(Character)
        case space
        case backspace
        case enter
        case escape
        /// Zero-based position on the current page.
        case select(Int)
        /// A digit key, 0–9: picks a candidate, or extends a shortcut such as `/dx1280`.
        case digit(Int)
        /// Starts a slash shortcut.
        case slash
        case pageUp
        case pageDown
        /// Starts giving the code that matched nothing a word of the user's own.
        case define
    }

    public struct Output: Equatable {
        public var committed = ""
        public var handled = true

        public init(committed: String = "", handled: Bool = true) {
            self.committed = committed
            self.handled = handled
        }
    }

    public static let maxCodeLength = 4
    static let maxQuickLength = 24

    public var options = Options()
    public private(set) var buffer = ""
    public private(set) var page = 0
    private var all: [Candidate] = []
    /// Where in `all` the candidates found by sound sit, when both lookups are mixed.
    private var byPinyin = 0..<0
    private var wubiCount = 0
    private let table: CodeTable
    private let usage: UsageStore?
    /// Injected so tests can pin the date behind `/rq` and `/sj`.
    public var now: () -> Date = Date.init

    public init(table: CodeTable, usage: UsageStore? = nil) {
        self.table = table
        self.usage = usage
    }

    /// A slash shortcut is being typed; the buffer starts with "/".
    public var isQuick: Bool { buffer.hasPrefix("/") }

    /// Set once the index is built; until then `z` is an ordinary code letter.
    public var pinyin: PinyinIndex?

    /// Pinyin is being typed after a leading "z".
    public var isPinyin: Bool { Session.isPinyin(buffer, options, pinyin) }

    private static func isPinyin(_ buffer: String, _ options: Options, _ pinyin: PinyinIndex?) -> Bool {
        options.tempPinyin && !options.mixedPinyin && pinyin != nil && buffer.hasPrefix("z")
    }

    private var isMixed: Bool { options.mixedPinyin && pinyin != nil && !isQuick }

    /// The candidate at this place on the page was found by its sound, not by its code.
    public func isByPinyin(_ i: Int) -> Bool {
        byPinyin.contains(page * max(1, options.pageSize) + i)
    }

    /// Shown in place of candidates while a shortcut or a pinyin lookup has nothing to offer yet.
    public var hint: String? {
        guard all.isEmpty else { return nil }
        if isQuick { return QuickInput.hint(for: String(buffer.dropFirst())) }
        if isPinyin, buffer == "z" { return "临时拼音    接着输入拼音，候选后面是五笔编码" }
        return nil
    }

    /// The code being given a new word, while the user types that word.
    public private(set) var defining: String?
    /// The part of the new word typed so far.
    public private(set) var definedWord = ""
    /// Called when a new word is saved, so it can be written to disk.
    public var onDefine: ((_ code: String, _ word: String) -> Void)?

    public var isDefining: Bool { defining != nil }

    /// Where the new word will be saved: the code its characters give by the Wubi rules,
    /// or, for a single character or one the table cannot spell, the code typed before.
    public var definingCode: String? {
        defining.map { table.wordCode(for: definedWord) ?? $0 }
    }

    /// A code is being typed that can start a word of the user's own.
    public var canDefine: Bool {
        defining == nil && !buffer.isEmpty && buffer.count <= Session.maxCodeLength
            && !isQuick && !isPinyin
    }

    /// The last page is showing, where the key that turns pages has nothing left to turn to.
    public var isLastPage: Bool { page + 1 >= pageCount }

    public var isComposing: Bool { !buffer.isEmpty || defining != nil }
    public var hasCandidates: Bool { !all.isEmpty }

    public var pageCount: Int {
        max(1, (all.count + options.pageSize - 1) / max(1, options.pageSize))
    }

    public var pageCandidates: [Candidate] {
        let size = max(1, options.pageSize)
        let start = page * size
        guard start < all.count else { return [] }
        return Array(all[start..<min(all.count, start + size)])
    }

    public func handle(_ key: Key) -> Output {
        guard let code = defining else { return handleKey(key) }
        if buffer.isEmpty {
            switch key {
            case .letter:
                break
            case .enter:
                return finishDefining(code)
            case .escape:
                cancelDefining()
                return Output()
            case .backspace:
                if definedWord.isEmpty {
                    // Nothing typed yet: step back to the code itself.
                    cancelDefining()
                    setBuffer(code)
                } else {
                    definedWord.removeLast()
                }
                return Output()
            default:
                return Output()
            }
        }
        // Whatever would have gone to the text goes into the new word instead.
        definedWord += handleKey(key).committed
        return Output()
    }

    private func finishDefining(_ typed: String) -> Output {
        let word = definedWord
        let code = definingCode ?? typed
        cancelDefining()
        guard !word.isEmpty else { return Output() }
        table.addUserWords(text: "\(code) \(word)")
        onDefine?(code, word)
        return Output(committed: word)
    }

    private func cancelDefining() {
        defining = nil
        definedWord = ""
    }

    private func handleKey(_ key: Key) -> Output {
        switch key {
        case .define:
            guard canDefine else { return Output(handled: isComposing) }
            defining = buffer
            definedWord = ""
            setBuffer("")
            return Output()
        case .letter(let ch):
            return type(ch)
        case .space:
            guard isComposing else { return Output(handled: false) }
            // An unfinished shortcut is just text: keep it and let the space through.
            if isQuick, all.isEmpty { return Output(committed: flushLetters(), handled: false) }
            return Output(committed: take(0))
        case .digit(let n):
            guard isComposing else { return Output(handled: false) }
            if isQuick, QuickInput.acceptsDigits(String(buffer.dropFirst())) {
                if buffer.count < Session.maxQuickLength { setBuffer(buffer + String(n)) }
                return Output()
            }
            return Output(committed: n >= 1 && n <= options.pageSize ? take(n - 1) : "")
        case .slash:
            guard !isComposing, options.slashQuickInput else { return Output(handled: false) }
            setBuffer("/")
            return Output()
        case .select(let i):
            guard isComposing else { return Output(handled: false) }
            return Output(committed: take(i))
        case .backspace:
            guard isComposing else { return Output(handled: false) }
            setBuffer(String(buffer.dropLast()))
            return Output()
        case .enter:
            guard isComposing else { return Output(handled: false) }
            let letters = options.enterCommitsLetters ? buffer : ""
            setBuffer("")
            return Output(committed: letters)
        case .escape:
            guard isComposing else { return Output(handled: false) }
            setBuffer("")
            return Output()
        case .pageDown:
            guard isComposing else { return Output(handled: false) }
            if page + 1 < pageCount { page += 1 }
            return Output()
        case .pageUp:
            guard isComposing else { return Output(handled: false) }
            if page > 0 { page -= 1 }
            return Output()
        }
    }

    /// Commits the first candidate on the page (nothing if the code has none) and ends the composition.
    public func commitFirst() -> String {
        guard let first = pageCandidates.first else {
            setBuffer("")
            return ""
        }
        return commit(first)
    }

    /// Ends the composition and returns the raw letters that were typed.
    public func flushLetters() -> String {
        let letters = definedWord + buffer
        cancelDefining()
        setBuffer("")
        return letters
    }

    public func reset() {
        cancelDefining()
        setBuffer("")
    }

    private func type(_ ch: Character) -> Output {
        var out = Output()
        if isQuick || isPinyin {
            if buffer.count < Session.maxQuickLength { setBuffer(buffer + String(ch)) }
            return out
        }
        if isMixed, buffer.count >= Session.maxCodeLength, buffer.count < Session.maxQuickLength,
           pinyin?.hasPrefix(buffer + String(ch)) == true {
            // Too long for a code, but still on the way to a reading such as "zhong".
            setBuffer(buffer + String(ch))
            return out
        }
        if buffer.count >= Session.maxCodeLength {
            guard options.fifthKeyCommits else { return out }
            let first = all.first
            out.committed = first.map(commit) ?? ""
            setBuffer(String(ch))
        } else {
            setBuffer(buffer + String(ch))
        }
        if buffer.count == Session.maxCodeLength {
            if isMixed, pinyin?.hasPrefix(buffer) == true {
                // May be pinyin still being typed: leave it to the user to pick.
            } else if all.count == 1, options.autoCommitUnique {
                out.committed += commit(all[0])
            } else if all.isEmpty, options.clearEmptyCode {
                setBuffer("")
            }
        }
        return out
    }

    private func take(_ i: Int) -> String {
        let cands = pageCandidates
        guard i >= 0, i < cands.count else { return "" }
        return commit(cands[i])
    }

    private func commit(_ candidate: Candidate) -> String {
        if isPinyin || all.firstIndex(of: candidate).map(byPinyin.contains) == true {
            usage?.record(word: candidate.word, code: buffer)
        } else if !isQuick {
            usage?.record(word: candidate.word, code: candidate.code)
        }
        setBuffer("")
        return candidate.word
    }

    /// Puts the words read as `value` after those coded exactly `value` and before the code hints.
    /// Words that merely start with that reading are offered only when Wubi has nothing at all.
    private func mix(_ pinyin: PinyinIndex, _ value: String) {
        let exact = all.prefix { $0.code == value }
        var seen = Set(exact.map(\.word))
        let sounds = pinyin.candidates(for: value, usage: usage, typed: value, prefixLimit: all.isEmpty ? 40 : 0)
            .filter { seen.insert($0.word).inserted }
        let hints = all.dropFirst(exact.count).filter { !seen.contains($0.word) }
        byPinyin = exact.count..<(exact.count + sounds.count)
        all = exact + sounds + hints
    }

    private func setBuffer(_ value: String) {
        buffer = value
        page = 0
        byPinyin = 0..<0
        if value.hasPrefix("/") {
            all = QuickInput.results(for: String(value.dropFirst()), now: now()).map { Candidate(word: $0, code: "") }
        } else if Session.isPinyin(value, options, pinyin) {
            all = pinyin?.candidates(for: String(value.dropFirst()), usage: usage, typed: value) ?? []
        } else {
            all = table.candidates(for: value, completions: options.completions, usage: usage, adaptExact: options.adaptExact)
            if isMixed, let pinyin { mix(pinyin, value) }
            liftRare(value)
        }
    }

    /// The table puts rare characters that match the code after every completion. Bring them
    /// up to the start of the second page, so they are a page turn away rather than many.
    private func liftRare(_ value: String) {
        guard let first = all.firstIndex(where: { $0.code != value }) else { return }
        let rare = all[first...].filter { $0.code == value }
        guard !rare.isEmpty else { return }
        var rest = Array(all[..<first]) + all[first...].filter { $0.code != value }
        let at = min(rest.count, max(max(1, options.pageSize), byPinyin.upperBound))
        rest.insert(contentsOf: rare, at: at)
        all = rest
    }
}
