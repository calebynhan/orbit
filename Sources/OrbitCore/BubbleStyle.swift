/// The face cam's shape and outline. Size lives in `BubbleState`; this is the look.
public enum BubbleShape: String, Codable, CaseIterable, Sendable {
    case circle
    case rounded
    case square

    public var label: String {
        switch self {
        case .circle: "Circle"
        case .rounded: "Rounded"
        case .square: "Square"
        }
    }

    /// Corner radius as a fraction of the bubble's side.
    public var cornerRadiusFraction: Double {
        switch self {
        case .circle: 0.5
        case .rounded: 0.18
        case .square: 0
        }
    }
}

/// A platform-independent colour, components 0...1.
public struct RGBAColor: Codable, Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    public static let white = RGBAColor(red: 1, green: 1, blue: 1)
    public static let black = RGBAColor(red: 0, green: 0, blue: 0)

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}

public struct BubbleStyle: Codable, Equatable, Sendable {
    public static let maxOutlineWidth = 0.08
    public static let `default` = BubbleStyle(shape: .circle, outlineWidth: 0.035, outlineColor: .white)

    public let shape: BubbleShape
    /// Outline thickness as a fraction of the bubble's side. 0 hides it.
    public let outlineWidth: Double
    public let outlineColor: RGBAColor

    public init(shape: BubbleShape, outlineWidth: Double, outlineColor: RGBAColor) {
        self.shape = shape
        self.outlineWidth = min(max(outlineWidth, 0), Self.maxOutlineWidth)
        self.outlineColor = outlineColor
    }

    public func with(shape: BubbleShape) -> BubbleStyle {
        BubbleStyle(shape: shape, outlineWidth: outlineWidth, outlineColor: outlineColor)
    }

    public func with(outlineWidth: Double) -> BubbleStyle {
        BubbleStyle(shape: shape, outlineWidth: outlineWidth, outlineColor: outlineColor)
    }

    public func with(outlineColor: RGBAColor) -> BubbleStyle {
        BubbleStyle(shape: shape, outlineWidth: outlineWidth, outlineColor: outlineColor)
    }
}
