import Foundation

/// Pinyin lookup for the words of a code table, for when a character's Wubi code will not come to mind.
/// Readings come from the system's Mandarin transliteration, so no pinyin dictionary is bundled.
public final class PinyinIndex {
    private struct Item {
        let word: String
        let code: String
        let weight: Int
    }

    private var items: [String: [Item]] = [:]
    private var keys: [String] = []

    public init(table: CodeTable) {
        // Each word once, with its fullest code and its best weight.
        var best: [String: (code: String, weight: Int)] = [:]
        table.forEachEntry { code, word, weight in
            guard word.unicodeScalars.allSatisfy(PinyinIndex.isHan) else { return }
            if let old = best[word] {
                best[word] = (code.count > old.code.count ? code : old.code, max(weight, old.weight))
            } else {
                best[word] = (code, weight)
            }
        }

        var primary: [String: String] = [:]
        var extra: [String: Set<String>] = [:]
        for (word, info) in best {
            guard let syllables = PinyinIndex.syllables(of: word) else { continue }
            items[syllables.joined(), default: []].append(Item(word: word, code: info.code, weight: info.weight))
            if word.count == 1 {
                primary[word] = syllables.joined()
            } else if syllables.count == word.count {
                // A word shows how each of its characters is read there: 银行 gives 行 "hang".
                for (ch, reading) in zip(word, syllables) { extra[String(ch), default: []].insert(reading) }
            }
        }
        for (reading, chars) in PinyinIndex.otherReadings {
            for ch in chars { extra[String(ch), default: []].insert(reading) }
        }
        for (ch, readings) in extra {
            guard let info = best[ch], let main = primary[ch] else { continue }
            for reading in readings where reading != main && items[reading]?.contains(where: { $0.word == ch }) != true {
                items[reading, default: []].append(Item(word: ch, code: info.code, weight: info.weight))
            }
        }
        for key in items.keys {
            items[key]?.sort { $0.weight != $1.weight ? $0.weight > $1.weight : $0.word < $1.word }
        }
        keys = items.keys.sorted()
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Some word's reading starts with these letters.
    public func hasPrefix(_ letters: String) -> Bool {
        let i = lowerBound(letters)
        return i < keys.count && keys[i].hasPrefix(letters)
    }

    private func lowerBound(_ pinyin: String) -> Int {
        var lo = 0
        var hi = keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if keys[mid] < pinyin { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Second readings of common characters that the system transliteration does not offer on its own.
    private static let otherReadings: [String: String] = [
        "hang": "行巷", "xing": "省", "chang": "长场厂", "zhang": "长涨", "yue": "乐说钥", "le": "乐了",
        "jiao": "觉角校教", "jue": "觉角", "hai": "还", "huan": "还", "dou": "都", "du": "都读度",
        "de": "的地得", "di": "的地", "dei": "得", "liao": "了", "zhe": "着", "zhao": "着朝",
        "zhuo": "着", "wei": "为", "kuai": "会", "hui": "会", "chong": "重种", "mo": "没万", "mei": "没",
        "shao": "少", "hao": "好号", "kan": "看", "shu": "数", "shuo": "数说", "chuan": "传", "zhuan": "传转",
        "diao": "调", "tiao": "调", "chao": "朝", "cang": "藏", "zang": "藏", "dan": "单弹", "shan": "单",
        "tan": "弹", "jiang": "降强", "xiang": "降相", "bian": "便", "pian": "便", "da": "大", "dai": "大",
        "ceng": "曾", "zeng": "曾", "cha": "差", "chai": "差", "chu": "处", "lv": "率", "shuai": "率",
        "gei": "给", "ji": "给几系", "gan": "干", "geng": "更", "xue": "血", "xie": "血", "bao": "薄",
        "bo": "薄", "shen": "什参", "shi": "什石似", "ka": "卡", "qia": "卡", "can": "参", "sheng": "省",
        "shui": "说", "su": "宿", "xiu": "宿", "ying": "应", "zhi": "只", "kong": "空", "qiang": "强",
        "xi": "系", "bei": "背", "jian": "间见", "xian": "见", "nan": "难", "ning": "宁", "pu": "朴",
        "qu": "区", "ou": "区", "sai": "塞", "se": "色塞", "shai": "色", "she": "折", "xia": "吓", "he": "和吓",
        "huo": "和", "hu": "和", "yao": "要", "yu": "与", "zai": "载仔", "zi": "仔", "zhong": "种重中",
    ]

    private static func isHan(_ s: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(s.value) || (0x20000...0x323AF).contains(s.value)
    }

    private static func syllables(of word: String) -> [String]? {
        guard let latin = word.applyingTransform(.mandarinToLatin, reverse: false)?.lowercased() else { return nil }
        // Drop the tone marks scalar by scalar; "ü" (u + diaeresis) is typed as "v".
        var plain = String.UnicodeScalarView()
        for scalar in latin.decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.value == 0x308, plain.last == "u" {
                plain.removeLast()
                plain.append("v")
            } else if !(0x300...0x36F).contains(scalar.value) {
                plain.append(scalar)
            }
        }
        let parts = String(plain).split(separator: " ").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0.utf8.allSatisfy { $0 >= 97 && $0 <= 122 } }) else { return nil }
        return parts
    }

    /// Words read exactly as `pinyin`, most common first, then words whose reading starts with it.
    /// Each candidate carries its Wubi code. `typed` is what the picks are counted under.
    public func candidates(for pinyin: String, usage: UsageStore? = nil, typed: String = "",
                           exactLimit: Int = 120, prefixLimit: Int = 40) -> [Candidate] {
        guard !pinyin.isEmpty else { return [] }
        func ranked(_ list: [Item]) -> [Item] {
            guard let usage, !usage.isEmpty else { return list }
            return list.enumerated()
                .map { (offset: $0.offset, item: $0.element, count: usage.count(word: $0.element.word, code: typed)) }
                .sorted { $0.count != $1.count ? $0.count > $1.count : $0.offset < $1.offset }
                .map(\.item)
        }
        var result = ranked(items[pinyin] ?? []).prefix(exactLimit).map { Candidate(word: $0.word, code: $0.code) }

        guard prefixLimit > 0 else { return result }
        var longer: [Item] = []
        var i = lowerBound(pinyin)
        while i < keys.count, keys[i].hasPrefix(pinyin) {
            if keys[i] != pinyin { longer.append(contentsOf: (items[keys[i]] ?? []).prefix(8)) }
            i += 1
        }
        longer.sort { $0.weight != $1.weight ? $0.weight > $1.weight : $0.word < $1.word }
        var seen = Set(result.map(\.word))
        var added = 0
        for item in ranked(longer) where !seen.contains(item.word) {
            seen.insert(item.word)
            result.append(Candidate(word: item.word, code: item.code))
            added += 1
            if added >= prefixLimit { break }
        }
        return result
    }
}
