import CoreGraphics
import XCTest
@testable import OrbitCore

final class CameraPlacementTests: XCTestCase {
    func testCameraStartingAfterScreen() {
        let placement = CameraPlacement.compute(offset: 0.25, cameraDuration: 10, screenDuration: 10)
        XCTAssertEqual(placement, CameraPlacement(sourceStart: 0, insertAt: 0.25, duration: 9.75))
    }

    func testCameraStartingBeforeScreenIsTrimmed() {
        let placement = CameraPlacement.compute(offset: -0.5, cameraDuration: 10, screenDuration: 20)
        XCTAssertEqual(placement, CameraPlacement(sourceStart: 0.5, insertAt: 0, duration: 9.5))
    }

    func testCameraLongerThanScreenIsCut() {
        let placement = CameraPlacement.compute(offset: 2, cameraDuration: 30, screenDuration: 10)
        XCTAssertEqual(placement, CameraPlacement(sourceStart: 0, insertAt: 2, duration: 8))
    }

    func testNoOverlapReturnsNil() {
        XCTAssertNil(CameraPlacement.compute(offset: 12, cameraDuration: 5, screenDuration: 10))
        XCTAssertNil(CameraPlacement.compute(offset: -6, cameraDuration: 5, screenDuration: 10))
    }

    func testOffsetFromStartTimes() {
        XCTAssertEqual(CameraPlacement.offset(cameraStart: 100.3, screenStart: 100.1), 0.2, accuracy: 1e-9)
    }
}

final class OverlaySettingsTests: XCTestCase {
    private let recorded = BubbleState(center: CGPoint(x: 0.7, y: 0.3), diameter: 0.25)

    private var track: BubbleTrack {
        BubbleTrack(keyframes: [.init(time: 0, state: recorded)])
    }

    func testHiddenOverlayResolvesToNil() {
        let settings = OverlaySettings.default.with(visible: false)
        XCTAssertNil(settings.state(at: 0, track: track))
    }

    func testFollowRecordingUsesTrack() {
        let settings = OverlaySettings.default.with(placement: .followRecording)
        XCTAssertEqual(settings.state(at: 1, track: track), recorded)
    }

    func testFollowRecordingFallsBackToFixedWhenTrackEmpty() {
        let settings = OverlaySettings.default.with(placement: .followRecording)
        XCTAssertEqual(settings.state(at: 1, track: BubbleTrack())?.center, settings.fixedCenter)
    }

    func testFixedPlacementIgnoresTrackPosition() {
        let center = CGPoint(x: 0.2, y: 0.8)
        let settings = OverlaySettings.default.with(placement: .fixed).with(fixedCenter: center)
        let state = settings.state(at: 0, track: track)
        XCTAssertEqual(state?.center, center)
        XCTAssertEqual(state?.diameter, recorded.diameter) // size still comes from the recording
    }

    func testDiameterOverrideWins() {
        let settings = OverlaySettings.default.with(placement: .followRecording).with(diameterOverride: 0.4)
        XCTAssertEqual(settings.state(at: 0, track: track)?.diameter, 0.4)
    }

    func testWithReturnsCopies() {
        let original = OverlaySettings.default
        _ = original.with(mirrored: !original.mirrored)
        XCTAssertEqual(original, OverlaySettings.default)
    }
}

