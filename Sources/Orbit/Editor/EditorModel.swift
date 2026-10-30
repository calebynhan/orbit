import AppKit
import AVFoundation
import OrbitCore
import os
import QuartzCore
import UniformTypeIdentifiers

/// State and actions for one recording's editor window.
@MainActor
final class EditorModel: ObservableObject {
    static let diameterRange = 0.08...0.6
    private static let log = Logger(subsystem: "dev.orbit.Orbit", category: "Editor")

    let folder: URL
    let player = AVPlayer()

    @Published private(set) var project: RecordingProject
    @Published private(set) var renderSize: CGSize = .zero
    @Published private(set) var hasCamera = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = true
    @Published private(set) var isRecordingTake = false
    @Published private(set) var exportProgress: Double?
    @Published private(set) var loadError: String?

    private var store: OverlaySettingsStore
    private var editable: EditableComposition?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var take: FaceCamTake?

    private struct FaceCamTake {
        let capture: CameraCapture
        let bubble: CameraBubbleController
        let url: URL
        let offset: Double
    }

    init(folder: URL, project: RecordingProject) {
        self.folder = folder
        self.project = project
        self.store = OverlaySettingsStore(settings: project.overlay, track: project.bubbleTrack)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
                self.isPlaying = self.player.rate != 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, (note.object as? AVPlayerItem) === self.player.currentItem else { return }
                self.isPlaying = false
                if self.isRecordingTake { Task { await self.stopFaceCamTake() } }
            }
        }
    }

    var overlay: OverlaySettings { project.overlay }
    var hasRecordedPath: Bool { !project.bubbleTrack.isEmpty }
    var isExporting: Bool { exportProgress != nil }

    /// The bubble as it should appear right now, already clamped inside the frame.
    var currentBubbleState: BubbleState? {
        guard hasCamera, renderSize.height > 0, let state = overlay.state(at: currentTime, track: project.bubbleTrack) else { return nil }
        return OverlayGeometry.clamped(state, aspect: renderSize.width / renderSize.height)
    }

    var currentDiameter: Double {
        overlay.diameterOverride ?? project.bubbleTrack.state(at: currentTime)?.diameter ?? OverlaySettings.defaultDiameter
    }

    // MARK: Loading

    func load() async {
        isLoading = true
        defer { isLoading = false }
        let store = OverlaySettingsStore(settings: project.overlay, track: project.bubbleTrack)
        do {
            let editable = try await CompositionBuilder.build(project: project, folder: folder, store: store)
            let item = AVPlayerItem(asset: editable.composition)
            item.videoComposition = editable.videoComposition
            let resumeAt = player.currentTime()
            player.replaceCurrentItem(with: item)
            await player.seek(to: resumeAt, toleranceBefore: .zero, toleranceAfter: .zero)
            self.store = store
            self.editable = editable
            renderSize = editable.renderSize
            hasCamera = editable.hasCamera
            duration = editable.composition.duration.seconds
            loadError = nil
        } catch {
            Self.log.error("Load failed: \(error.localizedDescription)")
            loadError = error.localizedDescription
        }
    }

    // MARK: Playback

    func togglePlay() {
        if player.rate != 0 {
            player.pause()
        } else {
            if currentTime >= duration - 0.05 { player.seek(to: .zero) }
            player.play()
        }
        isPlaying = player.rate != 0
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Overlay

    func setVisible(_ visible: Bool) { apply(overlay.with(visible: visible)) }

    func setMirrored(_ mirrored: Bool) { apply(overlay.with(mirrored: mirrored)) }

    func setStyle(_ style: BubbleStyle, commit: Bool = true) {
        BubbleStyleStore.style = style // becomes the default for the next recording too
        apply(overlay.with(style: style), persist: commit)
    }

    func setPlacement(_ placement: OverlayPlacement) {
        let current = currentBubbleState?.center ?? overlay.fixedCenter
        apply(placement == .fixed ? overlay.with(placement: .fixed).with(fixedCenter: current) : overlay.with(placement: placement))
    }

    func setDiameter(_ diameter: Double, commit: Bool) {
        apply(overlay.with(diameterOverride: diameter), persist: commit)
    }

    /// Dragging the bubble in the preview pins it to that spot.
    func moveBubble(toCenter center: CGPoint, commit: Bool) {
        let pinned = overlay
            .with(placement: .fixed)
            .with(fixedCenter: center)
            .with(diameterOverride: overlay.diameterOverride ?? currentDiameter)
        apply(pinned, persist: commit)
    }

    private func apply(_ settings: OverlaySettings, persist: Bool = true) {
        project = project.with(overlay: settings)
        store.update(settings)
        refreshPausedFrame()
        if persist { save() }
    }

    /// AVPlayer only re-runs the compositor for new frames; nudge it while paused.
    private func refreshPausedFrame() {
        guard player.rate == 0, let item = player.currentItem, let composition = editable?.videoComposition else { return }
        item.videoComposition = composition.mutableCopy() as? AVVideoComposition
    }

    private func save() {
        do {
            try project.save(to: folder)
        } catch {
            Self.log.error("Save failed: \(error.localizedDescription)")
            Alerts.show(error)
        }
    }

    // MARK: Face-cam sources (post-recording)

    /// Records your camera while the screen recording plays back, then overlays it.
    func startFaceCamTake() async {
        guard !isRecordingTake else { return }
        guard await CameraCapture.requestAccess(audio: true) else {
            Alerts.show(CaptureError.permissionDenied("Camera and Microphone"))
            return
        }
        let capture = CameraCapture()
        var bubble: CameraBubbleController?
        do {
            try capture.configure(includeAudio: true)
            // Preview layer first, then start the camera (see CameraCapture's threading rule).
            let preview = CameraBubbleController(session: capture.session, within: (NSScreen.main ?? NSScreen.screens[0]).visibleFrame)
            preview.show()
            bubble = preview
            await capture.startRunning()
            let videoStart = currentTime >= duration - 0.5 ? 0 : currentTime
            await player.seek(to: CMTime(seconds: videoStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            let url = folder.appendingPathComponent("camera-take-\(Int(Date().timeIntervalSince1970)).mov")
            let cameraStart = try await capture.startRecording(to: url)
            player.isMuted = true // keep playback audio out of your mic
            player.play()
            let playStart = CACurrentMediaTime()
            take = FaceCamTake(capture: capture, bubble: preview, url: url, offset: videoStart - (playStart - cameraStart))
            isRecordingTake = true
        } catch {
            CameraBubbleController.tearDown(bubble, camera: capture)
            Alerts.show(error)
        }
    }

    func stopFaceCamTake() async {
        guard let take else { return }
        self.take = nil
        isRecordingTake = false
        player.pause()
        player.isMuted = false
        defer { CameraBubbleController.tearDown(take.bubble, camera: take.capture) }
        do {
            let url = try await take.capture.stopRecording()
            await useCamera(CameraSource(file: url.lastPathComponent, offset: take.offset, includeAudio: true))
        } catch {
            Alerts.show(error)
        }
    }

    func importFaceVideo() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.prompt = "Add Face Cam"
        panel.message = "Choose a video of your face. It starts at the beginning of the recording."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let destination = folder.appendingPathComponent("camera-imported-\(Int(Date().timeIntervalSince1970)).\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            await useCamera(CameraSource(file: destination.lastPathComponent, offset: 0, includeAudio: true))
        } catch {
            Alerts.show(error)
        }
    }

    func removeFaceCam() async {
        project = project.with(camera: nil)
        save()
        await load()
    }

    private func useCamera(_ source: CameraSource) async {
        let placement: OverlayPlacement = hasRecordedPath ? overlay.placement : .fixed
        project = project.with(camera: source).with(overlay: overlay.with(visible: true).with(placement: placement))
        save()
        await load()
    }

    // MARK: Export

    func export() async {
        guard let editable, !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = folder.lastPathComponent + ".mp4"
        panel.directoryURL = folder.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }

        player.pause()
        exportProgress = 0
        defer { exportProgress = nil }
        do {
            try await Exporter.export(editable, to: url) { [weak self] value in self?.exportProgress = value }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Self.log.error("Export failed: \(error.localizedDescription)")
            Alerts.show(error)
        }
    }

    func tearDown() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        if let take {
            CameraBubbleController.tearDown(take.bubble, camera: take.capture)
            self.take = nil
        }
        player.replaceCurrentItem(with: nil)
    }
}
