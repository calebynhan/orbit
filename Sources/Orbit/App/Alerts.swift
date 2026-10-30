import AppKit
import AVFoundation

enum SettingsPane {
    case screenRecording
    case keyboardShortcuts

    var url: URL? {
        switch self {
        case .screenRecording: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .keyboardShortcuts: URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        }
    }
}

@MainActor
enum Alerts {
    static func show(_ error: Error, settingsPane: SettingsPane? = nil) {
        show(title: "Orbit", message: error.localizedDescription, settingsPane: settingsPane)
    }

    static func show(title: String, message: String, settingsPane: SettingsPane? = nil) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        if settingsPane != nil { alert.addButton(withTitle: "Open System Settings") }
        if alert.runModal() == .alertSecondButtonReturn, let url = settingsPane?.url {
            NSWorkspace.shared.open(url)
        }
    }
}

enum AVCaptureAccess {
    static func microphone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}
