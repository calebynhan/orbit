/// A global shortcut the user picks to open Orbit. AppKit-free so it can be tested and stored.
public struct KeyboardShortcut: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public enum ValidationProblem: Equatable, Sendable {
        case needsModifier
        case unknownKey

        public var message: String {
            switch self {
            case .needsModifier: "Add ⌘, ⌃, or ⌥ so the shortcut doesn’t type a character."
            case .unknownKey: "That key can’t be used for a shortcut."
            }
        }
    }

    /// macOS virtual key code (`kVK_*`).
    public let keyCode: Int
    public let modifiers: Modifiers

    public init(keyCode: Int, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌘⇧5, matching the macOS screenshot toolbar.
    public static let `default` = KeyboardShortcut(keyCode: 23, modifiers: [.command, .shift])

    public var isMacOSScreenshotShortcut: Bool { self == .default }

    public var validationProblem: ValidationProblem? {
        guard Self.keyNames[keyCode] != nil else { return .unknownKey }
        let isFunctionKey = Self.functionKeys.contains(keyCode)
        let hasRealModifier = !modifiers.intersection([.command, .control, .option]).isEmpty
        return isFunctionKey || hasRealModifier ? nil : .needsModifier
    }

    /// Modifier symbols in the order macOS shows them, then the key.
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "?")
    }

    /// Carbon `RegisterEventHotKey` flags: cmdKey 256, shiftKey 512, optionKey 2048, controlKey 4096.
    public var carbonModifiers: Int {
        (modifiers.contains(.command) ? 256 : 0)
            + (modifiers.contains(.shift) ? 512 : 0)
            + (modifiers.contains(.option) ? 2048 : 0)
            + (modifiers.contains(.control) ? 4096 : 0)
    }

    private static let functionKeys: Set<Int> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    static let keyNames: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W",
        14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}
