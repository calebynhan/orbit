import AppKit
import AVFoundation

/// A floating, circular, draggable window showing the live camera.
@MainActor
final class CameraBubbleController {
    nonisolated static let defaultDiameter: CGFloat = 200
    nonisolated static let minDiameter: CGFloat = 100
    nonisolated static let maxDiameter: CGFloat = 520

    private let panel: BubblePanel

    /// - Parameter area: global rect to start in (bottom-left corner), e.g. the screen or the selected portion.
    init(session: AVCaptureSession, within area: CGRect, diameter: CGFloat = CameraBubbleController.defaultDiameter) {
        panel = BubblePanel(frame: Self.cornerFrame(in: area, diameter: diameter), session: session)
    }

    /// Current frame in global AppKit screen coordinates.
    var frame: CGRect { panel.frame }

    /// Brings the bubble into `area` if it's currently outside it (keeps your placement otherwise).
    func keep(inside area: CGRect) {
        guard !area.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return }
        let diameter = min(frame.width, area.width * 0.5, area.height * 0.5)
        panel.setFrame(Self.cornerFrame(in: area, diameter: max(diameter, Self.minDiameter)), display: true)
    }

    private static func cornerFrame(in area: CGRect, diameter: CGFloat) -> CGRect {
        let margin = min(40, area.width * 0.05, area.height * 0.05)
        return CGRect(x: area.minX + margin, y: area.minY + margin, width: diameter, height: diameter)
    }

    func show() { panel.orderFrontRegardless() }

    func close() { panel.close() }

    /// Hides the bubble immediately, but keeps it (and its preview layer) alive until the camera
    /// has fully stopped. Releasing the preview layer while the session is stopping deadlocks
    /// AVFoundation (see `CameraCapture`).
    static func tearDown(_ bubble: CameraBubbleController?, camera: CameraCapture?) {
        bubble?.panel.orderOut(nil)
        Task { @MainActor in
            await camera?.stop()
            bubble?.close()
        }
    }
}

private final class BubblePanel: NSPanel {
    init(frame: CGRect, session: AVCaptureSession) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = BubbleView(session: session)
    }

    override var canBecomeKey: Bool { false }

    /// Resizes around the current center, clamped to sensible bounds.
    func resize(to diameter: CGFloat) {
        let size = min(max(diameter, CameraBubbleController.minDiameter), CameraBubbleController.maxDiameter)
        let center = CGPoint(x: frame.midX, y: frame.midY)
        setFrame(CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size), display: true)
        invalidateShadow()
    }
}

private final class BubbleView: NSView {
    private static let borderWidth: CGFloat = 4
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var dragOffset: CGPoint?

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.borderColor = NSColor.white.cgColor
        layer?.borderWidth = Self.borderWidth
        layer?.backgroundColor = NSColor.black.cgColor

        previewLayer.videoGravity = .resizeAspectFill
        layer?.insertSublayer(previewLayer, at: 0)
        menu = makeSizeMenu()
        toolTip = "Drag to move · scroll or pinch to resize · right-click for sizes"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.width / 2
        previewLayer.frame = bounds
        // The connection only exists once the session has inputs, so apply this lazily.
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported, !connection.isVideoMirrored {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true // matches the editor's default "Mirror" setting
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Manual dragging (instead of isMovableByWindowBackground) keeps `window.frame`
    // current on every event, so the recorder samples a smooth path.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        dragOffset = CGPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragOffset else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: mouse.x - dragOffset.x, y: mouse.y - dragOffset.y))
    }

    override func mouseUp(with event: NSEvent) { dragOffset = nil }

    override func scrollWheel(with event: NSEvent) {
        resize(by: event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 8))
    }

    override func magnify(with event: NSEvent) {
        resize(by: event.magnification * bounds.width)
    }

    private func resize(by delta: CGFloat) {
        (window as? BubblePanel)?.resize(to: bounds.width + delta)
    }

    private func makeSizeMenu() -> NSMenu {
        let menu = NSMenu()
        for (title, size) in [("Small", 140.0), ("Medium", 200.0), ("Large", 300.0), ("Extra Large", 440.0)] {
            let item = NSMenuItem(title: title, action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(size)
            menu.addItem(item)
        }
        return menu
    }

    @objc private func pickSize(_ sender: NSMenuItem) {
        (window as? BubblePanel)?.resize(to: CGFloat(sender.tag))
    }
}
