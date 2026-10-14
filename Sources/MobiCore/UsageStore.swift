import Foundation

/// How often each word was picked, kept on this Mac only.
public final class UsageStore {
    private var counts: [String: Int] = [:]
    private let url: URL?
    private var unsaved = 0

    /// Pass nil to keep the counts in memory only.
    public init(url: URL? = nil) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Int].self, from: data) {
            counts = saved
        }
    }

    public var isEmpty: Bool { counts.isEmpty }

    private func key(_ word: String, _ code: String) -> String { code + " " + word }

    public func count(word: String, code: String) -> Int {
        counts.isEmpty ? 0 : counts[key(word, code)] ?? 0
    }

    public func record(word: String, code: String) {
        guard !word.isEmpty, !code.isEmpty else { return }
        counts[key(word, code), default: 0] += 1
        unsaved += 1
        if unsaved >= 20 { save() }
    }

    public func save() {
        guard let url, unsaved > 0 else { return }
        unsaved = 0
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(counts) { try? data.write(to: url, options: .atomic) }
    }

    public func clear() {
        counts = [:]
        unsaved = 0
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}
