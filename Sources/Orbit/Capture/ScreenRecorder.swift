import AVFoundation
import OrbitCore
import os
import QuartzCore
@preconcurrency import ScreenCaptureKit

struct ScreenRecordingOptions {
    let displayID: CGDirectDisplayID
    let outputURL: URL
    let microphone: Bool
    let systemAudio: Bool
    let framesPerSecond: Int32
    /// Display-local points, top-left origin (ScreenCaptureKit's `sourceRect`). `nil` = whole display.
    let sourceRect: CGRect?
    /// Exact pixel size of the recorded video, e.g. 1920×1080.
    let outputSize: PixelSize
}

/// Records one display to a .mov via ScreenCaptureKit, excluding Orbit's own windows
/// (toolbar, face-cam bubble) so the bubble can be repositioned after recording.
// Mutable state (continuations, stream) is only touched on the main queue, hence @unchecked.
final class ScreenRecorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate, @unchecked Sendable {
    private static let log = Logger(subsystem: "dev.orbit.Orbit", category: "ScreenRecorder")
    private static let finishTimeout: TimeInterval = 5

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var startContinuation: CheckedContinuation<CFTimeInterval, Error>?
    private var finishContinuation: CheckedContinuation<Void, Error>?

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Starts recording. Returns the host time (`CACurrentMediaTime`) the file began.
    func start(_ options: ScreenRecordingOptions) async throws -> CFTimeInterval {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == options.displayID }) else {
            throw CaptureError.noDisplay
        }
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let config = SCStreamConfiguration()
        if let sourceRect = options.sourceRect {
            config.sourceRect = sourceRect
        }
        config.width = options.outputSize.width
        config.height = options.outputSize.height
        // The output size already matches the area's aspect (to the even pixel). Letting SCK
        // letterbox would add a 1px black edge, so fill the frame exactly instead.
        config.preservesAspectRatio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: options.framesPerSecond)
        config.showsCursor = true
        config.capturesAudio = options.systemAudio
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = options.microphone
        if options.microphone {
            config.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
        }

        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = options.outputURL
        outputConfig.outputFileType = .mov
        outputConfig.videoCodecType = .hevc

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream
        self.recordingOutput = output

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.startContinuation = continuation
                stream.startCapture { error in
                    guard let error else { return }
                    DispatchQueue.main.async { self.failPending(with: error) }
                }
            }
        }
    }

    func stop() async throws {
        guard let stream else { throw CaptureError.notRecording }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                self.finishContinuation = continuation
                stream.stopCapture { error in
                    if let error { Self.log.error("stopCapture failed: \(error.localizedDescription)") }
                }
                // Safety net: never leave the UI stuck if the finish callback doesn't arrive.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishTimeout) {
                    guard let pending = self.finishContinuation else { return }
                    Self.log.error("Recording finish callback timed out; continuing with file on disk")
                    self.finishContinuation = nil
                    pending.resume()
                }
            }
        }
        self.stream = nil
        self.recordingOutput = nil
    }

    private func failPending(with error: Error) {
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
    }

    // MARK: SCRecordingOutputDelegate

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let startedAt = CACurrentMediaTime()
        DispatchQueue.main.async {
            self.startContinuation?.resume(returning: startedAt)
            self.startContinuation = nil
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Self.log.error("Recording failed: \(error.localizedDescription)")
        DispatchQueue.main.async { self.failPending(with: error) }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async {
            self.finishContinuation?.resume()
            self.finishContinuation = nil
        }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Self.log.error("Stream stopped: \(error.localizedDescription)")
        DispatchQueue.main.async { self.failPending(with: error) }
    }
}
