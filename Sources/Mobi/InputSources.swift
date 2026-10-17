import Carbon
import Foundation

/// Mobi registers one input mode under the input method, as the system asks of an input
/// method before it offers "Use Caps Lock to switch to and from ABC". Versions up to 0.1.2
/// had no mode, so a Mac that had them enabled has only the input method itself enabled,
/// which can no longer be selected. This turns the mode on for such a Mac.
enum InputSources {
    static func migrate() {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let modes = Bundle.main.infoDictionary?["ComponentInputModeDict"] as? [String: Any],
              let modeID = (modes["tsVisibleInputModeOrderedArrayKey"] as? [String])?.first else { return }
        TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
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
