import Foundation

public struct Candidate: Equatable {
    public let word: String
    public let code: String

    public init(word: String, code: String) {
        self.word = word
        self.code = code
    }
}

/// A Wubi code table: plain text, one entry per line, `code word [weight] [word [weight]…]`.
/// A number after a word is how common that word is; it only orders code hints.
/// Lines written as `word code [weight]` (the order Rime dictionaries use) are accepted too.
public final class CodeTable {
    private struct Entry {
        let word: String
        var weight: Int
    }

    private var exact: [String: [Entry]] = [:]
    private var codes: [String] = []
    private let keep: ((String) -> Bool)?
    /// User words the table already had under the same code; removing those must not drop them.
    private var shadowed: Set<String> = []
    /// Words the user added, as `code word`. These are never treated as rare.
    private var userWords: Set<String> = []
    private var rareCache: [String: Bool] = [:]

    /// `keep` can turn words away, e.g. those the system has no font to draw.
    public init(text: String, keep: ((String) -> Bool)? = nil) {
        self.keep = keep
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else { continue }
            if CodeTable.isCode(parts[0]) {
                let code = String(parts[0])
                var i = 1
                while i < parts.count {
                    if CodeTable.isNumber(parts[i]) { i += 1; continue }
                    var weight = 0
                    if i + 1 < parts.count, CodeTable.isNumber(parts[i + 1]) { weight = Int(parts[i + 1]) ?? 0 }
                    add(code: code, word: String(parts[i]), weight: weight)
                    i += 1
                }
            } else if CodeTable.isCode(parts[1]) {
                let weight = parts.count > 2 && CodeTable.isNumber(parts[2]) ? Int(parts[2]) ?? 0 : 0
                add(code: String(parts[1]), word: String(parts[0]), weight: weight)
            }
        }
        codes = exact.keys.sorted()
    }

    public var isEmpty: Bool { exact.isEmpty }
    public var entryCount: Int { exact.values.reduce(0) { $0 + $1.count } }

    private func add(code: String, word: String, weight: Int) {
        if exact[code]?.contains(where: { $0.word == word }) == true { return }
        if let keep, !keep(word) { return }
        exact[code, default: []].append(Entry(word: word, weight: weight))
    }

    /// Lays the user's own words over the table. Same line formats as the table; these words
    /// come first under their code, in the order the file lists them.
    public func addUserWords(text: String) {
        let user = CodeTable(text: text)
        for (code, entries) in user.exact {
            let words = Set(entries.map(\.word))
            for word in words { userWords.insert("\(code) \(word)") }
            for entry in exact[code] ?? [] where words.contains(entry.word) {
                shadowed.insert("\(code) \(entry.word)")
            }
            exact[code] = entries + (exact[code] ?? []).filter { !words.contains($0.word) }
        }
        codes = exact.keys.sorted()
    }

    /// Takes back a word added with `addUserWords`. A word the table had anyway stays.
    public func removeUserWord(_ word: String, code: String) {
        userWords.remove("\(code) \(word)")
        guard !shadowed.contains("\(code) \(word)"), var entries = exact[code] else { return }
        entries.removeAll { $0.word == word }
        exact[code] = entries.isEmpty ? nil : entries
        codes = exact.keys.sorted()
    }

    private static func isCode(_ s: Substring) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { $0 >= 97 && $0 <= 122 }
    }

    private static func isNumber(_ s: Substring) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    /// A word with a character in neither GB2312 nor Big5: extension-block ideographs,
    /// Japanese forms and the like, which almost nobody means to type.
    public static func isRare(_ word: String) -> Bool {
        word.contains { ch in
            let s = String(ch)
            return !s.canBeConverted(to: gb2312) && !s.canBeConverted(to: big5)
        }
    }

    private static let gb2312 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_CN.rawValue)))
    private static let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))

    private func isRare(_ word: String, code: String) -> Bool {
        if userWords.contains("\(code) \(word)") { return false }
        if let known = rareCache[word] { return known }
        let rare = CodeTable.isRare(word)
        rareCache[word] = rare
        return rare
    }

    /// Every entry, in no particular order.
    public func forEachEntry(_ body: (_ code: String, _ word: String, _ weight: Int) -> Void) {
        for (code, entries) in exact {
            for entry in entries { body(code, entry.word, entry.weight) }
        }
    }

    /// Words for exactly this code, in table order.
    public func words(for code: String) -> [String] {
        (exact[code] ?? []).map(\.word)
    }

    /// Exact matches first, then code hints: words whose code starts with `input`.
    ///
    /// Exact matches keep the table's order unless `adaptExact` is set, in which case the ones
    /// picked more often move forward. Rare ones (see `isRare`) go after the hints, so a code
    /// typed short still offers the common word first. Hints are ordered by how often they
    /// were picked, then shortest code, then the table's weight.
    public func candidates(for input: String, completions: Bool = true, completionLimit: Int = 40,
                           usage: UsageStore? = nil, adaptExact: Bool = false) -> [Candidate] {
        guard !input.isEmpty else { return [] }
        var words = self.words(for: input)
        if adaptExact, let usage, words.count > 1 {
            let ranked = words.enumerated().map { (offset: $0.offset, word: $0.element, count: usage.count(word: $0.element, code: input)) }
            words = ranked.sorted { $0.count != $1.count ? $0.count > $1.count : $0.offset < $1.offset }.map(\.word)
        }
        let rare = words.filter { isRare($0, code: input) }
        var result = words.filter { !rare.contains($0) }.map { Candidate(word: $0, code: input) }
        let tail = rare.map { Candidate(word: $0, code: input) }
        guard completions else { return result + tail }

        var lo = 0
        var hi = codes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if codes[mid] < input { lo = mid + 1 } else { hi = mid }
        }
        var hints: [(word: String, code: String, weight: Int, count: Int)] = []
        var i = lo
        while i < codes.count, codes[i].hasPrefix(input) {
            let code = codes[i]
            i += 1
            if code == input { continue }
            for entry in exact[code] ?? [] {
                hints.append((entry.word, code, entry.weight, usage?.count(word: entry.word, code: code) ?? 0))
            }
        }
        hints.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            if $0.code.count != $1.code.count { return $0.code.count < $1.code.count }
            if $0.weight != $1.weight { return $0.weight > $1.weight }
            return $0.code < $1.code
        }
        var seen = Set(words)
        var added = 0
        for hint in hints where !seen.contains(hint.word) {
            seen.insert(hint.word)
            result.append(Candidate(word: hint.word, code: hint.code))
            added += 1
            if added >= completionLimit { break }
        }
        return result + tail
    }
}
