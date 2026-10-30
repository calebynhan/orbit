import Foundation
import OrbitCore

/// Persists the user's chosen global shortcut and first-run state.
enum ShortcutStore {
    private static let shortcutKey = "globalShortcut"
    static let onboardedKey = "onboardingCompleted"

    static var shortcut: KeyboardShortcut {
        get {
            guard
                let data = UserDefaults.standard.data(forKey: shortcutKey),
                let stored = try? JSONDecoder().decode(KeyboardShortcut.self, from: data)
            else { return .default }
            return stored
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: shortcutKey)
            }
        }
    }

    static var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: onboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardedKey) }
    }
}
