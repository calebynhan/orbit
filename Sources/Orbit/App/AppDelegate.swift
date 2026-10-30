import AppKit
import Carbon.HIToolbox
import OrbitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let coordinator = RecordingCoordinator()
    private var statusMenu: StatusMenu?
    private var hotKey: HotKey?
    private var editors: [EditorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()

        let statusMenu = StatusMenu(
            coordinator: coordinator,
            openRecording: { [weak self] in self?.chooseRecording() },
            setOrbitOwnsShortcut: { [weak self] owns in owns ? self?.takeOverShortcut() : self?.giveShortcutBack() }
        )
        self.statusMenu = statusMenu
        coordinator.onPhaseChange = { [weak statusMenu] phase in statusMenu?.update(for: phase) }
        coordinator.onFinished = { [weak self] folder in self?.openEditor(for: folder) }

        registerHotKey()
        if hotKey == nil {
            Alerts.show(title: "Shortcut unavailable", message: "Couldn’t register ⌘⇧5. Use the Orbit menu bar icon to start recording.")
        }
        offerShortcutTakeoverOnce()
    }

    private func registerHotKey() {
        guard hotKey == nil else { return }
        hotKey = HotKey(keyCode: kVK_ANSI_5, modifiers: cmdKey | shiftKey) { [weak self] in
            MainActor.assumeIsolated { self?.coordinator.handleHotKey() }
        }
    }

    // MARK: ⌘⇧5 ownership

    private static let askedTakeoverKey = "askedShortcutTakeover"

    /// First launch while macOS still owns ⌘⇧5: offer to switch it over. Asked once; the menu offers it after that.
    private func offerShortcutTakeoverOnce() {
        guard SystemShortcut.macOSOwnsCommandShift5, !UserDefaults.standard.bool(forKey: Self.askedTakeoverKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.askedTakeoverKey)
        takeOverShortcut()
    }

    private func takeOverShortcut() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Make ⌘⇧5 open Orbit?"
        alert.informativeText = "Right now ⌘⇧5 opens macOS’s screenshot toolbar. Orbit can turn off that macOS shortcut "
            + "so ⌘⇧5 opens Orbit instead. ⌘⇧3 and ⌘⇧4 screenshots keep working.\n\n"
            + "You can give ⌘⇧5 back to macOS from the Orbit menu at any time."
        alert.addButton(withTitle: "Use ⌘⇧5 for Orbit")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setMacOSShortcut(enabled: false)
    }

    private func giveShortcutBack() {
        setMacOSShortcut(enabled: true)
    }

    private func setMacOSShortcut(enabled: Bool) {
        do {
            try SystemShortcut.setMacOSShortcut(enabled: enabled)
            registerHotKey()
        } catch {
            Alerts.show(error, settingsPane: .keyboardShortcuts)
        }
        statusMenu?.refresh()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Editors

    private func chooseRecording() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = RecordingCoordinator.recordingsRoot
        panel.prompt = "Open Recording"
        NSApp.activate()
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        openEditor(for: folder)
    }

    private func openEditor(for folder: URL) {
        do {
            let project = try RecordingProject.load(from: folder)
            let editor = EditorWindowController(folder: folder, project: project)
            editor.window?.delegate = self
            editors.append(editor)
            NSApp.setActivationPolicy(.regular)
            editor.showWindow(nil)
            NSApp.activate()
        } catch {
            Alerts.show(error)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        editors.filter { $0.window === window }.forEach { $0.tearDown() }
        editors = editors.filter { $0.window !== window }
        if editors.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Hide Orbit", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Orbit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)
        return main
    }
}
