import Cocoa
import MobiCore

/// Tells whether the system has a font for every character of a word. Rare characters from
/// the Unicode extension blocks often have none and would show as a boxed question mark.
private final class Glyphs {
    private var covered = CharacterSet()

    init() {
        // Asking the system for a fallback font character by character takes seconds for a
        // whole table; the fonts PingFang falls back to cover the same characters in no time.
        let base = CTFontCreateWithName("PingFangSC-Regular" as CFString, 16, nil)
        let fallbacks = CTFontCopyDefaultCascadeListForLanguages(base, ["zh-Hans"] as CFArray) as? [CTFontDescriptor] ?? []
        for descriptor in [CTFontCopyFontDescriptor(base)] + fallbacks {
            if let set = CTFontDescriptorCopyAttribute(descriptor, kCTFontCharacterSetAttribute) as? CharacterSet {
                covered.formUnion(set)
            }
        }
    }

    func canShow(_ word: String) -> Bool {
        word.unicodeScalars.allSatisfy { $0.value < 0x7F || (0x4E00...0x9FA5).contains($0.value) || covered.contains($0) }
    }
}

enum Dictionary {
    /// A table the user dropped into Application Support replaces the bundled one.
    static var userTableURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mobi/wubi86.txt")
    }

    /// The user's own words, laid over whichever table is loaded.
    static var userWordsURL: URL {
        userTableURL.deletingLastPathComponent().appendingPathComponent("user.txt")
    }

    static let table: CodeTable = {
        let table = baseTable
        if let text = try? String(contentsOf: userWordsURL, encoding: .utf8) {
            table.addUserWords(text: text)
        }
        return table
    }()

    private static let baseTable: CodeTable = {
        let urls = [userTableURL, Bundle.main.url(forResource: "wubi86", withExtension: "txt")].compactMap { $0 }
        for url in urls {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let glyphs = Glyphs()
                let table = CodeTable(text: text, keep: glyphs.canShow)
                if !table.isEmpty {
                    NSLog("Mobi: loaded %d entries from %@", table.entryCount, url.path)
                    return table
                }
            }
        }
        NSLog("Mobi: no code table found")
        return CodeTable(text: "")
    }()

    static func userWords() -> [UserWords.Entry] {
        UserWords.parse((try? String(contentsOf: userWordsURL, encoding: .utf8)) ?? "")
    }

    static func removeUserWord(_ entry: UserWords.Entry) {
        guard let text = try? String(contentsOf: userWordsURL, encoding: .utf8) else { return }
        do {
            try UserWords.removing(entry, from: text).write(to: userWordsURL, atomically: true, encoding: .utf8)
            table.removeUserWord(entry.word, code: entry.code)
        } catch {
            NSLog("Mobi: could not update user words: %@", error.localizedDescription)
        }
    }

    /// Adds a word from the settings window: to the table in use and to the file.
    static func addUserWord(code: String, word: String) {
        table.addUserWords(text: "\(code) \(word)")
        saveUserWord(code: code, word: word)
    }

    /// Appends a word the user just defined to their word file.
    static func saveUserWord(code: String, word: String) {
        let url = userWordsURL
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        text += "\(code) \(word)\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Mobi: could not save user word: %@", error.localizedDescription)
        }
    }

    static let usage = UsageStore(url: userTableURL.deletingLastPathComponent().appendingPathComponent("usage.json"))

    /// Nil until the index has been built in the background, which takes a couple of seconds.
    private(set) static var pinyin: PinyinIndex?

    static func preparePinyin() {
        let table = self.table
        DispatchQueue.global(qos: .utility).async {
            let index = PinyinIndex(table: table)
            DispatchQueue.main.async { pinyin = index }
        }
    }
}
