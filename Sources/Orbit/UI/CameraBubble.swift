import AppKit
import AVFoundation
import OrbitCore

/// A floating, draggable window showing the live camera in the chosen shape.
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

    func show() { panel.orderFrontRegardless() }

    func close() { panel.close() }

    /// Brings the bubble into `area` if it's currently outside it (keeps your placement otherwise).
    func keep(inside area: CGRect) {
        guard !area.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return }
        let diameter = min(frame.width, area.width * 0.5, area.height * 0.5)
        panel.setFrame(Self.cornerFrame(in: area, diameter: max(diameter, Self.minDiameter)), display: true)
    }

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

    private static func cornerFrame(in area: CGRect, diameter: CGFloat) -> CGRect {
        let margin = min(40, area.width * 0.05, area.height * 0.05)
        return CGRect(x: area.minX + margin, y: area.minY + margin, width: diameter, height: diameter)
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
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var dragOffset: CGPoint?
    private var style = BubbleStyleStore.style { didSet { BubbleStyleStore.style = style; applyStyle() } }

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.videoGravity = .resizeAspectFill
        layer?.insertSublayer(previewLayer, at: 0)
        menu = makeMenu()
        toolTip = "Drag to move · scroll or pinch to resize · right-click for size, shape, and outline"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        applyStyle()
        previewLayer.frame = bounds
        // The connection only exists once the session has inputs, so apply this lazily.
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported, !connection.isVideoMirrored {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true // matches the editor's default "Mirror" setting
        }
    }

    private func applyStyle() {
        let side = bounds.width
        layer?.cornerRadius = side * style.shape.cornerRadiusFraction
        layer?.borderWidth = side * style.outlineWidth
        layer?.borderColor = style.outlineColor.nsColor.cgColor
        window?.invalidateShadow()
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

    // MARK: Right-click menu

    private static let sizes: [(String, CGFloat)] = [("Small", 140), ("Medium", 200), ("Large", 300), ("Extra Large", 440)]
    private static let outlines: [(String, Double)] = [("None", 0), ("Thin", 0.015), ("Medium", 0.035), ("Thick", 0.06)]
    private static let colors: [(String, RGBAColor)] = [
        ("White", .white), ("Black", .black),
        ("Red", RGBAColor(red: 0.9, green: 0.28, blue: 0.3)), ("Blue", RGBAColor(red: 0.31, green: 0.49, blue: 1)),
        ("Green", RGBAColor(red: 0.33, green: 0.8, blue: 0.5)), ("Yellow", RGBAColor(red: 1, green: 0.84, blue: 0.3)),
    ]

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(submenu("Size", items: Self.sizes.map(\.0), action: #selector(pickSize(_:))))
        menu.addItem(submenu("Shape", items: BubbleShape.allCases.map(\.label), action: #selector(pickShape(_:))))
        menu.addItem(submenu("Outline", items: Self.outlines.map(\.0), action: #selector(pickOutline(_:))))
        menu.addItem(submenu("Outline Color", items: Self.colors.map(\.0), action: #selector(pickColor(_:))))
        return menu
    }

    private func submenu(_ title: String, items: [String], action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu(title: title)
        for (index, name) in items.enumerated() {
            let entry = NSMenuItem(title: name, action: action, keyEquivalent: "")
            entry.target = self
            entry.tag = index
            sub.addItem(entry)
        }
        item.submenu = sub
        return item
    }

    @objc private func pickSize(_ sender: NSMenuItem) { (window as? BubblePanel)?.resize(to: Self.sizes[sender.tag].1) }
    @objc private func pickShape(_ sender: NSMenuItem) { style = style.with(shape: BubbleShape.allCases[sender.tag]) }
    @objc private func pickOutline(_ sender: NSMenuItem) { style = style.with(outlineWidth: Self.outlines[sender.tag].1) }
    @objc private func pickColor(_ sender: NSMenuItem) { style = style.with(outlineColor: Self.colors[sender.tag].1) }
}

extension BubbleView: NSMenuDelegate {
    /// Tick the current choice in each submenu.
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            guard let sub = item.submenu else { continue }
            for entry in sub.items {
                let on: Bool = switch item.title {
                case "Shape": BubbleShape.allCases[entry.tag] == style.shape
                case "Outline": abs(Self.outlines[entry.tag].1 - style.outlineWidth) < 0.001
                case "Outline Color": Self.colors[entry.tag].1 == style.outlineColor
                default: false
                }
                entry.state = on ? .on : .off
            }
        }
    }
}
