import XCTest
@testable import MobiCore

final class SessionTests: XCTestCase {
    let table = CodeTable(text: """
    # sample
    w 人
    wq 你
    wqvb 你好
    wqwu 你们
    wqrq 你的
    wqjg 你是
    wqiy 你没
    wqkk 你呢
    gg 五
    ggtt 五笔
    gstt 末笔
    tt 笔
    末笔测试\tgsty\t100
    """)

    func type(_ s: Session, _ text: String) -> String {
        var out = ""
        for ch in text { out += s.handle(.letter(ch)).committed }
        return out
    }

    func testExactBeforeCompletions() {
        let c = table.candidates(for: "wq")
        XCTAssertEqual(c.first, Candidate(word: "你", code: "wq"))
        XCTAssertEqual(c.map(\.word).sorted(), ["你", "你们", "你呢", "你好", "你是", "你没", "你的"].sorted())
        XCTAssertEqual(table.candidates(for: "wq", completions: false).map(\.word), ["你"])
    }

    func testRimeOrderLineIsAccepted() {
        XCTAssertEqual(table.words(for: "gsty"), ["末笔测试"])
    }

    func testSpaceCommitsFirst() {
        let s = Session(table: table)
        XCTAssertEqual(type(s, "wq"), "")
        XCTAssertEqual(s.handle(.space).committed, "你")
        XCTAssertFalse(s.isComposing)
        XCTAssertFalse(s.handle(.space).handled)
    }

    func testUniqueFourthCodeCommits() {
        let s = Session(table: table)
        XCTAssertEqual(type(s, "ggtt"), "五笔")
        XCTAssertFalse(s.isComposing)
        s.options.autoCommitUnique = false
        XCTAssertEqual(type(s, "ggtt"), "")
        XCTAssertEqual(s.buffer, "ggtt")
    }

    func testFifthKeyPushesFirstCandidate() {
        let s = Session(table: table)
        s.options.autoCommitUnique = false
        XCTAssertEqual(type(s, "ggttw"), "五笔")
        XCTAssertEqual(s.buffer, "w")
        s.reset()
        s.options.fifthKeyCommits = false
        XCTAssertEqual(type(s, "ggttw"), "")
        XCTAssertEqual(s.buffer, "ggtt")
    }

    func testEmptyCode() {
        let s = Session(table: table)
        XCTAssertEqual(type(s, "wqvx"), "")
        XCTAssertEqual(s.buffer, "wqvx")
        XCTAssertFalse(s.hasCandidates)
        XCTAssertEqual(s.handle(.space), Session.Output())
        XCTAssertEqual(s.buffer, "wqvx")
        XCTAssertEqual(s.handle(.enter).committed, "wqvx")
        s.options.clearEmptyCode = true
        XCTAssertEqual(type(s, "wqvx"), "")
        XCTAssertEqual(s.buffer, "")
    }

    func testEnterCanClear() {
        let s = Session(table: table)
        s.options.enterCommitsLetters = false
        _ = type(s, "wq")
        XCTAssertEqual(s.handle(.enter), Session.Output())
        XCTAssertFalse(s.isComposing)
    }

    func testSelectAndPaging() {
        let s = Session(table: table)
        _ = type(s, "wq")
        XCTAssertEqual(s.pageCount, 2)
        XCTAssertEqual(s.pageCandidates.count, 5)
        _ = s.handle(.pageDown)
        XCTAssertEqual(s.page, 1)
        XCTAssertEqual(s.pageCandidates.count, 2)
        _ = s.handle(.pageDown)
        XCTAssertEqual(s.page, 1)
        _ = s.handle(.pageUp)
        let second = s.pageCandidates[1].word
        XCTAssertEqual(s.handle(.select(1)).committed, second)
        _ = type(s, "wq")
        XCTAssertEqual(s.handle(.select(4 + 3)), Session.Output())
        XCTAssertTrue(s.isComposing)
    }

