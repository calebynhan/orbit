import AppKit
import OrbitCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let coordinator = RecordingCoordinator()
    private var statusMenu: StatusMenu?
    private var hotKey: HotKey?
    private var editors: [EditorWindowController] = []
    private var welcome: WelcomeWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()

        let statusMenu = StatusMenu(
            coordinator: coordinator,
            openRecording: { [weak self] in self?.chooseRecording() },
            showWelcome: { [weak self] in self?.showWelcome() },
            setOrbitOwnsShortcut: { [weak self] owns in owns ? self?.takeOverShortcut() : self?.giveShortcutBack() }
        )
        self.statusMenu = statusMenu
        coordinator.onPhaseChange = { [weak statusMenu] phase in statusMenu?.update(for: phase) }
        coordinator.onFinished = { [weak self] folder in self?.openEditor(for: folder) }

        registerHotKey(ShortcutStore.shortcut)
        if !ShortcutStore.hasOnboarded { showWelcome() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Shortcut

    private func registerHotKey(_ shortcut: KeyboardShortcut) {
        hotKey = nil // unregisters the old one
        hotKey = HotKey(keyCode: shortcut.keyCode, modifiers: shortcut.carbonModifiers) { [weak self] in
            MainActor.assumeIsolated { self?.coordinator.handleHotKey() }
        }
        if hotKey == nil {
            Alerts.show(title: "Shortcut unavailable", message: "Couldn’t register \(shortcut.displayString). Another app may be using it. Pick a different one from the Orbit menu.")
        }
        statusMenu?.refresh()
    }

    private func applyShortcut(_ shortcut: KeyboardShortcut) {
        ShortcutStore.shortcut = shortcut
        registerHotKey(shortcut)
    }

    // MARK: Welcome guide

    private func showWelcome() {
        if welcome == nil {
            let model = WelcomeModel(
                shortcut: ShortcutStore.shortcut,
                onFinish: { [weak self] shortcut in
                    ShortcutStore.hasOnboarded = true
                    self?.applyShortcut(shortcut)
                    self?.welcome?.close()
                    self?.welcome = nil
                },
                takeOverSystemShortcut: { [weak self] in self?.setMacOSShortcut(enabled: false) }
            )
            let controller = WelcomeWindowController(model: model)
            controller.window?.delegate = self
            welcome = controller
        }
        NSApp.setActivationPolicy(.regular)
        welcome?.showWindow(nil)
        NSApp.activate()
    }

    // MARK: ⌘⇧5 ownership

    private func takeOverShortcut() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Make ⇧⌘5 open Orbit?"
        alert.informativeText = "Right now ⇧⌘5 opens macOS’s screenshot toolbar. Orbit can turn off that macOS shortcut "
            + "so ⇧⌘5 opens Orbit instead. ⇧⌘3 and ⇧⌘4 screenshots keep working.\n\n"
            + "You can give ⇧⌘5 back to macOS from the Orbit menu at any time."
        alert.addButton(withTitle: "Use ⇧⌘5 for Orbit")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let error = setMacOSShortcut(enabled: false) {
            Alerts.show(title: "Orbit", message: error, settingsPane: .keyboardShortcuts)
        } else {
            applyShortcut(.default)
        }
    }

    private func giveShortcutBack() {
        if let error = setMacOSShortcut(enabled: true) {
            Alerts.show(title: "Orbit", message: error, settingsPane: .keyboardShortcuts)
        }
    }

    /// Returns an error message on failure.
    @discardableResult
    private func setMacOSShortcut(enabled: Bool) -> String? {
        do {
            try SystemShortcut.setMacOSShortcut(enabled: enabled)
            statusMenu?.refresh()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

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
        if window === welcome?.window {
            ShortcutStore.hasOnboarded = true // closing the guide counts as done; it's in the menu if they want it back
            welcome = nil
        }
        editors.filter { $0.window === window }.forEach { $0.tearDown() }
        editors = editors.filter { $0.window !== window }
        if editors.isEmpty, welcome == nil { NSApp.setActivationPolicy(.accessory) }
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
