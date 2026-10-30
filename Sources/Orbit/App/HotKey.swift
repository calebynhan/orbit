import Carbon.HIToolbox
import Foundation
import OrbitCore
import os

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

/// macOS's own ⌘⇧5 ("Screenshot and recording options") is handled before any app sees the
/// keystroke. For ⌘⇧5 to open Orbit instead, that macOS shortcut has to be switched off — the
/// same checkbox as System Settings → Keyboard → Keyboard Shortcuts → Screenshots.
enum SystemShortcut {
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let key = "AppleSymbolicHotKeys" as CFString
    private static let applySettingsTool = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"
    private static let log = Logger(subsystem: "dev.orbit.Orbit", category: "Shortcut")

    enum ShortcutError: LocalizedError {
        case didNotApply

        var errorDescription: String? {
            "macOS didn’t accept the change. Turn it off yourself in System Settings → Keyboard → "
                + "Keyboard Shortcuts… → Screenshots → “Screenshot and recording options”."
        }
    }

    static var macOSOwnsCommandShift5: Bool {
        ScreenshotShortcut.isEnabled(in: readHotKeys())
    }

    /// Turns macOS's ⌘⇧5 on or off and applies it immediately (no logout needed).
    static func setMacOSShortcut(enabled: Bool) throws {
        let updated = ScreenshotShortcut.setting(enabled: enabled, in: readHotKeys() ?? [:])
        CFPreferencesSetAppValue(key, updated as CFDictionary, domain)
        guard CFPreferencesAppSynchronize(domain), macOSOwnsCommandShift5 == enabled else {
            throw ShortcutError.didNotApply
        }
        applyToRunningSession()
    }

    private static func readHotKeys() -> [String: Any]? {
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key, domain) as? [String: Any]
    }

    /// Asks the system to reload keyboard shortcuts now rather than at next login.
    private static func applyToRunningSession() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: applySettingsTool)
        process.arguments = ["-u"]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log.error("Couldn't reload shortcuts now; they apply after logging out: \(error.localizedDescription)")
        }
    }
}
