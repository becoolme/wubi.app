import Cocoa
import Sparkle

/// Updates come through Sparkle from the appcast on wubi.app (SUFeedURL in Info.plist).
/// Mobi lives in the user's own input methods folder, so a new version goes in without a
/// password: it is fetched in the background and put in place once nobody is typing.
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    private var lastKey = Date()
    private var pending: (() -> Void)?
    private var pendingItem: SUAppcastItem?
    /// What to tell the user the first time they type after Mobi came back as a new version.
    private var notice: String?
    private var timer: Timer?
    /// The version downloaded and waiting to go in, for the menu and settings to offer.
    @Published private(set) var ready: String?

    /// How long the keyboard has to be quiet before Mobi restarts into a new version.
    private static let quiet: TimeInterval = 120
    private static let day: TimeInterval = 24 * 60 * 60

    enum Mode { case automatic, notify, off }

    /// Automatic: a new version is looked for daily and goes in without a word.
    /// Notify: it is looked for weekly and only offered, so the update window comes up at most
    /// once a week. Off: nothing is looked for until 检查更新… is chosen.
    @Published var mode = Mode.automatic {
        didSet { apply() }
    }

    func start() {
        let defaults = UserDefaults.standard
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let last = defaults.string(forKey: "LastBuild"), last != build {
            notice = "已更新到 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")"
        }
        defaults.set(build, forKey: "LastBuild")
        controller.startUpdater()
        let updater = controller.updater
        mode = !updater.automaticallyChecksForUpdates ? .off
            : updater.automaticallyDownloadsUpdates ? .automatic : .notify
    }

    private func apply() {
        let updater = controller.updater
        updater.automaticallyChecksForUpdates = mode != .off
        updater.automaticallyDownloadsUpdates = mode == .automatic
        updater.updateCheckInterval = mode == .automatic ? Self.day : 7 * Self.day
    }

    func check() {
        NSApp.activate(ignoringOtherApps: true)
        // With a new version already downloaded Sparkle starts no other check, so it is offered here.
        if pending != nil, let item = pendingItem {
            offer(item)
            return
        }
        controller.checkForUpdates(nil)
    }

    /// Hands over the line to show once Mobi has come back as a new version, then forgets it.
    func takeNotice() -> String? {
        defer { notice = nil }
        return notice
    }

    private func offer(_ item: SUAppcastItem) {
        let alert = NSAlert()
        alert.messageText = "末笔 \(item.displayVersionString) 已经下载好"
        alert.informativeText = Self.plainText(item.itemDescription) ?? ""
        alert.addButton(withTitle: "现在更新")
        alert.addButton(withTitle: "稍后")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        installNow()
    }

    /// Puts the downloaded version in place and restarts Mobi into it.
    func installNow() {
        guard let install = pending else { return }
        pending = nil
        ready = nil
        timer?.invalidate()
        install()
    }

    /// The release notes are a short HTML list; the alert wants lines.
    private static func plainText(_ html: String?) -> String? {
        guard let html else { return nil }
        let items = html.components(separatedBy: "<li>").dropFirst().map {
            "· " + $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&amp;", with: "&")
        }
        return items.joined(separator: "\n")
    }

    /// Called for every key Mobi sees, so an update never lands in the middle of typing.
    func noteKey() {
        lastKey = Date()
    }

    var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "")（\(info?["CFBundleVersion"] ?? "")）"
    }

    // MARK: SPUUpdaterDelegate

    /// An input method is seldom quit, so a downloaded update would wait for the next logout.
    /// It goes in as soon as the keyboard has been quiet for a while instead.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock: @escaping () -> Void) -> Bool {
        pending = immediateInstallationBlock
        pendingItem = item
        ready = item.displayVersionString
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.installIfQuiet()
        }
        return true
    }

    private func installIfQuiet() {
        guard pending != nil, Date().timeIntervalSince(lastKey) > Self.quiet else { return }
        NSLog("Mobi: installing the downloaded update")
        installNow()
    }

    // MARK: SPUStandardUserDriverDelegate

    /// A check Mobi starts by itself should not take the keys away from whatever is being
    /// typed: if it has to show something, its window waits behind the others.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }
}