    func testBackspaceAndEscape() {
        let s = Session(table: table)
        _ = type(s, "wq")
        XCTAssertTrue(s.handle(.backspace).handled)
        XCTAssertEqual(s.buffer, "w")
        XCTAssertTrue(s.handle(.escape).handled)
        XCTAssertFalse(s.handle(.backspace).handled)
        XCTAssertFalse(s.handle(.escape).handled)
    }

    func testPunctuationPairsQuotes() {
        var p = Punctuation()
        XCTAssertEqual(p.map(","), "，")
        XCTAssertEqual(p.map("\""), "“")
        XCTAssertEqual(p.map("\""), "”")
        XCTAssertEqual(p.map("'"), "‘")
        XCTAssertEqual(p.map("'"), "’")
        XCTAssertNil(p.map("/"))
    }
}

final class FeatureTests: XCTestCase {
    private let table = CodeTable(text: """
    g 一 900
    gd 天 500
    ga 开 800
    gab 蒜 1
    khlg 中国 300 跨国 200 跑车 100
    kh 中 700
    tgjh 重 600
    tgjf 种 400
    tgjy 重庆 80
    yvi 庆 60
    lv 绿 70
    """)

    func testHintsFollowWeightThenUsage() {
        XCTAssertEqual(table.candidates(for: "g").map(\.word), ["一", "开", "天", "蒜"])
        let usage = UsageStore()
        usage.record(word: "天", code: "gd")
        XCTAssertEqual(table.candidates(for: "g", usage: usage).map(\.word), ["一", "天", "开", "蒜"])
    }

    func testExactOrderOnlyAdaptsWhenAsked() {
        let usage = UsageStore()
        let session = Session(table: table, usage: usage)
        for ch in "khlg" { _ = session.handle(.letter(ch)) }
        XCTAssertEqual(session.handle(.digit(3)).committed, "跑车")
        for ch in "khlg" { _ = session.handle(.letter(ch)) }
        XCTAssertEqual(session.pageCandidates.map(\.word), ["中国", "跨国", "跑车"])
        session.reset()
        session.options.adaptExact = true
        for ch in "khlg" { _ = session.handle(.letter(ch)) }
        XCTAssertEqual(session.pageCandidates.map(\.word), ["跑车", "中国", "跨国"])
    }