final class RecordingProjectTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let project = RecordingProject(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            screenFile: "screen.mov",
            camera: CameraSource(file: "camera.mov", offset: 0.12, includeAudio: false),
            overlay: .default,
            bubbleTrack: BubbleTrack(keyframes: [.init(time: 0, state: BubbleState(center: CGPoint(x: 0.5, y: 0.5), diameter: 0.2))])
        )
        try project.save(to: folder)
        XCTAssertEqual(try RecordingProject.load(from: folder), project)
    }

    func testFrameRateSurvivesEditsAndOlderProjectsStillLoad() throws {
        let project = RecordingProject(createdAt: Date(), screenFile: "screen.mov", camera: nil, overlay: .default, bubbleTrack: BubbleTrack(), framesPerSecond: 60)
        XCTAssertEqual(project.with(overlay: .default.with(visible: false)).framesPerSecond, 60)
        XCTAssertEqual(project.with(camera: nil).framesPerSecond, 60)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = """
        {"version":1,"createdAt":"2026-10-30T14:00:00Z","screenFile":"screen.mov",
         "overlay":{"visible":true,"placement":"fixed","fixedCenter":[0.1,0.8],"mirrored":true},
         "bubbleTrack":{"keyframes":[]}}
        """
        try Data(legacy.utf8).write(to: folder.appendingPathComponent(RecordingProject.fileName))
        XCTAssertNil(try RecordingProject.load(from: folder).framesPerSecond)
    }

    func testLoadFailsWithClearErrorWhenMissing() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try RecordingProject.load(from: folder)) { error in
            XCTAssertEqual(error as? RecordingProjectError, .notAProject(folder))
        }
    }

    func testLoadRefusesFilesOutsideTheFolder() throws {
        for (screen, camera) in [("../secret.mov", "camera.mov"), ("screen.mov", "/etc/passwd"), ("screen.mov", ".."), ("", "camera.mov")] {
            let folder = try makeTemporaryFolder()
            defer { try? FileManager.default.removeItem(at: folder) }
            let json = """
            {"version":1,"createdAt":"2026-10-30T14:00:00Z","screenFile":\(quoted(screen)),
             "camera":{"file":\(quoted(camera)),"offset":0,"includeAudio":false},
             "overlay":{"visible":true,"placement":"fixed","fixedCenter":[0.1,0.8],"mirrored":true},
             "bubbleTrack":{"keyframes":[]}}
            """
            try Data(json.utf8).write(to: folder.appendingPathComponent(RecordingProject.fileName))
            XCTAssertThrowsError(try RecordingProject.load(from: folder), "\(screen) / \(camera)") { error in
                guard let projectError = error as? RecordingProjectError, case .unsafeFileReference = projectError else {
                    return XCTFail("Expected unsafeFileReference, got \(error)")
                }
            }
        }
    }

    func testFileURLRefusesSymlinkLeavingTheFolder() throws {
        let folder = try makeTemporaryFolder()
        let outside = try makeTemporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: outside)
        }
        let target = outside.appendingPathComponent("private.mov")
        try Data().write(to: target)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("screen.mov"), withDestinationURL: target)

        XCTAssertThrowsError(try RecordingProject.fileURL("screen.mov", in: folder))
        XCTAssertEqual(try RecordingProject.fileURL("camera.mov", in: folder).lastPathComponent, "camera.mov")
    }

    func testLoadRefusesUnsupportedFrameRate() throws {
        let folder = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = RecordingProject(createdAt: Date(), screenFile: "screen.mov", camera: nil, overlay: .default, bubbleTrack: BubbleTrack(), framesPerSecond: 0)
        try project.save(to: folder)
        XCTAssertThrowsError(try RecordingProject.load(from: folder))
    }

    private func makeTemporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func quoted(_ string: String) -> String {
        String(decoding: try! JSONEncoder().encode(string), as: UTF8.self)
    }

    func testWithCameraReturnsUpdatedCopy() {
        let project = RecordingProject(createdAt: Date(), screenFile: "screen.mov", camera: nil, overlay: .default, bubbleTrack: BubbleTrack())
        let updated = project.with(camera: CameraSource(file: "take.mov", offset: 1, includeAudio: true))
        XCTAssertNil(project.camera)
        XCTAssertEqual(updated.camera?.file, "take.mov")
    }

    func testFolderNameIsFilesystemSafe() {
        let date = Date(timeIntervalSince1970: 0)
        let name = RecordingProject.folderName(for: date, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "Recording 1970-01-01 at 00.00.00")
        XCTAssertFalse(name.contains(":"))
    }
}
