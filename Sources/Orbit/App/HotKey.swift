import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut via Carbon's `RegisterEventHotKey` (no Accessibility permission needed).
final class HotKey {
    static let signature: OSType = 0x4F52_4254 // "ORBT"

    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - modifiers: Carbon modifier flags, e.g. `cmdKey | shiftKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard installStatus == noErr, registerStatus == noErr else { return nil }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// Detects whether macOS still owns ⌘⇧5 ("Screenshot and recording options"), which would
/// swallow the shortcut before Orbit sees it.
enum SystemShortcut {
    private static let screenshotOptionsHotKeyID = "184"

    static var macOSOwnsCommandShift5: Bool {
        guard
            let hotKeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any],
            let entry = hotKeys[screenshotOptionsHotKeyID] as? [String: Any]
        else {
            return true // never customized → enabled by default
        }
        return (entry["enabled"] as? Bool) ?? true
    }
}
