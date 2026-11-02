import AppKit

/// Takes over the Touch Bar while recording with a red Stop button and the elapsed time,
/// like macOS's own screen recording. A no-op on Macs without a Touch Bar.
@MainActor
final class StopTouchBarController: NSObject, NSTouchBarDelegate {
    private static let stopItem = NSTouchBarItem.Identifier("dev.orbit.Orbit.stop")

    private let touchBar = NSTouchBar()
    private let button: NSButton
    private let startedAt: Date
    private let onStop: () -> Void
    private var clock: Timer?

    init(startedAt: Date, onStop: @escaping () -> Void) {
        self.startedAt = startedAt
        self.onStop = onStop
        let image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop") ?? NSImage()
        button = NSButton(title: Self.title(elapsed: 0), image: image, target: nil, action: nil)
        super.init()
        button.target = self
        button.action = #selector(stop)
        button.bezelColor = .systemRed
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [.flexibleSpace, Self.stopItem, .flexibleSpace]
    }

    // System-modal presentation isn't in the public headers (macOS's own screen recording uses it),
    // so it goes through the runtime; on a Mac without a Touch Bar it simply does nothing.
    private static let present = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    private static let dismiss = NSSelectorFromString("dismissSystemModalTouchBar:")

    func show() {
        if NSTouchBar.responds(to: Self.present) {
            _ = NSTouchBar.perform(Self.present, with: touchBar, with: nil)
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.button.title = Self.title(elapsed: Date().timeIntervalSince(self.startedAt))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
    }

    func close() {
        clock?.invalidate()
        clock = nil
        if NSTouchBar.responds(to: Self.dismiss) {
            _ = NSTouchBar.perform(Self.dismiss, with: touchBar)
        }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.stopItem else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = button
        item.customizationLabel = "Stop Recording"
        return item
    }

    @objc private func stop() { onStop() }

    private static func title(elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        let time = total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
        return "Stop  \(time)"
    }
}
