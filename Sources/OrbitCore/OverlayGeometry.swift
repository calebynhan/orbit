import CoreGraphics

/// Conversions between the coordinate spaces the bubble lives in:
/// - AppKit global screen points (bottom-left origin) while recording,
/// - normalized `BubbleState` (top-left origin) stored in the project,
/// - Core Image render pixels (bottom-left origin) when compositing,
/// - SwiftUI view points (top-left origin) in the editor preview.
public enum OverlayGeometry {
    public static let minDiameter = 0.06
    public static let maxDiameter = 0.8

    public static func bubbleState(windowFrame: CGRect, displayFrame: CGRect) -> BubbleState {
        guard displayFrame.width > 0, displayFrame.height > 0 else {
            return BubbleState(center: CGPoint(x: 0.5, y: 0.5), diameter: 0.2)
        }
        return BubbleState(
            center: CGPoint(
                x: (windowFrame.midX - displayFrame.minX) / displayFrame.width,
                y: (displayFrame.maxY - windowFrame.midY) / displayFrame.height
            ),
            diameter: windowFrame.height / displayFrame.height
        )
    }

    public static func windowFrame(for state: BubbleState, displayFrame: CGRect) -> CGRect {
        let size = state.diameter * displayFrame.height
        let midX = displayFrame.minX + state.center.x * displayFrame.width
        let midY = displayFrame.maxY - state.center.y * displayFrame.height
        return CGRect(x: midX - size / 2, y: midY - size / 2, width: size, height: size)
    }

    public static func renderRect(for state: BubbleState, renderSize: CGSize) -> CGRect {
        let size = state.diameter * renderSize.height
        let midX = state.center.x * renderSize.width
        let midY = (1 - state.center.y) * renderSize.height
        return CGRect(x: midX - size / 2, y: midY - size / 2, width: size, height: size)
    }

    public static func viewRect(for state: BubbleState, videoRect: CGRect) -> CGRect {
        let size = state.diameter * videoRect.height
        let midX = videoRect.minX + state.center.x * videoRect.width
        let midY = videoRect.minY + state.center.y * videoRect.height
        return CGRect(x: midX - size / 2, y: midY - size / 2, width: size, height: size)
    }

    public static func normalizedCenter(fromViewPoint point: CGPoint, videoRect: CGRect) -> CGPoint {
        guard videoRect.width > 0, videoRect.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(
            x: (point.x - videoRect.minX) / videoRect.width,
            y: (point.y - videoRect.minY) / videoRect.height
        )
    }

    public static func aspectFitRect(content: CGSize, in bounds: CGRect) -> CGRect {
        guard content.width > 0, content.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let size = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The largest centered square inside a frame — what a circular aspect-fill crop shows.
    public static func centeredSquareCrop(of size: CGSize) -> CGRect {
        let side = min(size.width, size.height)
        return CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }

    /// Keeps the whole bubble inside the frame. `aspect` is width / height of the frame.
    public static func clamped(_ state: BubbleState, aspect: Double) -> BubbleState {
        let diameter = min(max(state.diameter, minDiameter), maxDiameter)
        let radiusY = diameter / 2
        let radiusX = aspect > 0 ? radiusY / aspect : radiusY
        return BubbleState(
            center: CGPoint(
                x: min(max(state.center.x, radiusX), 1 - radiusX),
                y: min(max(state.center.y, radiusY), 1 - radiusY)
            ),
            diameter: diameter
        )
    }
}
