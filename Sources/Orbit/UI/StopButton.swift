import AppKit
import SwiftUI

/// A floating stop control shown while recording, for Macs whose menu bar hides the status item
/// (the notch). Orbit's own windows are excluded from the capture, so it never appears in the video.
@MainActor
final class StopButtonController {
    private let panel: StopPanel

    init(on screen: NSScreen, startedAt: Date, onStop: @escaping () -> Void) {
        let hosting = NSHostingView(rootView: StopButtonView(startedAt: startedAt, onStop: onStop))
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.minY + 24, width: size.width, height: size.height)
        panel = StopPanel(frame: frame)
        panel.contentView = hosting
    }

    func show() { panel.orderFrontRegardless() }

    func close() { panel.close() }
}

private final class StopPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool { false }
}

private struct StopButtonView: View {
    let startedAt: Date
    let onStop: () -> Void
    @State private var elapsed: TimeInterval = 0
    @State private var isHovering = false

    private let clock = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Button(action: onStop) {
            HStack(spacing: 8) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.red)
                Text(Self.format(elapsed))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                Text("Stop")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(isHovering ? 1 : 0.7)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(isHovering ? 0.35 : 0.15)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Stop recording")
        .padding(6)
        .onReceive(clock) { now in elapsed = now.timeIntervalSince(startedAt) }
        .environment(\.colorScheme, .dark)
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
