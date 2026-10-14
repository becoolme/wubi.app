import Foundation

/// Slash shortcuts: `/rq` date, `/sj` time, `/dx1280` capital numerals, `/fh` symbols.
public enum QuickInput {
    public static let help = "rq 日期    sj 时间    dx 大写数字    fh 符号"
    private static let commands = ["rq", "sj", "dx", "fh"]

    /// Results for what follows the slash; empty when the code is incomplete or unknown.
    public static func results(for code: String, now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let c = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second], from: now)
        guard let y = c.year, let mo = c.month, let d = c.day, let h = c.hour, let mi = c.minute, let s = c.second else { return [] }
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
        switch code {
        case "rq":
            let weekday = ["日", "一", "二", "三", "四", "五", "六"][((c.weekday ?? 1) - 1) % 7]
            return ["\(y)年\(mo)月\(d)日", "\(y)-\(two(mo))-\(two(d))", "\(mo)月\(d)日 星期\(weekday)", "\(y)/\(two(mo))/\(two(d))"]
        case "sj":
            return ["\(two(h)):\(two(mi))", "\(two(h)):\(two(mi)):\(two(s))", "\(h)点\(two(mi))分",
                    "\(y)-\(two(mo))-\(two(d)) \(two(h)):\(two(mi))"]
        case "fh":
            return "→ ← ↑ ↓ ★ ☆ § ℃ ¥ © ® ™ ° ± × ÷ ≠ ≤ ≥ ≈ ∞ √ ✓ ✗ • ※ № ◆ ○ ●".split(separator: " ").map(String.init)
        default:
            guard code.hasPrefix("dx"), let capital = capitalNumber(String(code.dropFirst(2))) else { return [] }
            return [capital, capital + "元整"]
        }
    }

    /// What to show while there are no results yet; nil when the code cannot become a shortcut.
    public static func hint(for code: String) -> String? {
        if code == "dx" { return "接着输入数字，如 /dx1280" }
        if code.hasPrefix("dx") { return nil }
        return commands.contains { $0.hasPrefix(code) } ? help : nil
    }

    public static func acceptsDigits(_ code: String) -> Bool { code.hasPrefix("dx") }

    /// 1280 → 壹仟贰佰捌拾. Whole numbers of up to 16 digits.
    public static func capitalNumber(_ digits: String) -> String? {
        guard !digits.isEmpty, digits.count <= 16, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        let numerals = Array("零壹贰叁肆伍陆柒捌玖")
        let small = ["仟", "佰", "拾", ""]
        let big = ["", "万", "亿", "万亿"]
        var values = digits.utf8.map { Int($0) - 48 }
        while values.count % 4 != 0 { values.insert(0, at: 0) }
        let groups = values.count / 4

        var result = ""
        var skippedGroup = false
        for g in 0..<groups {
            let group = Array(values[g * 4..<g * 4 + 4])
            if group.allSatisfy({ $0 == 0 }) {
                skippedGroup = !result.isEmpty
                continue
            }
            var text = ""
            var zero = false
            for (i, v) in group.enumerated() {
                if v == 0 {
                    zero = true
                    continue
                }
                if zero, !(text.isEmpty && result.isEmpty) { text += "零" }
                zero = false
                text.append(numerals[v])
                text += small[i]
            }
            if skippedGroup, !text.hasPrefix("零") { text = "零" + text }
            skippedGroup = false
            result += text + big[groups - 1 - g]
        }
        return result.isEmpty ? "零" : result
    }
}
