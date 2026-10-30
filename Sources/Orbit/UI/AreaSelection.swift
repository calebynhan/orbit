import AppKit
import OrbitCore

/// Full-display overlay for "Record Selected Portion": dims everything outside a frame you
/// can draw, move, and resize. While recording it becomes a click-through outline.
/// Orbit's windows are excluded from capture, so none of this shows up in the video.
@MainActor
final class AreaSelectionController {
    private let panel: NSPanel
    private let overlay: SelectionOverlayView
    let displayFrame: CGRect

    /// - Parameters:
    ///   - selection: global AppKit rect.
    ///   - sizeLabel: text shown under the frame, e.g. the output pixel size.
    init(
        displayFrame: CGRect,
        selection: CGRect,
        aspect: SelectionAspect,
        sizeLabel: @escaping (CGSize) -> String,
        onChange: @escaping (CGRect) -> Void
    ) {
        self.displayFrame = displayFrame
        overlay = SelectionOverlayView(
            selection: selection.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY),
            aspect: aspect,
            sizeLabel: sizeLabel,
            onChange: { local in onChange(local.offsetBy(dx: displayFrame.minX, dy: displayFrame.minY)) }
        )
        panel = NSPanel(contentRect: displayFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1) // below toolbar & bubble
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = overlay
        panel.setFrame(displayFrame, display: false)
    }

    func show() { panel.orderFrontRegardless() }

    func close() { panel.close() }

    func update(selection: CGRect, aspect: SelectionAspect) {
        overlay.aspect = aspect
        overlay.selection = selection.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    func refreshLabel() { overlay.needsDisplay = true }

    /// Switches to a thin outline that ignores the mouse, so you can work inside the area.
    func showRecordingOutline() {
        overlay.isRecording = true
        panel.ignoresMouseEvents = true
    }
}

private final class SelectionOverlayView: NSView {
    private static let dimColor = NSColor.black.withAlphaComponent(0.35)
    private static let handleRadius: CGFloat = 4.5

    var selection: CGRect { didSet { needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var aspect: SelectionAspect
    var isRecording = false { didSet { needsDisplay = true } }

    private let sizeLabel: (CGSize) -> String
    private let onChange: (CGRect) -> Void
    private var drag: (handle: SelectionHandle?, start: CGPoint, original: CGRect)?

    init(selection: CGRect, aspect: SelectionAspect, sizeLabel: @escaping (CGSize) -> String, onChange: @escaping (CGRect) -> Void) {
        self.selection = selection
        self.aspect = aspect
        self.sizeLabel = sizeLabel
        self.onChange = onChange
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if isRecording {
            drawRecordingOutline()
            return
        }
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: selection))
        dim.windingRule = .evenOdd
        Self.dimColor.setFill()
        dim.fill()

        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.white.setStroke()
        border.stroke()

        for point in handlePoints(of: selection) {
            let dot = NSBezierPath(ovalIn: CGRect(x: point.x - Self.handleRadius, y: point.y - Self.handleRadius, width: Self.handleRadius * 2, height: Self.handleRadius * 2))
            NSColor.white.setFill()
            dot.fill()
            NSColor.black.withAlphaComponent(0.4).setStroke()
            dot.lineWidth = 0.5
            dot.stroke()
        }
        drawSizeLabel()
    }

    private func drawRecordingOutline() {
        // Drawn just outside the capture area so it never bleeds into the video edge.
        let outline = NSBezierPath(rect: selection.insetBy(dx: -2, dy: -2))
        outline.lineWidth = 2
        outline.setLineDash([6, 4], count: 2, phase: 0)
        NSColor.systemRed.withAlphaComponent(0.85).setStroke()
        outline.stroke()
    }

    private func drawSizeLabel() {
        let text = sizeLabel(selection.size) as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attributes)
        let padding = CGSize(width: 8, height: 4)
        var box = CGRect(
            x: selection.midX - size.width / 2 - padding.width,
            y: selection.minY - size.height - padding.height * 2 - 10,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )
        if box.minY < bounds.minY { box.origin.y = selection.minY + 10 } // no room below → inside
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height), withAttributes: attributes)
    }

    private func handlePoints(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY),
        ]
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        drag = (SelectionGeometry.handle(at: point, in: selection), point, selection)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let handle = drag.handle {
            let delta = CGSize(width: point.x - drag.start.x, height: point.y - drag.start.y)
            selection = SelectionGeometry.resized(drag.original, handle: handle, by: delta, bounds: bounds, aspect: aspect)
        } else {
            // Clicked outside the frame: draw a new one from the press point, like ⌘⇧5.
            let drawn = SelectionGeometry.rect(from: drag.start, to: point)
            selection = SelectionGeometry.constrained(drawn, aspect: aspect, anchor: Self.anchor(from: drag.start, to: point), bounds: bounds)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        onChange(selection)
    }

    /// The corner being pulled when drawing from `start` toward `end`.
    private static func anchor(from start: CGPoint, to end: CGPoint) -> SelectionHandle {
        switch (end.x >= start.x, end.y >= start.y) {
        case (true, true): .topRight
        case (true, false): .bottomRight
        case (false, true): .topLeft
        case (false, false): .bottomLeft
        }
    }

    override func resetCursorRects() {
        guard !isRecording else { return }
        addCursorRect(bounds, cursor: .crosshair)
        addCursorRect(selection.insetBy(dx: SelectionGeometry.handleTolerance, dy: SelectionGeometry.handleTolerance), cursor: .openHand)
        let t = SelectionGeometry.handleTolerance
        addCursorRect(CGRect(x: selection.minX - t, y: selection.minY + t, width: t * 2, height: selection.height - t * 2), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: selection.maxX - t, y: selection.minY + t, width: t * 2, height: selection.height - t * 2), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: selection.minX + t, y: selection.minY - t, width: selection.width - t * 2, height: t * 2), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: selection.minX + t, y: selection.maxY - t, width: selection.width - t * 2, height: t * 2), cursor: .resizeUpDown)
    }
}
