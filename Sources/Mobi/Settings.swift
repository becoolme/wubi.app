import Cocoa
import Combine
import MobiCore

/// User preferences, kept in the input method's own defaults domain.
final class Settings: ObservableObject {
    static let shared = Settings()

    enum Layout: String, CaseIterable { case horizontal, vertical }
    enum Theme: String, CaseIterable { case system, light, dark }
    enum SwitchKey: String, CaseIterable { case leftShift, rightShift, anyShift, off }
    enum EmptyCode: String, CaseIterable { case keep, clear }
    enum EnterKey: String, CaseIterable { case letters, clear }
    enum TabKey: String, CaseIterable { case define, page }

    static let accents: [(name: String, hex: String)] = [
        ("赭红", "#A94438"), ("靛青", "#1F5FBF"), ("松绿", "#1E7A5A"), ("琥珀", "#9A6412"), ("石墨", "#3A3A3C"),
    ]

    private let defaults = UserDefaults.standard

    @Published var autoCommitUnique: Bool { didSet { defaults.set(autoCommitUnique, forKey: "autoCommitUnique") } }
    @Published var fifthKeyCommits: Bool { didSet { defaults.set(fifthKeyCommits, forKey: "fifthKeyCommits") } }
    @Published var emptyCode: EmptyCode { didSet { defaults.set(emptyCode.rawValue, forKey: "emptyCode") } }
    @Published var enterKey: EnterKey { didSet { defaults.set(enterKey.rawValue, forKey: "enterKey") } }
    @Published var tabKey: TabKey { didSet { defaults.set(tabKey.rawValue, forKey: "tabKey") } }
    @Published var adaptExact: Bool { didSet { defaults.set(adaptExact, forKey: "adaptExact") } }
    @Published var slashQuickInput: Bool { didSet { defaults.set(slashQuickInput, forKey: "slashQuickInput") } }
    @Published var tempPinyin: Bool { didSet { defaults.set(tempPinyin, forKey: "tempPinyin") } }
    @Published var mixedPinyin: Bool { didSet { defaults.set(mixedPinyin, forKey: "mixedPinyin") } }
    @Published var codeHints: Bool { didSet { defaults.set(codeHints, forKey: "codeHints") } }
    @Published var chinesePunctuation: Bool { didSet { defaults.set(chinesePunctuation, forKey: "chinesePunctuation") } }
    @Published var switchKey: SwitchKey { didSet { defaults.set(switchKey.rawValue, forKey: "switchKey") } }
    @Published var layout: Layout { didSet { defaults.set(layout.rawValue, forKey: "layout") } }
    @Published var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var accentHex: String { didSet { defaults.set(accentHex, forKey: "accentHex") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    @Published var pageSize: Int { didSet { defaults.set(pageSize, forKey: "pageSize") } }

    private init() {
        defaults.register(defaults: [
            "autoCommitUnique": true, "fifthKeyCommits": true, "codeHints": true, "chinesePunctuation": true,
            "slashQuickInput": true, "tempPinyin": true,
            "fontSize": 16.0, "pageSize": 5, "accentHex": "#A94438",
        ])
        autoCommitUnique = defaults.bool(forKey: "autoCommitUnique")
        fifthKeyCommits = defaults.bool(forKey: "fifthKeyCommits")
        emptyCode = EmptyCode(rawValue: defaults.string(forKey: "emptyCode") ?? "") ?? .keep
        enterKey = EnterKey(rawValue: defaults.string(forKey: "enterKey") ?? "") ?? .letters
        tabKey = TabKey(rawValue: defaults.string(forKey: "tabKey") ?? "") ?? .define
        codeHints = defaults.bool(forKey: "codeHints")
        adaptExact = defaults.bool(forKey: "adaptExact")
        slashQuickInput = defaults.bool(forKey: "slashQuickInput")
        tempPinyin = defaults.bool(forKey: "tempPinyin")
        mixedPinyin = defaults.bool(forKey: "mixedPinyin")
        chinesePunctuation = defaults.bool(forKey: "chinesePunctuation")
        switchKey = SwitchKey(rawValue: defaults.string(forKey: "switchKey") ?? "") ?? .leftShift
        layout = Layout(rawValue: defaults.string(forKey: "layout") ?? "") ?? .horizontal
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .system
        accentHex = defaults.string(forKey: "accentHex") ?? "#A94438"
        fontSize = min(26, max(12, defaults.double(forKey: "fontSize")))
        pageSize = min(9, max(3, defaults.integer(forKey: "pageSize")))
    }

    var accent: NSColor { NSColor(hex: accentHex) ?? NSColor(hex: "#A94438")! }

    var isDark: Bool {
        switch theme {
        case .light: return false
        case .dark: return true
        case .system: return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    var sessionOptions: Session.Options {
        var o = Session.Options()
        o.autoCommitUnique = autoCommitUnique
        o.fifthKeyCommits = fifthKeyCommits
        o.clearEmptyCode = emptyCode == .clear
        o.enterCommitsLetters = enterKey == .letters
        o.completions = codeHints
        o.pageSize = pageSize
        o.adaptExact = adaptExact
        o.slashQuickInput = slashQuickInput
        o.tempPinyin = tempPinyin
        o.mixedPinyin = mixedPinyin
        return o
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
