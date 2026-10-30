import AppKit
import Foundation
import OrbitCore

/// The look used for the live bubble and as the starting style of each new recording.
enum BubbleStyleStore {
    private static let key = "bubbleStyle"

    static var style: BubbleStyle {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let stored = try? JSONDecoder().decode(BubbleStyle.self, from: data) else { return .default }
            return stored
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) }
        }
    }
}

extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        self.init(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent, alpha: c.alphaComponent)
    }
}
