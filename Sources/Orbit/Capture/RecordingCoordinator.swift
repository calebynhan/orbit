import AppKit
import OrbitCore
import os
import QuartzCore

struct DisplayChoice: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
}

enum CaptureMode: String, CaseIterable {
    case entireScreen
    case selection
}

/// Drives a live recording: toolbar → (optional) area + camera bubble → screen + camera files → editor.
@MainActor
final class RecordingCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case choosing
        case recording(startedAt: Date)
        case finishing
    }

    static let frameRates = [30, 60]
    private static let log = Logger(subsystem: "dev.orbit.Orbit", category: "Recording")
    private static let sampleInterval: TimeInterval = 1.0 / 30
    private static let defaults = UserDefaults.standard

    @Published private(set) var phase: Phase = .idle
    @Published var cameraOn = defaults.object(forKey: "cameraOn") as? Bool ?? true {
        didSet { Self.defaults.set(cameraOn, forKey: "cameraOn") }
    }
    @Published var microphoneOn = defaults.object(forKey: "microphoneOn") as? Bool ?? true {
        didSet { Self.defaults.set(microphoneOn, forKey: "microphoneOn") }
    }
    @Published var systemAudioOn = defaults.bool(forKey: "systemAudioOn") {
        didSet { Self.defaults.set(systemAudioOn, forKey: "systemAudioOn") }
    }
    @Published var captureMode = CaptureMode(rawValue: defaults.string(forKey: "captureMode") ?? "") ?? .entireScreen {
        didSet {
            Self.defaults.set(captureMode.rawValue, forKey: "captureMode")
            refreshAreaOverlay()
        }
    }
    @Published var resolution = OutputResolution(rawValue: defaults.string(forKey: "resolution") ?? "") ?? .p1080 {
        didSet {
            Self.defaults.set(resolution.rawValue, forKey: "resolution")
            areaOverlay?.refreshLabel()
        }
    }
    @Published var aspect = SelectionAspect(rawValue: defaults.string(forKey: "aspect") ?? "") ?? .widescreen {
        didSet {
            Self.defaults.set(aspect.rawValue, forKey: "aspect")
            updateSelection(selection)
        }
    }
    @Published var framesPerSecond = (defaults.object(forKey: "framesPerSecond") as? Int).flatMap { frameRates.contains($0) ? $0 : nil } ?? 60 {
        didSet { Self.defaults.set(framesPerSecond, forKey: "framesPerSecond") }
    }
    @Published private(set) var displays: [DisplayChoice] = []
    @Published var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID() {
        didSet { if oldValue != selectedDisplayID { refreshAreaOverlay(rebuild: true) } }
    }

    var isBusy: Bool { phase == .finishing }
    var isRecording: Bool { if case .recording = phase { true } else { false } }

    /// Called with the finished project folder so the app can open the editor.
    var onFinished: ((URL) -> Void)?
    var onPhaseChange: ((Phase) -> Void)?

    private var toolbar: CaptureToolbarController?
    private var areaOverlay: AreaSelectionController?
    private var camera: CameraCapture?
    private var bubble: CameraBubbleController?
    private var screenRecorder: ScreenRecorder?
    private var sampler: Timer?
    private var trackRecorder = BubbleTrackRecorder()
    private var screenStartTime: CFTimeInterval = 0
    private var cameraStartTime: CFTimeInterval?
    private var projectFolder: URL?
    /// Global rect the bubble's position is normalized against (the recorded area).
    private var recordingArea: CGRect = .zero
    /// Selected portion in global AppKit points.
    private var selection: CGRect = NSRectFromString(defaults.string(forKey: "selection") ?? "")

    // MARK: Hotkey entry point

    func handleHotKey() {
        switch phase {
        case .idle: showToolbar()
        case .choosing: cancel()
        case .recording: stopRecording()
        case .finishing: break
        }
    }

    // MARK: Toolbar

    func showToolbar() {
        guard phase == .idle else { return }
        let screen = Self.screenUnderMouse()
        displays = NSScreen.screens.compactMap { screen in
            screen.displayID.map { DisplayChoice(id: $0, name: screen.localizedName) }
        }
        setPhase(.choosing)
        selectedDisplayID = screen.displayID ?? CGMainDisplayID() // rebuilds the overlay if the display changed
        refreshAreaOverlay()
        toolbar = CaptureToolbarController(coordinator: self, on: screen)
        toolbar?.show()
        if cameraOn { startCameraPreview() }
    }

    func cancel() {
        guard phase == .choosing else { return }
        toolbar?.close()
        toolbar = nil
        closeAreaOverlay()
        stopCameraPreview()
        setPhase(.idle)
    }

    func toggleCamera() {
        cameraOn.toggle()
        if cameraOn { startCameraPreview() } else { stopCameraPreview() }
    }

    /// Output pixel size for the current mode, display, and resolution.
    func outputSize(forPoints size: CGSize) -> PixelSize {
        resolution.pixelSize(forPoints: size, scale: Self.screen(for: selectedDisplayID).backingScaleFactor)
    }

    // MARK: Area selection

    private var selectedScreen: NSScreen { Self.screen(for: selectedDisplayID) }

    /// The area that will be recorded, in global AppKit points.
    private var captureArea: CGRect {
        captureMode == .selection ? selection : selectedScreen.frame
    }

    private func refreshAreaOverlay(rebuild: Bool = false) {
        guard phase == .choosing else { return }
        guard captureMode == .selection else {
            closeAreaOverlay()
            return
        }
        let display = selectedScreen.frame
        if rebuild || areaOverlay?.displayFrame != display { closeAreaOverlay() }
        let fitted = display.intersects(selection) && selection.width > 0
            ? SelectionGeometry.constrained(selection, aspect: aspect, anchor: .body, bounds: display)
            : SelectionGeometry.constrained(SelectionGeometry.defaultSelection(in: display), aspect: aspect, anchor: .body, bounds: display)
        storeSelection(fitted)
        if let areaOverlay {
            areaOverlay.update(selection: fitted, aspect: aspect)
        } else {
            let overlay = AreaSelectionController(
                displayFrame: display,
                selection: fitted,
                aspect: aspect,
                sizeLabel: { [weak self] size in self?.sizeLabel(forPoints: size) ?? "" },
                onChange: { [weak self] rect in self?.storeSelection(rect) }
            )
            overlay.show()
            areaOverlay = overlay
        }
        bubble?.keep(inside: fitted)
    }

    private func updateSelection(_ rect: CGRect) {
        guard captureMode == .selection, phase == .choosing else { return }
        let fitted = SelectionGeometry.constrained(rect, aspect: aspect, anchor: .body, bounds: selectedScreen.frame)
        storeSelection(fitted)
        areaOverlay?.update(selection: fitted, aspect: aspect)
    }

    private func storeSelection(_ rect: CGRect) {
        selection = rect
        Self.defaults.set(NSStringFromRect(rect), forKey: "selection")
    }

    private func sizeLabel(forPoints size: CGSize) -> String {
        let pixels = outputSize(forPoints: size)
        return "\(pixels.width) × \(pixels.height)"
    }

    private func closeAreaOverlay() {
        areaOverlay?.close()
        areaOverlay = nil
    }

    // MARK: Camera preview

    private func startCameraPreview() {
        guard camera == nil else { return }
        Task {
            guard await CameraCapture.requestAccess(audio: false) else {
                cameraOn = false
                Alerts.show(CaptureError.permissionDenied("Camera"))
                return
            }
            guard phase == .choosing, camera == nil, cameraOn else { return }
            do {
                let capture = CameraCapture()
                try capture.configure(includeAudio: false)
                // Preview layer first, then start the camera (see CameraCapture's threading rule).
                let area = captureMode == .selection ? selection : selectedScreen.visibleFrame
                let bubble = CameraBubbleController(session: capture.session, within: area)
                bubble.show()
                self.camera = capture
                self.bubble = bubble
                await capture.startRunning()
            } catch {
                cameraOn = false
                Alerts.show(error)
            }
        }
    }

    private func stopCameraPreview() {
        CameraBubbleController.tearDown(bubble, camera: camera)
        bubble = nil
        camera = nil
    }

    // MARK: Recording

    func startRecording() {
        guard phase == .choosing else { return }
        guard ScreenRecorder.hasPermission() || ScreenRecorder.requestPermission() else {
            Alerts.show(CaptureError.permissionDenied("Screen & System Audio Recording"), settingsPane: .screenRecording)
            return
        }
        Task { await beginRecording() }
    }

    private func beginRecording() async {
        if microphoneOn, await !AVCaptureAccess.microphone() {
            Alerts.show(CaptureError.permissionDenied("Microphone"))
            return
        }
        let startedAt = Date()
        let folder: URL
        do {
            folder = try Self.makeProjectFolder(for: startedAt)
        } catch {
            Alerts.show(error)
            return
        }

        let area = captureArea
        let display = selectedScreen.frame
        toolbar?.close()
        toolbar = nil
        areaOverlay?.showRecordingOutline()
        setPhase(.finishing)

        let recorder = ScreenRecorder()
        let options = ScreenRecordingOptions(
            displayID: selectedDisplayID,
            outputURL: folder.appendingPathComponent("screen.mov"),
            microphone: microphoneOn,
            systemAudio: systemAudioOn,
            framesPerSecond: Int32(framesPerSecond),
            sourceRect: captureMode == .selection ? SelectionGeometry.sourceRect(selection: area, display: display) : nil,
            outputSize: outputSize(forPoints: area.size)
        )
        do {
            screenStartTime = try await recorder.start(options)
            if let camera {
                cameraStartTime = try await camera.startRecording(to: folder.appendingPathComponent("camera.mov"))
            }
        } catch {
            Self.log.error("Couldn't start recording: \(error.localizedDescription)")
            try? await recorder.stop()
            closeAreaOverlay()
            stopCameraPreview()
            setPhase(.idle)
            Alerts.show(error)
            return
        }

        screenRecorder = recorder
        projectFolder = folder
        recordingArea = area
        trackRecorder = BubbleTrackRecorder()
        sampleBubble()
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleBubble() }
        }
        RunLoop.main.add(timer, forMode: .common) // keep sampling while the bubble is being dragged
        sampler = timer
        setPhase(.recording(startedAt: startedAt))
    }

    private func sampleBubble() {
        guard let bubble else { return }
        let state = OverlayGeometry.bubbleState(windowFrame: bubble.frame, displayFrame: recordingArea)
        trackRecorder = trackRecorder.recording(state, at: CACurrentMediaTime() - screenStartTime)
    }

    func stopRecording() {
        guard isRecording else { return }
        setPhase(.finishing)
        Task { await finishRecording() }
    }

    private func finishRecording() async {
        sampleBubble()
        sampler?.invalidate()
        sampler = nil

        var cameraFile: String?
        if let camera, cameraStartTime != nil {
            do {
                cameraFile = try await camera.stopRecording().lastPathComponent
            } catch {
                Self.log.error("Camera file failed: \(error.localizedDescription)")
            }
        }
        do {
            try await screenRecorder?.stop()
        } catch {
            Self.log.error("Screen recorder stop failed: \(error.localizedDescription)")
        }
        stopCameraPreview()
        closeAreaOverlay()

        guard let folder = projectFolder else {
            setPhase(.idle)
            return
        }
        let cameraSource = cameraFile.map { file in
            CameraSource(
                file: file,
                offset: CameraPlacement.offset(cameraStart: cameraStartTime ?? screenStartTime, screenStart: screenStartTime),
                includeAudio: false
            )
        }
        let project = RecordingProject(
            createdAt: Date(),
            screenFile: "screen.mov",
            camera: cameraSource,
            overlay: .default.with(placement: cameraSource == nil ? .fixed : .followRecording),
            bubbleTrack: trackRecorder.finished(),
            framesPerSecond: framesPerSecond
        )
        screenRecorder = nil
        projectFolder = nil
        cameraStartTime = nil
        setPhase(.idle)

        do {
            try project.save(to: folder)
            onFinished?(folder)
        } catch {
            Alerts.show(error)
        }
    }

    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        onPhaseChange?(newPhase)
    }

    // MARK: Helpers

    static var recordingsRoot: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Orbit", isDirectory: true)
    }

    private static func makeProjectFolder(for date: Date) throws -> URL {
        let folder = recordingsRoot.appendingPathComponent(RecordingProject.folderName(for: date), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func screen(for displayID: CGDirectDisplayID) -> NSScreen {
        NSScreen.screens.first { $0.displayID == displayID } ?? screenUnderMouse()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
