import AppKit

/// Menu bar item. Idle: a menu. Recording: a red stop button with elapsed time (like macOS's own).
@MainActor
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: RecordingCoordinator
    private let openRecording: () -> Void
    private let setOrbitOwnsShortcut: (Bool) -> Void
    private var clock: Timer?

    /// - Parameter setOrbitOwnsShortcut: `true` = take ⌘⇧5 from macOS, `false` = give it back.
    init(coordinator: RecordingCoordinator, openRecording: @escaping () -> Void, setOrbitOwnsShortcut: @escaping (Bool) -> Void) {
        self.coordinator = coordinator
        self.openRecording = openRecording
        self.setOrbitOwnsShortcut = setOrbitOwnsShortcut
        super.init()
        showIdle()
    }

    /// Rebuilds the idle menu, e.g. after the ⌘⇧5 owner changes.
    func refresh() {
        if !coordinator.isRecording, !coordinator.isBusy { showIdle() }
    }

    func update(for phase: RecordingCoordinator.Phase) {
        switch phase {
        case .idle, .choosing: showIdle()
        case .recording(let startedAt): showRecording(since: startedAt)
        case .finishing: showFinishing()
        }
    }

    private func showIdle() {
        stopClock()
        item.button?.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Orbit")
        item.button?.title = ""
        item.button?.contentTintColor = nil
        item.button?.action = nil
        item.menu = makeMenu()
    }

    private func showRecording(since start: Date) {
        item.menu = nil
        item.button?.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop recording")
        item.button?.contentTintColor = .systemRed
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(stop)
        stopClock()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.item.button?.title = " " + Self.format(Date().timeIntervalSince(start)) }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        item.button?.title = " 0:00"
    }

    private func showFinishing() {
        stopClock()
        item.menu = nil
        item.button?.action = nil
        item.button?.title = " Saving…"
        item.button?.contentTintColor = nil
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let record = NSMenuItem(title: "New Recording…", action: #selector(newRecording), keyEquivalent: "5")
        record.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(record)
        menu.addItem(NSMenuItem(title: "Open Recording…", action: #selector(open), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Show Recordings in Finder", action: #selector(revealRecordings), keyEquivalent: ""))

        menu.addItem(.separator())
        if SystemShortcut.macOSOwnsCommandShift5 {
            let takeOver = NSMenuItem(title: "⚠︎ ⌘⇧5 Opens macOS’s Toolbar — Use It for Orbit…", action: #selector(takeOverShortcut), keyEquivalent: "")
            takeOver.toolTip = "Turns off macOS’s “Screenshot and recording options” shortcut so ⌘⇧5 opens Orbit. ⌘⇧3 and ⌘⇧4 keep working."
            menu.addItem(takeOver)
        } else {
            let giveBack = NSMenuItem(title: "Give ⌘⇧5 Back to macOS", action: #selector(restoreShortcut), keyEquivalent: "")
            giveBack.toolTip = "Turns macOS’s screenshot toolbar shortcut back on."
            menu.addItem(giveBack)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Orbit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func newRecording() { coordinator.showToolbar() }
    @objc private func stop() { coordinator.stopRecording() }
    @objc private func open() { openRecording() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func revealRecordings() {
        let root = RecordingCoordinator.recordingsRoot
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        NSWorkspace.shared.open(root)
    }

    @objc private func takeOverShortcut() { setOrbitOwnsShortcut(true) }
    @objc private func restoreShortcut() { setOrbitOwnsShortcut(false) }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
