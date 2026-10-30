import CoreGraphics
import XCTest
@testable import OrbitCore

final class BubbleTrackTests: XCTestCase {
    private let a = BubbleState(center: CGPoint(x: 0.1, y: 0.1), diameter: 0.2)
    private let b = BubbleState(center: CGPoint(x: 0.5, y: 0.9), diameter: 0.4)

    func testEmptyTrackHasNoState() {
        XCTAssertNil(BubbleTrack().state(at: 1))
    }

    func testClampsBeforeFirstAndAfterLastKeyframe() {
        let track = BubbleTrack(keyframes: [.init(time: 1, state: a), .init(time: 2, state: b)])
        XCTAssertEqual(track.state(at: 0), a)
        XCTAssertEqual(track.state(at: 5), b)
    }

    func testInterpolatesLinearlyBetweenKeyframes() throws {
        let track = BubbleTrack(keyframes: [.init(time: 0, state: a), .init(time: 2, state: b)])
        let mid = try XCTUnwrap(track.state(at: 1))
        XCTAssertEqual(mid.center.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(mid.center.y, 0.5, accuracy: 1e-9)
        XCTAssertEqual(mid.diameter, 0.3, accuracy: 1e-9)
    }

    func testKeyframesAreSortedOnInit() {
        let track = BubbleTrack(keyframes: [.init(time: 2, state: b), .init(time: 0, state: a)])
        XCTAssertEqual(track.keyframes.map(\.time), [0, 2])
    }

    func testAppendingReturnsNewTrackWithoutMutatingOriginal() {
        let original = BubbleTrack(keyframes: [.init(time: 0, state: a)])
        let extended = original.appending(.init(time: 1, state: b))
        XCTAssertEqual(original.keyframes.count, 1)
        XCTAssertEqual(extended.keyframes.count, 2)
    }

    func testStateAtManyKeyframesUsesCorrectSegment() throws {
        let frames = (0...10).map { i in
            BubbleKeyframe(time: Double(i), state: BubbleState(center: CGPoint(x: Double(i) / 10, y: 0), diameter: 0.2))
        }
        let track = BubbleTrack(keyframes: frames)
        let state = try XCTUnwrap(track.state(at: 7.5))
        XCTAssertEqual(state.center.x, 0.75, accuracy: 1e-9)
    }
}

final class BubbleTrackRecorderTests: XCTestCase {
    private let a = BubbleState(center: CGPoint(x: 0.1, y: 0.1), diameter: 0.2)
    private let b = BubbleState(center: CGPoint(x: 0.6, y: 0.6), diameter: 0.2)

    func testFirstSampleBecomesKeyframe() {
        let recorder = BubbleTrackRecorder().recording(a, at: 0)
        XCTAssertEqual(recorder.track.keyframes, [.init(time: 0, state: a)])
    }

    func testUnchangedSamplesDoNotAddKeyframes() {
        let recorder = BubbleTrackRecorder()
            .recording(a, at: 0)
            .recording(a, at: 1)
            .recording(a, at: 2)
        XCTAssertEqual(recorder.track.keyframes.count, 1)
    }

    func testMoveAfterHoldInsertsHoldKeyframeSoBubbleDoesNotDrift() {
        let recorder = BubbleTrackRecorder()
            .recording(a, at: 0)
            .recording(a, at: 5)
            .recording(b, at: 5.1)
        XCTAssertEqual(recorder.track.keyframes, [
            .init(time: 0, state: a),
            .init(time: 5, state: a),
            .init(time: 5.1, state: b),
        ])
        XCTAssertEqual(recorder.track.state(at: 4), a)
    }

    func testContinuousMovementRecordsEverySample() {
        let c = BubbleState(center: CGPoint(x: 0.9, y: 0.9), diameter: 0.2)
        let recorder = BubbleTrackRecorder()
            .recording(a, at: 0)
            .recording(b, at: 0.1)
            .recording(c, at: 0.2)
        XCTAssertEqual(recorder.track.keyframes.map(\.time), [0, 0.1, 0.2])
    }

    func testFinishedAppendsFinalHold() {
        let recorder = BubbleTrackRecorder()
            .recording(a, at: 0)
            .recording(a, at: 3)
        XCTAssertEqual(recorder.finished().keyframes.last, .init(time: 3, state: a))
    }
}
