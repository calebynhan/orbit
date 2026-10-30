import CoreGraphics
import XCTest
@testable import OrbitCore

final class SelectionGeometryTests: XCTestCase {
    // A 1000x600 display whose bottom-left sits at (200, 100) in global AppKit coordinates.
    private let display = CGRect(x: 200, y: 100, width: 1000, height: 600)
    private let minSize = SelectionGeometry.minimumSize

    func testSourceRectIsDisplayLocalWithTopLeftOrigin() {
        // 300x200 selection, 100pt from the display's left and 50pt from its top.
        let selection = CGRect(x: 300, y: 100 + 600 - 50 - 200, width: 300, height: 200)
        XCTAssertEqual(
            SelectionGeometry.sourceRect(selection: selection, display: display),
            CGRect(x: 100, y: 50, width: 300, height: 200)
        )
    }

    func testRectFromTwoPointsIsStandardized() {
        let rect = SelectionGeometry.rect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20))
        XCTAssertEqual(rect, CGRect(x: 10, y: 20, width: 40, height: 60))
    }

    func testDefaultSelectionIsCenteredInsideBounds() {
        let rect = SelectionGeometry.defaultSelection(in: display)
        XCTAssertEqual(rect.midX, display.midX, accuracy: 1e-9)
        XCTAssertEqual(rect.midY, display.midY, accuracy: 1e-9)
        XCTAssertTrue(display.contains(rect))
    }

    func testClampMovesRectBackInsideBoundsKeepingSize() {
        let rect = SelectionGeometry.clamped(CGRect(x: 1100, y: 50, width: 300, height: 200), to: display)
        XCTAssertEqual(rect, CGRect(x: 900, y: 100, width: 300, height: 200))
    }

    func testClampShrinksOversizedRectAndEnforcesMinimum() {
        let huge = SelectionGeometry.clamped(CGRect(x: 0, y: 0, width: 5000, height: 5000), to: display)
        XCTAssertEqual(huge, display)
        let tiny = SelectionGeometry.clamped(CGRect(x: 500, y: 300, width: 2, height: 2), to: display)
        XCTAssertEqual(tiny.size, minSize)
    }

    func testMovingBodyTranslatesAndStaysInBounds() {
        let start = CGRect(x: 300, y: 200, width: 200, height: 100)
        XCTAssertEqual(
            SelectionGeometry.resized(start, handle: .body, by: CGSize(width: 50, height: -20), bounds: display),
            CGRect(x: 350, y: 180, width: 200, height: 100)
        )
        XCTAssertEqual(
            SelectionGeometry.resized(start, handle: .body, by: CGSize(width: 5000, height: 0), bounds: display),
            CGRect(x: 1000, y: 200, width: 200, height: 100)
        )
    }

    func testDraggingCornerHandlesMovesOnlyThoseEdges() {
        let start = CGRect(x: 300, y: 200, width: 200, height: 100)
        // y-up space: "top" is maxY.
        XCTAssertEqual(
            SelectionGeometry.resized(start, handle: .topRight, by: CGSize(width: 40, height: 30), bounds: display),
            CGRect(x: 300, y: 200, width: 240, height: 130)
        )
        XCTAssertEqual(
            SelectionGeometry.resized(start, handle: .bottomLeft, by: CGSize(width: -40, height: -30), bounds: display),
            CGRect(x: 260, y: 170, width: 240, height: 130)
        )
    }

    func testDraggingEdgeHandleOnlyChangesOneDimension() {
        let start = CGRect(x: 300, y: 200, width: 200, height: 100)
        XCTAssertEqual(
            SelectionGeometry.resized(start, handle: .left, by: CGSize(width: 20, height: 999), bounds: display),
            CGRect(x: 320, y: 200, width: 180, height: 100)
        )
        XCTAssertEqual(
            SelectionGeometry.resized(start, handle: .top, by: CGSize(width: 999, height: -10), bounds: display),
            CGRect(x: 300, y: 200, width: 200, height: 90)
        )
    }

    func testResizeNeverGoesBelowMinimumOrOutsideBounds() {
        let start = CGRect(x: 300, y: 200, width: 200, height: 100)
        let collapsed = SelectionGeometry.resized(start, handle: .right, by: CGSize(width: -1000, height: 0), bounds: display)
        XCTAssertEqual(collapsed.minX, 300)
        XCTAssertEqual(collapsed.width, minSize.width)

        let grown = SelectionGeometry.resized(start, handle: .bottomLeft, by: CGSize(width: -5000, height: -5000), bounds: display)
        XCTAssertEqual(grown.minX, display.minX)
        XCTAssertEqual(grown.minY, display.minY)
        XCTAssertEqual(grown.maxX, start.maxX)
        XCTAssertEqual(grown.maxY, start.maxY)
    }

    // MARK: 16:9 lock

    func testWidescreenLockSnapsToExact16x9WholePoints() {
        let rect = SelectionGeometry.constrained(CGRect(x: 300, y: 200, width: 333, height: 150), aspect: .widescreen, anchor: .body, bounds: display)
        XCTAssertEqual(rect.width * 9, rect.height * 16)
        XCTAssertEqual(rect.width, rect.width.rounded())
        XCTAssertEqual(rect.height, rect.height.rounded())
        XCTAssertEqual(rect.origin.x, rect.origin.x.rounded())
        XCTAssertEqual(rect.origin.y, rect.origin.y.rounded())
    }

    func testWidescreenLockKeepsOppositeCornerAnchored() {
        let start = CGRect(x: 300, y: 200, width: 320, height: 180)
        let dragged = SelectionGeometry.resized(start, handle: .topRight, by: CGSize(width: 160, height: 0), bounds: display, aspect: .widescreen)
        XCTAssertEqual(dragged, CGRect(x: 300, y: 200, width: 480, height: 270))
    }

    func testWidescreenLockFromVerticalEdgeDrivesWidth() {
        let start = CGRect(x: 300, y: 200, width: 320, height: 180)
        let dragged = SelectionGeometry.resized(start, handle: .top, by: CGSize(width: 0, height: 90), bounds: display, aspect: .widescreen)
        XCTAssertEqual(dragged.height, 270)
        XCTAssertEqual(dragged.width, 480)
        XCTAssertEqual(dragged.minY, 200) // bottom edge stays put
    }

    func testWidescreenLockFitsInsideSmallBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 300)
        let rect = SelectionGeometry.constrained(CGRect(x: 0, y: 0, width: 1000, height: 300), aspect: .widescreen, anchor: .body, bounds: bounds)
        XCTAssertTrue(bounds.contains(rect))
        XCTAssertEqual(rect.width * 9, rect.height * 16)
    }

    func testFreeformConstraintOnlySnapsToWholePoints() {
        let rect = SelectionGeometry.constrained(CGRect(x: 300.4, y: 200.6, width: 333.3, height: 150.2), aspect: .freeform, anchor: .body, bounds: display)
        XCTAssertEqual(rect, CGRect(x: 300, y: 201, width: 333, height: 150))
    }

    func testHitTestFindsHandlesBodyAndOutside() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 102, y: 198), in: rect), .topLeft)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 300, y: 100), in: rect), .bottomRight)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 200, y: 200), in: rect), .top)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 99, y: 150), in: rect), .left)
        XCTAssertEqual(SelectionGeometry.handle(at: CGPoint(x: 200, y: 150), in: rect), .body)
        XCTAssertNil(SelectionGeometry.handle(at: CGPoint(x: 10, y: 10), in: rect))
    }
}
