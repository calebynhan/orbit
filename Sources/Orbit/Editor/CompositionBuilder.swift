import AVFoundation
import OrbitCore

enum CompositionError: LocalizedError {
    case missingScreenVideo
    case cannotCreateTrack

    var errorDescription: String? {
        switch self {
        case .missingScreenVideo: "The screen recording has no video. It may not have finished saving."
        case .cannotCreateTrack: "Couldn’t assemble the video."
        }
    }
}

/// The screen recording plus an optional face-cam clip, ready for preview or export.
struct EditableComposition {
    let composition: AVComposition
    let videoComposition: AVVideoComposition
    let renderSize: CGSize
    let hasCamera: Bool
}

enum CompositionBuilder {
    static func build(project: RecordingProject, folder: URL, store: OverlaySettingsStore) async throws -> EditableComposition {
        let screenAsset = AVURLAsset(url: folder.appendingPathComponent(project.screenFile))
        guard let screenVideo = try await screenAsset.loadTracks(withMediaType: .video).first else {
            throw CompositionError.missingScreenVideo
        }
        let (screenRange, naturalSize, frameRate) = try await screenVideo.load(.timeRange, .naturalSize, .nominalFrameRate)
        let duration = screenRange.duration
        let master = CMTimeRange(start: .zero, duration: duration)

        let composition = AVMutableComposition()
        guard let compScreen = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompositionError.cannotCreateTrack
        }
        try compScreen.insertTimeRange(screenRange, of: screenVideo, at: .zero)

        for audio in try await screenAsset.loadTracks(withMediaType: .audio) {
            try await insert(audio, from: screenRange.start, duration: duration, at: .zero, into: composition)
        }

        let camera = try await addCamera(project.camera, folder: folder, screenDuration: duration, into: composition)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = BubbleCompositor.self
        videoComposition.renderSize = CGSize(width: evenFloor(naturalSize.width), height: evenFloor(naturalSize.height))
        // ScreenCaptureKit only writes frames when the screen changes, so the file's nominal rate
        // under-reports. Render at the rate we captured at for a constant, exact frame rate.
        let fps = project.framesPerSecond ?? (frameRate >= 50 ? 60 : 30)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        videoComposition.instructions = [BubbleInstruction(
            timeRange: master, // every track is clamped to the screen video's duration
            screenTrackID: compScreen.trackID,
            cameraTrackID: camera?.trackID,
            cameraTransform: camera?.transform ?? .identity,
            cameraTimeRange: camera?.timeRange ?? .invalid,
            store: store
        )]

        return EditableComposition(
            composition: composition,
            videoComposition: videoComposition,
            renderSize: videoComposition.renderSize,
            hasCamera: camera != nil
        )
    }

    private static func addCamera(
        _ source: CameraSource?,
        folder: URL,
        screenDuration: CMTime,
        into composition: AVMutableComposition
    ) async throws -> (trackID: CMPersistentTrackID, transform: CGAffineTransform, timeRange: CMTimeRange)? {
        guard let source else { return nil }
        let asset = AVURLAsset(url: folder.appendingPathComponent(source.file))
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let (range, transform) = try await video.load(.timeRange, .preferredTransform)
        guard let placement = CameraPlacement.compute(
            offset: source.offset,
            cameraDuration: range.duration.seconds,
            screenDuration: screenDuration.seconds
        ) else { return nil }

        let sourceStart = range.start + seconds(placement.sourceStart)
        let length = seconds(placement.duration)
        let insertAt = seconds(placement.insertAt)
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompositionError.cannotCreateTrack
        }
        try track.insertTimeRange(CMTimeRange(start: sourceStart, duration: length), of: video, at: insertAt)

        if source.includeAudio {
            for audio in try await asset.loadTracks(withMediaType: .audio) {
                let audioStart = try await audio.load(.timeRange).start + seconds(placement.sourceStart)
                try await insert(audio, from: audioStart, duration: length, at: insertAt, into: composition)
            }
        }
        return (track.trackID, transform, CMTimeRange(start: insertAt, duration: length))
    }

    private static func insert(_ audio: AVAssetTrack, from start: CMTime, duration: CMTime, at insertAt: CMTime, into composition: AVMutableComposition) async throws {
        // Clamp to the audio that actually exists while keeping it in sync with the video timeline.
        let available = try await audio.load(.timeRange)
        let clampedStart = CMTimeMaximum(start, available.start)
        let end = CMTimeMinimum(start + duration, available.end)
        guard end > clampedStart else { return }
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CompositionError.cannotCreateTrack
        }
        try track.insertTimeRange(CMTimeRange(start: clampedStart, end: end), of: audio, at: insertAt + (clampedStart - start))
    }

    private static func seconds(_ value: Double) -> CMTime {
        CMTime(seconds: value, preferredTimescale: 600)
    }

    private static func evenFloor(_ value: CGFloat) -> CGFloat {
        CGFloat(Int(value) / 2 * 2)
    }
}
