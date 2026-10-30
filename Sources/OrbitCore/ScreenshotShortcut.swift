/// Reads and edits macOS's "Screenshot and recording options" shortcut (⌘⇧5) inside the
/// `AppleSymbolicHotKeys` dictionary of the `com.apple.symbolichotkeys` preferences domain.
/// Pure functions on the dictionary; the app does the actual preference I/O.
public enum ScreenshotShortcut {
    /// Symbolic hot key ID macOS uses for the ⌘⇧5 screenshot toolbar.
    public static let hotKeyID = "184"

    /// macOS's stock binding: character "5", virtual key 23 (kVK_ANSI_5), ⌘⇧ modifier mask.
    static let defaultValue: [String: Any] = [
        "parameters": [53, 23, 1_179_648],
        "type": "standard",
    ]

    /// Whether macOS currently owns ⌘⇧5. A missing entry means the shortcut was never customized, so it's on.
    public static func isEnabled(in hotKeys: [String: Any]?) -> Bool {
        guard let entry = hotKeys?[hotKeyID] as? [String: Any] else { return true }
        if let flag = entry["enabled"] as? Bool { return flag }
        if let number = entry["enabled"] as? Int { return number != 0 }
        return true
    }

    /// A copy of `hotKeys` with the screenshot-toolbar shortcut switched on or off. Everything else is untouched.
    public static func setting(enabled: Bool, in hotKeys: [String: Any]) -> [String: Any] {
        let existing = hotKeys[hotKeyID] as? [String: Any] ?? [:]
        let entry = existing.merging(["enabled": enabled, "value": existing["value"] ?? defaultValue]) { _, new in new }
        return hotKeys.merging([hotKeyID: entry]) { _, new in new }
    }
}