    func testUsageSurvivesReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mobi-\(UUID().uuidString)/usage.json")
        let store = UsageStore(url: url)
        store.record(word: "天", code: "gd")
        store.save()
        XCTAssertEqual(UsageStore(url: url).count(word: "天", code: "gd"), 1)
        store.clear()
        XCTAssertEqual(UsageStore(url: url).count(word: "天", code: "gd"), 0)
    }

    func testSlashDate() {
        let session = Session(table: table)
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute) = (2026, 10, 13, 14, 2)
        let date = Calendar.current.date(from: parts)!
        session.now = { date }
        XCTAssertTrue(session.handle(.slash).handled)
        XCTAssertEqual(session.hint, QuickInput.help)
        _ = session.handle(.letter("r"))
        _ = session.handle(.letter("q"))
        XCTAssertEqual(session.pageCandidates.map(\.word).prefix(3), ["2026年10月13日", "2026-10-13", "10月13日 星期二"])
        XCTAssertEqual(session.handle(.digit(2)).committed, "2026-10-13")
        XCTAssertFalse(session.isComposing)
    }

    func testSlashCapitalNumber() {
        let session = Session(table: table)
        _ = session.handle(.slash)
        for ch in "dx" { _ = session.handle(.letter(ch)) }
        for n in [1, 2, 8, 0] { _ = session.handle(.digit(n)) }
        XCTAssertEqual(session.handle(.space).committed, "壹仟贰佰捌拾")
        XCTAssertEqual(QuickInput.capitalNumber("1005"), "壹仟零伍")
        XCTAssertEqual(QuickInput.capitalNumber("10000"), "壹万")
        XCTAssertEqual(QuickInput.capitalNumber("100200"), "壹拾万零贰佰")
        XCTAssertEqual(QuickInput.capitalNumber("100000001"), "壹亿零壹")
        XCTAssertEqual(QuickInput.capitalNumber("100003000"), "壹亿零叁仟")
        XCTAssertEqual(QuickInput.capitalNumber("0"), "零")
    }

    func testLoneSlashStaysASlash() {
        let session = Session(table: table)
        _ = session.handle(.slash)
        XCTAssertEqual(session.handle(.space), Session.Output(committed: "/", handled: false))
        session.options.slashQuickInput = false
        XCTAssertFalse(session.handle(.slash).handled)
    }

    func testTemporaryPinyin() {
        let session = Session(table: table)
        for ch in "zz" { _ = session.handle(.letter(ch)) }
        XCTAssertFalse(session.isPinyin, "z is an ordinary letter until the index is ready")
        session.reset()

        session.pinyin = PinyinIndex(table: table)
        _ = session.handle(.letter("z"))
        XCTAssertNotNil(session.hint)
        for ch in "zhong" { _ = session.handle(.letter(ch)) }
        XCTAssertEqual(session.pageCandidates.prefix(3), [
            Candidate(word: "中", code: "kh"), Candidate(word: "重", code: "tgjh"), Candidate(word: "种", code: "tgjf"),
        ])
        for ch in "guo" { _ = session.handle(.letter(ch)) }
        XCTAssertEqual(session.handle(.space).committed, "中国")

        // 重 is read "chong" in 重庆, so it is found under both readings.
        for ch in "zchong" { _ = session.handle(.letter(ch)) }
        XCTAssertEqual(session.pageCandidates.first, Candidate(word: "重", code: "tgjh"))
        session.reset()
        for ch in "zlv" { _ = session.handle(.letter(ch)) }
        XCTAssertEqual(session.handle(.space).committed, "绿")
    }

    func testMixedPinyin() {
        let table = CodeTable(text: """
        w 人
        wo 伙
        wqvb 你好
        q 我
        trnt 我
        kh 中
        khlg 中国
        shan 山
        mmmm 冂
        """)
        let session = Session(table: table)
        session.options.mixedPinyin = true
        session.pinyin = PinyinIndex(table: table)

        // Coded "wo" first, then read "wo".
        for ch in "wo" { _ = session.handle(.letter(ch)) }
        XCTAssertEqual(session.pageCandidates, [Candidate(word: "伙", code: "wo"), Candidate(word: "我", code: "trnt")])
        XCTAssertFalse(session.isByPinyin(0))
        XCTAssertTrue(session.isByPinyin(1))
        XCTAssertEqual(session.handle(.digit(2)).committed, "我")

        // Longer than any code, yet still a reading.
        var typed = ""
        for ch in "zhongguo" { typed += session.handle(.letter(ch)).committed }
        XCTAssertEqual(typed, "")
        XCTAssertEqual(session.buffer, "zhongguo")
        XCTAssertEqual(session.handle(.space).committed, "中国")

        // The only word coded "shan" might be the start of more pinyin: it waits.
        for ch in "shan" { typed += session.handle(.letter(ch)).committed }
        XCTAssertEqual(typed, "")
        XCTAssertEqual(session.handle(.space).committed, "山")

        // No reading starts like this, so Wubi goes on as ever.
        for ch in "wqvb" { typed += session.handle(.letter(ch)).committed }
        XCTAssertEqual(typed, "你好")
        for ch in "mmmmw" { typed += session.handle(.letter(ch)).committed }
        XCTAssertEqual(typed, "你好冂")
        XCTAssertEqual(session.buffer, "w")
    }

    func testRareCharactersYieldToHints() {
        let table = CodeTable(text: "yiy 䚱 𧦋\nyiyy 应该 100\nyiyj 哀鸿遍野 10\nyny 房 訫\nynyy 房子")
        XCTAssertEqual(table.candidates(for: "yiy").map(\.word), ["应该", "哀鸿遍野", "䚱", "𧦋"])
        XCTAssertEqual(table.candidates(for: "yny").map(\.word), ["房", "房子", "訫"])
        XCTAssertEqual(table.candidates(for: "yiy", completions: false).map(\.word), ["䚱", "𧦋"])
        table.addUserWords(text: "yiy 䚱")
        XCTAssertEqual(table.candidates(for: "yiy").first?.word, "䚱")
        XCTAssertFalse(CodeTable.isRare("見"))
        XCTAssertFalse(CodeTable.isRare("应该"))
        XCTAssertTrue(CodeTable.isRare("哀𧦋"))
    }

    func testRareCharactersOpenThePageAfterHints() {
        let table = CodeTable(text: "yiy 䚱\nyiya 应 9\nyiyb 该 8\nyiyc 就 7\nyiyd 说 6\nyiye 让 5\nyiyf 读 4\nyny 房 訫")
        let s = Session(table: table)
        for ch in "yiy" { _ = s.handle(.letter(ch)) }
        XCTAssertEqual(s.pageCandidates.map(\.word), ["应", "该", "就", "说", "让"])
        _ = s.handle(.pageDown)
        XCTAssertEqual(s.pageCandidates.map(\.word), ["䚱", "读"])
        s.reset()
        for ch in "yny" { _ = s.handle(.letter(ch)) }
        XCTAssertEqual(s.pageCandidates.map(\.word), ["房", "訫"])
    }

    func testUserWordsComeFirst() {
        let table = CodeTable(text: "khlg 中国 跨国\nrcq 反")
        table.addUserWords(text: "# mine\nrcql 反链\nkhlg 跑车 跨国")
        XCTAssertEqual(table.words(for: "rcql"), ["反链"])
        XCTAssertEqual(table.words(for: "khlg"), ["跑车", "跨国", "中国"])
        XCTAssertEqual(table.candidates(for: "rcq").map(\.word), ["反", "反链"])
    }

    func testDefineWordForEmptyCode() {
        let table = CodeTable(text: "rci 反\nqlp 链\nqlpy 链\nrcq 反\n")
        let session = Session(table: table)
        var saved: [String] = []
        session.onDefine = { saved.append("\($0) \($1)") }
        for ch in "rcql" { XCTAssertEqual(session.handle(.letter(ch)).committed, "") }
        XCTAssertTrue(session.canDefine)
        XCTAssertEqual(session.handle(.define), Session.Output())
        XCTAssertEqual(session.defining, "rcql")
        XCTAssertEqual(session.buffer, "")

        for ch in "rci" { XCTAssertEqual(session.handle(.letter(ch)).committed, "") }
        XCTAssertEqual(session.handle(.space).committed, "")
        XCTAssertEqual(session.definedWord, "反")
        for ch in "qlp" { _ = session.handle(.letter(ch)) }
        _ = session.handle(.space)
        XCTAssertEqual(session.definedWord, "反链")
        _ = session.handle(.backspace)
        XCTAssertEqual(session.definedWord, "反")
        for ch in "qlp" { _ = session.handle(.letter(ch)) }
        _ = session.handle(.space)

        XCTAssertEqual(session.handle(.enter), Session.Output(committed: "反链"))
        XCTAssertFalse(session.isComposing)
        XCTAssertEqual(saved, ["rcql 反链"])
        XCTAssertEqual(table.words(for: "rcql"), ["反链"])

        // Escape leaves no trace; backspace on an empty word returns to the code.
        for ch in "rcqx" { _ = session.handle(.letter(ch)) }
        _ = session.handle(.define)
        _ = session.handle(.backspace)
        XCTAssertEqual(session.buffer, "rcqx")
        XCTAssertFalse(session.isDefining)
        _ = session.handle(.define)
        _ = session.handle(.escape)
        XCTAssertFalse(session.isComposing)
        XCTAssertEqual(saved.count, 1)
    }

    func testUserWordFile() {
        let text = "# mine\nrcql 反链\nkhlg 跑车 跨国\n"
        let entries = UserWords.parse(text)
        XCTAssertEqual(entries.map(\.id), ["rcql 反链", "khlg 跑车", "khlg 跨国"])
        XCTAssertEqual(UserWords.removing(entries[1], from: text), "# mine\nrcql 反链\nkhlg 跨国\n")
        XCTAssertEqual(UserWords.removing(entries[0], from: text), "# mine\nkhlg 跑车 跨国\n")

        let table = CodeTable(text: "khlg 中国 跨国")
        table.addUserWords(text: text)
        table.removeUserWord("跑车", code: "khlg")
        table.removeUserWord("跨国", code: "khlg")
        table.removeUserWord("反链", code: "rcql")
        XCTAssertEqual(table.words(for: "khlg"), ["跨国", "中国"])
        XCTAssertEqual(table.words(for: "rcql"), [])
        XCTAssertEqual(table.candidates(for: "rcq").map(\.word), [])
    }

    func testDefineWordBesideExistingOnes() {
        let table = CodeTable(text: "rwud 摄像头 甲 乙\nrwy 推\nudp 送\n")
        let session = Session(table: table)
        session.options.pageSize = 2
        for ch in "rwud" { _ = session.handle(.letter(ch)) }
        XCTAssertTrue(session.canDefine)
        XCTAssertFalse(session.isLastPage)
        _ = session.handle(.pageDown)
        XCTAssertTrue(session.isLastPage)
        _ = session.handle(.define)
        for ch in "rwy" { _ = session.handle(.letter(ch)) }
        _ = session.handle(.space)
        for ch in "udp" { _ = session.handle(.letter(ch)) }
        _ = session.handle(.space)
        XCTAssertEqual(session.handle(.enter).committed, "推送")
        XCTAssertEqual(table.words(for: "rwud"), ["推送", "摄像头", "甲", "乙"])
    }

    func testWordCodeFollowsWubiRules() {
        let table = CodeTable(text: "rwp 迭\nrwpi 迭\nwa 代\nway 代\nl 连\nlpk 连\nfcu 云\niawn 港\nk 中\nkhk 中\nwxe 华\nw 人\nnav 民\na 国\nlgyi 国")
        table.addUserWords(text: "x 迭")
        XCTAssertEqual(table.wordCode(for: "迭代"), "rwwa")
        XCTAssertEqual(table.wordCode(for: "连云港"), "lfia")
        XCTAssertEqual(table.wordCode(for: "中华人民"), "kwwn")
        XCTAssertEqual(table.wordCode(for: "中华人民国"), "kwwl")
        XCTAssertNil(table.wordCode(for: "迭"))
        XCTAssertNil(table.wordCode(for: "迭甲"))
        XCTAssertNil(table.wordCode(for: "人人"))
    }

    func testDefinedWordTakesItsOwnCode() {
        let table = CodeTable(text: "rww 失 抢\nrwwa 抚今追昔\nrwp 迭\nrwpi 迭\nwa 代\nway 代\nrwu 推")
        let session = Session(table: table)
        var saved: [String] = []
        session.onDefine = { saved.append("\($0) \($1)") }
        for ch in "rww" { _ = session.handle(.letter(ch)) }
        XCTAssertTrue(session.canDefine)
        _ = session.handle(.define)
        XCTAssertEqual(session.definingCode, "rww")
        for ch in "rwp" { _ = session.handle(.letter(ch)) }
        _ = session.handle(.space)
        XCTAssertEqual(session.definingCode, "rww")
        for ch in "wa" { _ = session.handle(.letter(ch)) }
        _ = session.handle(.space)
        XCTAssertEqual(session.definingCode, "rwwa")
        XCTAssertEqual(session.handle(.enter).committed, "迭代")
        XCTAssertEqual(saved, ["rwwa 迭代"])
        XCTAssertEqual(table.words(for: "rwwa"), ["迭代", "抚今追昔"])
        XCTAssertEqual(table.words(for: "rww"), ["失", "抢"])
    }
}
