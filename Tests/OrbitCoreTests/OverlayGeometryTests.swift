import CoreGraphics
import XCTest
@testable import OrbitCore

final class OverlayGeometryTests: XCTestCase {
    // A 1000x500 display whose bottom-left sits at (100, 50) in global AppKit coordinates.
    private let display = CGRect(x: 100, y: 50, width: 1000, height: 500)

    func testBubbleStateFromWindowFrameUsesTopLeftNormalizedCoords() {
        // 100pt bubble whose center is 200pt from the display's left and 100pt from its top.
        let window = CGRect(x: 100 + 150, y: 50 + 500 - 100 - 50, width: 100, height: 100)
        let state = OverlayGeometry.bubbleState(windowFrame: window, displayFrame: display)
        XCTAssertEqual(state.center.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(state.center.y, 0.2, accuracy: 1e-9)
        XCTAssertEqual(state.diameter, 0.2, accuracy: 1e-9)
    }

    func testWindowFrameRoundTripsThroughBubbleState() {
        let window = CGRect(x: 640, y: 120, width: 180, height: 180)
        let state = OverlayGeometry.bubbleState(windowFrame: window, displayFrame: display)
        let back = OverlayGeometry.windowFrame(for: state, displayFrame: display)
        XCTAssertEqual(back.origin.x, window.origin.x, accuracy: 1e-9)
        XCTAssertEqual(back.origin.y, window.origin.y, accuracy: 1e-9)
        XCTAssertEqual(back.width, window.width, accuracy: 1e-9)
    }

    func testRenderRectUsesBottomLeftOriginPixels() {
        let state = BubbleState(center: CGPoint(x: 0.25, y: 0.25), diameter: 0.5)
        let rect = OverlayGeometry.renderRect(for: state, renderSize: CGSize(width: 2000, height: 1000))
        XCTAssertEqual(rect, CGRect(x: 250, y: 500, width: 500, height: 500))
    }

    func testViewRectUsesTopLeftOriginInsideVideoRect() {
        let state = BubbleState(center: CGPoint(x: 0.5, y: 0.5), diameter: 0.2)
        let video = CGRect(x: 10, y: 20, width: 400, height: 200)
        let rect = OverlayGeometry.viewRect(for: state, videoRect: video)
        XCTAssertEqual(rect, CGRect(x: 190, y: 100, width: 40, height: 40))
    }

    func testCenterFromViewPointInvertsViewRect() {
        let video = CGRect(x: 10, y: 20, width: 400, height: 200)
        let center = OverlayGeometry.normalizedCenter(fromViewPoint: CGPoint(x: 110, y: 70), videoRect: video)
        XCTAssertEqual(center, CGPoint(x: 0.25, y: 0.25))
    }

    func testAspectFitLetterboxesWideContent() {
        let rect = OverlayGeometry.aspectFitRect(content: CGSize(width: 1600, height: 900), in: CGRect(x: 0, y: 0, width: 800, height: 800))
        XCTAssertEqual(rect, CGRect(x: 0, y: 175, width: 800, height: 450))
    }

    func testAspectFitHandlesZeroContent() {
        let rect = OverlayGeometry.aspectFitRect(content: .zero, in: CGRect(x: 0, y: 0, width: 800, height: 800))
        XCTAssertEqual(rect, .zero)
    }

    func testCenteredSquareCropOfLandscapeFrame() {
        let crop = OverlayGeometry.centeredSquareCrop(of: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(crop, CGRect(x: 420, y: 0, width: 1080, height: 1080))
    }

    func testCenteredSquareCropOfPortraitFrame() {
        let crop = OverlayGeometry.centeredSquareCrop(of: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(crop, CGRect(x: 0, y: 420, width: 1080, height: 1080))
    }

    func testClampKeepsBubbleFullyInsideFrame() {
        let state = BubbleState(center: CGPoint(x: -1, y: 2), diameter: 0.2)
        let clamped = OverlayGeometry.clamped(state, aspect: 2)
        XCTAssertEqual(clamped.center.x, 0.05, accuracy: 1e-9) // radius 0.1 of height = 0.05 of width
        XCTAssertEqual(clamped.center.y, 0.9, accuracy: 1e-9)
    }

    func testClampLimitsDiameter() {
        let tiny = OverlayGeometry.clamped(BubbleState(center: CGPoint(x: 0.5, y: 0.5), diameter: 0.001), aspect: 1)
        let huge = OverlayGeometry.clamped(BubbleState(center: CGPoint(x: 0.5, y: 0.5), diameter: 5), aspect: 1)
        XCTAssertEqual(tiny.diameter, OverlayGeometry.minDiameter)
        XCTAssertEqual(huge.diameter, OverlayGeometry.maxDiameter)
    }
}
