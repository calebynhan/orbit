import XCTest
@testable import OrbitCore

final class BubbleStyleTests: XCTestCase {
    func testDefaultStyleIsWhiteCircle() {
        let style = BubbleStyle.default
        XCTAssertEqual(style.shape, .circle)
        XCTAssertEqual(style.outlineWidth, 0.035, accuracy: 1e-9)
        XCTAssertEqual(style.outlineColor, .white)
    }

    func testWithReturnsCopies() {
        let base = BubbleStyle.default
        let changed = base.with(shape: .square).with(outlineWidth: 0.02).with(outlineColor: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertEqual(base, .default)
        XCTAssertEqual(changed.shape, .square)
        XCTAssertEqual(changed.outlineWidth, 0.02, accuracy: 1e-9)
        XCTAssertEqual(changed.outlineColor.red, 1)
    }

    func testOutlineWidthIsClamped() {
        XCTAssertEqual(BubbleStyle.default.with(outlineWidth: -1).outlineWidth, 0)
        XCTAssertEqual(BubbleStyle.default.with(outlineWidth: 9).outlineWidth, BubbleStyle.maxOutlineWidth)
    }

    func testCornerRadiusFractionPerShape() {
        XCTAssertEqual(BubbleShape.circle.cornerRadiusFraction, 0.5)
        XCTAssertEqual(BubbleShape.rounded.cornerRadiusFraction, 0.18)
        XCTAssertEqual(BubbleShape.square.cornerRadiusFraction, 0)
    }

    func testRGBAColorClampsComponents() {
        let c = RGBAColor(red: 2, green: -1, blue: 0.5, alpha: 3)
        XCTAssertEqual(c, RGBAColor(red: 1, green: 0, blue: 0.5, alpha: 1))
    }

    func testOverlaySettingsCarryStyleAndDecodeLegacyProjectsWithDefaults() throws {
        let legacy = """
        {"visible":true,"placement":"fixed","fixedCenter":[0.1,0.8],"mirrored":true}
        """
        let decoded = try JSONDecoder().decode(OverlaySettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.style, .default)
        XCTAssertEqual(decoded.fixedCenter.x, 0.1)

        let styled = OverlaySettings.default.with(style: .default.with(shape: .rounded))
        let data = try JSONEncoder().encode(styled)
        XCTAssertEqual(try JSONDecoder().decode(OverlaySettings.self, from: data).style.shape, .rounded)
    }
}
