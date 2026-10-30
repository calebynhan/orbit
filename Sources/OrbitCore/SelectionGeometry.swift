import CoreGraphics

/// The part of a selection rectangle being dragged. Uses AppKit's y-up space: "top" is `maxY`.
public enum SelectionHandle: Equatable, Sendable, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, body

    var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
    var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
}

/// Math for the "Record Selected Portion" rectangle. All rects are in global AppKit points
/// (bottom-left origin) unless noted. Results are snapped to whole points so the capture
/// crop lands exactly on the pixel grid.
public enum SelectionGeometry {
    public static let minimumSize = CGSize(width: 64, height: 64)
    public static let handleTolerance: CGFloat = 8
    private static let defaultFraction: CGFloat = 0.6

    /// ScreenCaptureKit's `sourceRect`: display-local points with a top-left origin.
    public static func sourceRect(selection: CGRect, display: CGRect) -> CGRect {
        CGRect(
            x: selection.minX - display.minX,
            y: display.maxY - selection.maxY,
            width: selection.width,
            height: selection.height
        )
    }

    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    public static func defaultSelection(in bounds: CGRect) -> CGRect {
        let size = CGSize(width: bounds.width * defaultFraction, height: bounds.height * defaultFraction)
        return snapped(CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
    }

    /// Fits `rect` inside `bounds` (shrinking if needed) and enforces the minimum size.
    public static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let width = min(max(rect.width, minimumSize.width), bounds.width)
        let height = min(max(rect.height, minimumSize.height), bounds.height)
        return CGRect(
            x: min(max(rect.minX, bounds.minX), bounds.maxX - width),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }

    /// The rect after dragging `handle` by `delta`, kept inside `bounds`.
    public static func resized(
        _ rect: CGRect,
        handle: SelectionHandle,
        by delta: CGSize,
        bounds: CGRect,
        aspect: SelectionAspect = .freeform
    ) -> CGRect {
        if handle == .body {
            return constrained(rect.offsetBy(dx: delta.width, dy: delta.height), aspect: aspect, anchor: .body, bounds: bounds)
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesLeft { minX = max(min(minX + delta.width, maxX - minimumSize.width), bounds.minX) }
        if handle.movesRight { maxX = min(max(maxX + delta.width, minX + minimumSize.width), bounds.maxX) }
        if handle.movesBottom { minY = max(min(minY + delta.height, maxY - minimumSize.height), bounds.minY) }
        if handle.movesTop { maxY = min(max(maxY + delta.height, minY + minimumSize.height), bounds.maxY) }
        let free = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return constrained(free, aspect: aspect, anchor: handle, bounds: bounds)
    }

    /// Applies the aspect lock (keeping the edge/corner opposite `anchor` fixed), snaps to
    /// whole points, and keeps the rect inside `bounds`.
    public static func constrained(_ rect: CGRect, aspect: SelectionAspect, anchor: SelectionHandle, bounds: CGRect) -> CGRect {
        guard let units = aspect.units else { return clamped(snapped(rect), to: bounds) }

        // Size in whole "units" (16×9 points each) so the ratio is exact.
        let heightDriven = anchor == .top || anchor == .bottom
        let requested = (heightDriven ? rect.height / units.height : rect.width / units.width).rounded(.down)
        let fewest = max(minimumSize.width / units.width, minimumSize.height / units.height).rounded(.up)
        let most = min(bounds.width / units.width, bounds.height / units.height).rounded(.down)
        let count = min(max(requested, fewest), most)
        let size = CGSize(width: count * units.width, height: count * units.height)

        let x: CGFloat
        if anchor.movesLeft { x = rect.maxX - size.width } else if anchor.movesRight { x = rect.minX } else { x = rect.midX - size.width / 2 }
        let y: CGFloat
        if anchor.movesBottom { y = rect.maxY - size.height } else if anchor.movesTop { y = rect.minY } else { y = rect.midY - size.height / 2 }

        let placed = CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
        return CGRect(
            x: min(max(placed.minX, bounds.minX), bounds.maxX - size.width),
            y: min(max(placed.minY, bounds.minY), bounds.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// Which handle (if any) is under `point`. Corners win over edges; edges extend a few points outside.
    public static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat = handleTolerance) -> SelectionHandle? {
        guard rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return nil }
        let left = abs(point.x - rect.minX) <= tolerance
        let right = abs(point.x - rect.maxX) <= tolerance
        let bottom = abs(point.y - rect.minY) <= tolerance
        let top = abs(point.y - rect.maxY) <= tolerance
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return .body
        }
    }

    private static func snapped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
    }
}
