import CoreGraphics
import XCTest
@testable import OrbitCore

final class CaptureFormatTests: XCTestCase {
    func testWidescreenSelectionAt1080pIsExactlyFullHD() {
        let size = OutputResolution.p1080.pixelSize(forPoints: CGSize(width: 640, height: 360), scale: 2)
        XCTAssertEqual(size, PixelSize(width: 1920, height: 1080))
    }

    func testRetinaScreenAt1080pKeepsAspectWithEvenWidth() {
        // 1512x982 MacBook Pro display (~16:10.4).
        let size = OutputResolution.p1080.pixelSize(forPoints: CGSize(width: 1512, height: 982), scale: 2)
        XCTAssertEqual(size.height, 1080)
        XCTAssertEqual(size.width, 1662)
        XCTAssertEqual(size.width % 2, 0)
    }

    func testPortraitSelectionAt1080pCapsShortSide() {
        // 1080p means the *short* side is 1080, like a phone's vertical video.
        let size = OutputResolution.p1080.pixelSize(forPoints: CGSize(width: 360, height: 640), scale: 2)
        XCTAssertEqual(size, PixelSize(width: 1080, height: 1920))
    }

    func testNativeUsesBackingPixels() {
        let size = OutputResolution.native.pixelSize(forPoints: CGSize(width: 301, height: 200), scale: 2)
        XCTAssertEqual(size, PixelSize(width: 602, height: 400))
    }

    func test720pIs1280x720ForWidescreen() {
        let size = OutputResolution.p720.pixelSize(forPoints: CGSize(width: 1920, height: 1080), scale: 1)
        XCTAssertEqual(size, PixelSize(width: 1280, height: 720))
    }

    func testDegenerateSizeIsSafe() {
        let size = OutputResolution.p1080.pixelSize(forPoints: .zero, scale: 2)
        XCTAssertEqual(size, PixelSize(width: 2, height: 2))
    }

    func testFormatRoundTripsThroughUserDefaultsStrings() {
        XCTAssertEqual(OutputResolution(rawValue: OutputResolution.p1080.rawValue), .p1080)
        XCTAssertEqual(SelectionAspect(rawValue: SelectionAspect.widescreen.rawValue), .widescreen)
    }
}
