import Cocoa
import SwiftUI
import MobiCore

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private var clickMonitor: Any?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "末笔"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
            // A click anywhere outside a text field ends editing in it.
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak w] event in
                guard let w, event.window === w, w.firstResponder is NSText else { return event }
                var hit = w.contentView?.hitTest(event.locationInWindow)
                while let view = hit {
                    if view is NSText || view is NSTextField { return event }
                    hit = view.superview
                }
                w.makeFirstResponder(nil)
                return event
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private enum Pane: String, CaseIterable, Identifiable {
    case general, words, appearance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "通用"
        case .words: return "用户词库"
        case .appearance: return "外观"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .words: return "text.book.closed"
        case .appearance: return "circle.lefthalf.filled"
        }
    }
}

private struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @State private var pane: Pane? = .general
    @State private var usageCleared = false

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch pane {
                case .appearance: appearance
                case .words: UserWordsPane()
                default: general
                }
            }
            .formStyle(.grouped)
            .navigationTitle(pane?.title ?? "")
        }
        .tint(Color(nsColor: settings.accent))
        .frame(minWidth: 760, minHeight: 520)
    }

    private var general: some View {
        Form {
            Section("上屏") {
                Toggle("四码唯一时自动上屏", isOn: $settings.autoCommitUnique)
                Toggle("第五码顶字上屏", isOn: $settings.fifthKeyCommits)
                Picker("空码时", selection: $settings.emptyCode) {
                    Text("保留编码，等待修改").tag(Settings.EmptyCode.keep)
                    Text("清空编码").tag(Settings.EmptyCode.clear)
                }
                Picker("回车键", selection: $settings.enterKey) {
                    Text("上屏编码字母").tag(Settings.EnterKey.letters)
                    Text("清空编码").tag(Settings.EnterKey.clear)
                }
            }
            Section("提示") {
                Toggle(isOn: $settings.codeHints) {
                    Text("编码提示")
                    Text("候选里列出以当前编码开头的词，并显示剩余编码；常选的排在前面")
                }
            }
            Section("词频") {
                Toggle(isOn: $settings.adaptExact) {
                    Text("按使用频率调整重码顺序")
                    Text("关闭时同一编码的候选位置固定，适合盲打")
                }
                LabeledContent {
                    Button(usageCleared ? "已清除" : "清除…") {
                        Dictionary.usage.clear()
                        usageCleared = true
                    }
                    .disabled(usageCleared)
                } label: {
                    Text("使用记录")
                    Text("只保存在这台 Mac 上")
                }
            }
            Section("快捷输入") {
                Toggle(isOn: $settings.mixedPinyin) {
                    Text("五笔拼音混输")
                    Text("直接打拼音也能出字，排在五笔候选之后；可能是拼音的四码不再自动上屏")
                }
                Toggle(isOn: $settings.tempPinyin) {
                    Text("Z 键临时拼音")
                    Text(settings.mixedPinyin ? "混输时不需要按 z" : "按 z 再输入拼音，候选后面显示五笔编码")
                }
                .disabled(settings.mixedPinyin)
                Toggle(isOn: $settings.slashQuickInput) {
                    Text("斜杠快捷输入")
                    Text("/rq 日期　/sj 时间　/dx1280 大写数字　/fh 符号")
                }
            }
            Section("中英文") {
                Picker("中英切换", selection: $settings.switchKey) {
                    Text("左 Shift").tag(Settings.SwitchKey.leftShift)
                    Text("右 Shift").tag(Settings.SwitchKey.rightShift)
                    Text("任一 Shift").tag(Settings.SwitchKey.anyShift)
                    Text("关闭").tag(Settings.SwitchKey.off)
                }
                Toggle("中文模式下使用中文标点", isOn: $settings.chinesePunctuation)
            }
        }
    }

    private var appearance: some View {
        Form {
            Section("候选窗") {
                Picker("排列", selection: $settings.layout) {
                    Text("横排").tag(Settings.Layout.horizontal)
                    Text("竖排").tag(Settings.Layout.vertical)
                }
                .pickerStyle(.segmented)
                Picker("主题", selection: $settings.theme) {
                    Text("跟随系统").tag(Settings.Theme.system)
                    Text("浅色").tag(Settings.Theme.light)
                    Text("深色").tag(Settings.Theme.dark)
                }
                .pickerStyle(.segmented)
                LabeledContent("强调色") {
                    HStack(spacing: 10) {
                        ForEach(Settings.accents, id: \.hex) { accent in
                            Button {
                                settings.accentHex = accent.hex
                            } label: {
                                Circle()
                                    .fill(Color(nsColor: NSColor(hex: accent.hex)!))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: settings.accentHex == accent.hex ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(accent.name)
                            .help(accent.name)
                        }
                    }
                }
            }
            Section("文字") {
                LabeledContent("字号") {
                    HStack {
                        Slider(value: $settings.fontSize, in: 12...26, step: 1).frame(width: 200)
                        Text("\(Int(settings.fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Stepper("每页候选数　\(settings.pageSize)", value: $settings.pageSize, in: 3...9)
            }
        }
    }
}

private struct UserWordsPane: View {
    @State private var entries: [UserWords.Entry] = []
    @State private var code = ""
    @State private var word = ""
    @State private var filter = ""
    /// Shown after a press of 添加 that could not go through.
    @State private var complaint: String?

    private var newWord: String { word.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Why the entry being typed cannot be added yet; nil when it can.
    private var problem: String? {
        if code.isEmpty || newWord.isEmpty { return "先填上编码和词" }
        if !UserWords.isCode(code) { return "编码是 1 到 4 个小写字母" }
        if newWord.contains(where: \.isWhitespace) { return "词里不能有空格" }
        if entries.contains(UserWords.Entry(code: code, word: newWord)) { return "已经有这个词了" }
        return nil
    }

    private var shown: [UserWords.Entry] {
        filter.isEmpty ? entries : entries.filter { $0.code.hasPrefix(filter.lowercased()) || $0.word.contains(filter) }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    TextField("编码", text: $code, prompt: Text("编码"))
                        .font(.body.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 84)
                        .onChange(of: code) {
                            code = String($0.lowercased().prefix(Session.maxCodeLength))
                            complaint = nil
                        }
                    TextField("词", text: $word, prompt: Text("词"))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: word) { _ in complaint = nil }
                        .onSubmit(add)
                    Button("添加", action: add)
                }
                .labelsHidden()
                Text(complaint ?? "自造词排在同一编码的内置词之前。打字时遇到空码，也可以按 = 直接造词。")
                    .font(.callout)
                    .foregroundStyle(complaint == nil ? Color.secondary : Color.red)
            } header: {
                Text("添加")
            }

            Section("自造词　\(entries.count)") {
                if entries.count > 8 {
                    TextField("筛选", text: $filter, prompt: Text("按编码或词筛选")).labelsHidden()
                }
                if entries.isEmpty {
                    Text("还没有自造词").foregroundStyle(.secondary)
                } else if shown.isEmpty {
                    Text("没有符合的词").foregroundStyle(.secondary)
                }
                ForEach(shown) { entry in
                    HStack(spacing: 10) {
                        // Same column as the code field above, text inset like the field's.
                        Text(entry.code).font(.body.monospaced()).foregroundStyle(.secondary)
                            .padding(.leading, 6)
                            .frame(width: 84, alignment: .leading)
                        Text(entry.word).padding(.leading, 6)
                        Spacer()
                        Button {
                            Dictionary.removeUserWord(entry)
                            reload()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除 \(entry.word)")
                        .help("删除")
                    }
                }
            }

            Section {
                LabeledContent {
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([Dictionary.userWordsURL])
                    }
                    .disabled(entries.isEmpty)
                } label: {
                    Text("词库文件")
                    Text("纯文本，每行「编码 词」；直接改文件后需重启末笔")
                }
            }
        }
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in reload() }
    }

    private func reload() {
        entries = Dictionary.userWords()
    }

    private func add() {
        complaint = problem
        guard complaint == nil else { return }
        Dictionary.addUserWord(code: code, word: newWord)
        code = ""
        word = ""
        reload()
    }
}
