import Cocoa
import Carbon

/// Mobi registers one input mode under the input method, as the system asks of an input
/// method before it offers "Use Caps Lock to switch to and from ABC". Versions up to 0.1.2
/// had no mode, so a Mac that had them enabled has only the input method itself enabled,
/// which can no longer be selected. This turns the mode on for such a Mac, and asks the user
/// to add Mobi again in System Settings, as only that keeps the mode on after a restart.
enum InputSources {
    static func migrate() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let modes = Bundle.main.infoDictionary?["ComponentInputModeDict"] as? [String: Any],
              let modeID = (modes["tsVisibleInputModeOrderedArrayKey"] as? [String])?.first else { return }
        // Only when the system has yet to learn of the mode: registering again while Mobi is in
        // use can leave the input menu in the menu bar empty until Mobi is removed and added back.
        if source(modeID, enabledOnly: false) == nil {
            TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        }
        if savedWithoutMode(bundleID: bundleID, modeID: modeID) { askToAddAgain() }
        // A Mac that never had Mobi enabled, or turned it off, is left alone.
        guard source(bundleID, enabledOnly: true) != nil, source(modeID, enabledOnly: true) == nil else { return }
        guard let mode = source(modeID, enabledOnly: false) else {
            NSLog("Mobi: input mode %@ not found", modeID)
            return
        }
        let enabled = TISEnableInputSource(mode)
        NSLog("Mobi: enabled input mode %@ (%d)", modeID, enabled)
        if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), id(current) == bundleID {
            TISSelectInputSource(mode)
        }
    }

    /// Whether the saved list of input sources, the one the next login brings back, has Mobi
    /// without its mode. TISEnableInputSource lasts only until then, and only System Settings
    /// can write that list.
    private static func savedWithoutMode(bundleID: String, modeID: String) -> Bool {
        let lists = [("com.apple.inputsources", "AppleEnabledThirdPartyInputSources"),
                     ("com.apple.HIToolbox", "AppleEnabledInputSources")]
        let saved = lists.flatMap { domain, key in
            CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? [[String: Any]] ?? []
        }
        return saved.contains { $0["Bundle ID"] as? String == bundleID }
            && !saved.contains { $0["Input Mode"] as? String == modeID }
    }

    private static func askToAddAgain() {
        // Once the app is running, so the alert can come to the front.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "请在系统设置里重新添加一次末笔"
            alert.informativeText = "这一版末笔要在输入法列表里重新添加一次，不然重启以后，它会从输入法菜单里消失。\n\n在 键盘 → 文字输入 → 输入法 → 编辑… 里选中「末笔」点 －，再点 ＋ → 简体中文 → 末笔 加回来。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            guard alert.runModal() == .alertFirstButtonReturn,
                  let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    /// The enabled flag of a mode says nothing about whether the user has it turned on;
    /// only the list of enabled sources does.
    private static func source(_ id: String, enabledOnly: Bool) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let list = TISCreateInputSourceList(filter, !enabledOnly)?.takeRetainedValue() as? [TISInputSource]
        return list?.first
    }

    private static func id(_ source: TISInputSource) -> String? {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
}
