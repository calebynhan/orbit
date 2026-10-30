import CoreGraphics

public struct PixelSize: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Recording resolution. Named sizes set the *short* side (1080p = 1080 tall for landscape),
/// so a 16:9 selection at `.p1080` comes out at exactly 1920×1080.
public enum OutputResolution: String, CaseIterable, Sendable {
    case native
    case p720
    case p1080
    case p1440

    public var label: String {
        switch self {
        case .native: "Native (Retina)"
        case .p720: "720p"
        case .p1080: "1080p"
        case .p1440: "1440p"
        }
    }

    private var shortSide: Double? {
        switch self {
        case .native: nil
        case .p720: 720
        case .p1080: 1080
        case .p1440: 1440
        }
    }

    /// Output pixels for a capture area measured in points. Always even, as video encoders require.
    public func pixelSize(forPoints size: CGSize, scale: CGFloat) -> PixelSize {
        guard size.width > 0, size.height > 0 else { return PixelSize(width: 2, height: 2) }
        let factor = shortSide.map { $0 / min(size.width, size.height) } ?? scale
        return PixelSize(width: Self.even(size.width * factor), height: Self.even(size.height * factor))
    }

    private static func even(_ value: Double) -> Int {
        max(2, Int((value / 2).rounded()) * 2)
    }
}

/// Shape constraint for "Record Selected Portion".
public enum SelectionAspect: String, CaseIterable, Sendable {
    case freeform
    case widescreen

    public var label: String {
        switch self {
        case .freeform: "Freeform"
        case .widescreen: "16:9"
        }
    }

    /// Width units × height units; sizes snap to whole multiples so the ratio is exact in points.
    var units: (width: CGFloat, height: CGFloat)? {
        switch self {
        case .freeform: nil
        case .widescreen: (16, 9)
        }
    }
}
