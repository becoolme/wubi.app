import Foundation

/// Maps ASCII punctuation to full-width Chinese punctuation, pairing quotes as they are typed.
public struct Punctuation {
    private var doubleOpen = false
    private var singleOpen = false

    public init() {}

    private static let fixed: [Character: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！", ";": "；", ":": "：",
        "\\": "、", "(": "（", ")": "）", "<": "《", ">": "》",
        "[": "【", "]": "】", "{": "「", "}": "」",
        "^": "……", "_": "——", "$": "￥", "~": "～", "`": "·",
    ]

    public mutating func map(_ ch: Character) -> String? {
        switch ch {
        case "\"":
            doubleOpen.toggle()
            return doubleOpen ? "“" : "”"
        case "'":
            singleOpen.toggle()
            return singleOpen ? "‘" : "’"
        default:
            return Punctuation.fixed[ch]
        }
    }
}
