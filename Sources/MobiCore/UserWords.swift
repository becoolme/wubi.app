import Foundation

/// The user's own word file: `code word [word…]` per line, `#` for comments.
public enum UserWords {
    public struct Entry: Equatable, Identifiable {
        public let code: String
        public let word: String
        public var id: String { "\(code) \(word)" }

        public init(code: String, word: String) {
            self.code = code
            self.word = word
        }
    }

    public static func isCode(_ s: String) -> Bool {
        !s.isEmpty && s.count <= Session.maxCodeLength && s.utf8.allSatisfy { $0 >= 97 && $0 <= 122 }
    }

    /// Entries in file order.
    public static func parse(_ text: String) -> [Entry] {
        var result: [Entry] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let (code, words) = fields(line) else { continue }
            for word in words where !result.contains(Entry(code: code, word: word)) {
                result.append(Entry(code: code, word: word))
            }
        }
        return result
    }

    /// The file with one entry taken out; comments and every other line stay as they were.
    public static func removing(_ entry: Entry, from text: String) -> String {
        var lines: [String] = []
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            guard let (code, words) = fields(line), code == entry.code, words.contains(entry.word) else {
                lines.append(String(line))
                continue
            }
            let rest = words.filter { $0 != entry.word }
            if !rest.isEmpty { lines.append(([code] + rest).joined(separator: " ")) }
        }
        return lines.joined(separator: "\n")
    }

    private static func fields(_ line: Substring) -> (code: String, words: [String])? {
        if line.hasPrefix("#") { return nil }
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count >= 2, isCode(parts[0]) else { return nil }
        let words = parts.dropFirst().filter { !$0.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }
        return words.isEmpty ? nil : (parts[0], Array(words))
    }
}
