@preconcurrency import AVFoundation
import QuartzCore

enum CaptureError: LocalizedError {
    case noCamera
    case noMicrophone
    case cannotAddInput(String)
    case permissionDenied(String)
    case notRecording
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .noCamera: "No camera was found."
        case .noMicrophone: "No microphone was found."
        case .cannotAddInput(let name): "Couldn’t use the \(name)."
        case .permissionDenied(let what):
            "Orbit needs \(what) access. Turn it on in System Settings → Privacy & Security, then try again."
        case .notRecording: "Nothing is being recorded."
        case .noDisplay: "Couldn’t find the display to record."
        }
    }
}

/// Owns the camera `AVCaptureSession` used for both the live bubble preview and the camera file.
// Mutable state (continuations) is only touched on the main queue, hence @unchecked.
final class CameraCapture: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "orbit.camera.session")
    private var startContinuation: CheckedContinuation<CFTimeInterval, Error>?
    private var finishContinuation: CheckedContinuation<URL, Error>?

    static func requestAccess(audio: Bool) async -> Bool {
        let video = await AVCaptureDevice.requestAccess(for: .video)
        guard audio, video else { return video }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    // Threading rule: `startRunning`/`stopRunning` run on `sessionQueue`, hold the session lock,
    // and call back to the main thread synchronously. Anything on main that also needs the lock —
    // creating or deallocating an AVCaptureVideoPreviewLayer — must not overlap them, or both
    // threads wait forever. So: create preview layers after `configure`, before `startRunning`,
    // and release them only after `stop()` returns.

    /// Adds the camera (and optionally mic) inputs and the file output. Doesn't start the camera.
    func configure(includeAudio: Bool) throws {
        guard let camera = AVCaptureDevice.default(for: .video) else { throw CaptureError.noCamera }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        let cameraInput = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(cameraInput) else { throw CaptureError.cannotAddInput("camera") }
        session.addInput(cameraInput)

        if includeAudio {
            guard let mic = AVCaptureDevice.default(for: .audio) else { throw CaptureError.noMicrophone }
            let micInput = try AVCaptureDeviceInput(device: mic)
            guard session.canAddInput(micInput) else { throw CaptureError.cannotAddInput("microphone") }
            session.addInput(micInput)
        }

        guard session.canAddOutput(movieOutput) else { throw CaptureError.cannotAddInput("camera recorder") }
        session.addOutput(movieOutput)
    }

    /// Starts the camera. Returns once it's live, without blocking the main thread.
    func startRunning() async {
        let session = self.session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.startRunning()
                continuation.resume()
            }
        }
    }

    /// Stops the camera. Returns once it has fully stopped, without blocking the main thread.
    func stop() async {
        let session = self.session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                session.stopRunning()
                continuation.resume()
            }
        }
    }

    /// Starts writing the camera to `url`. Returns the host time (`CACurrentMediaTime`) recording began.
    func startRecording(to url: URL) async throws -> CFTimeInterval {
        try await waitUntilRunning()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.startContinuation = continuation
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
            }
        }
    }

    /// `startRunning()` is asynchronous; recording before the camera is live fails.
    private func waitUntilRunning() async throws {
        let pollInterval: UInt64 = 50_000_000
        let maxPolls = 100
        for _ in 0..<maxPolls where !session.isRunning {
            try await Task.sleep(nanoseconds: pollInterval)
        }
        guard session.isRunning else { throw CaptureError.cannotAddInput("camera (it didn’t start)") }
    }

    func stopRecording() async throws -> URL {
        guard movieOutput.isRecording else { throw CaptureError.notRecording }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                self.finishContinuation = continuation
                self.movieOutput.stopRecording()
            }
        }
    }

    // MARK: AVCaptureFileOutputRecordingDelegate

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let startedAt = CACurrentMediaTime()
        DispatchQueue.main.async {
            self.startContinuation?.resume(returning: startedAt)
            self.startContinuation = nil
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            // AVFoundation reports some successful stops as errors; trust the flag it attaches.
            let succeeded = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            if let start = self.startContinuation {
                start.resume(throwing: error ?? CaptureError.notRecording)
                self.startContinuation = nil
            }
            guard let finish = self.finishContinuation else { return }
            self.finishContinuation = nil
            if succeeded {
                finish.resume(returning: outputFileURL)
            } else {
                finish.resume(throwing: error ?? CaptureError.notRecording)
            }
        }
    }
}
