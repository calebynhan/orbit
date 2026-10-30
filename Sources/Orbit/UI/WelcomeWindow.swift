import AppKit
import AVFoundation
import OrbitCore
import SwiftUI

/// First-run guide: what Orbit does, permissions, shortcut, how to record. Reopenable from the menu.
@MainActor
final class WelcomeWindowController: NSWindowController {
    private let model: WelcomeModel

    init(model: WelcomeModel) {
        self.model = model
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Orbit"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WelcomeView(model: model))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

@MainActor
final class WelcomeModel: ObservableObject {
    enum Step: Int, CaseIterable { case intro, permissions, shortcut, howTo }
    enum Permission { case camera, microphone, screen }
    enum Status { case unknown, granted, denied }

    @Published var step: Step = .intro
    @Published var shortcut: OrbitCore.KeyboardShortcut
    @Published var isRecordingShortcut = false
    @Published var camera: Status = .unknown
    @Published var microphone: Status = .unknown
    @Published var screen: Status = .unknown
    @Published var macOSOwnsScreenshotShortcut = SystemShortcut.macOSOwnsCommandShift5
    @Published var shortcutError: String?

    /// Called with the chosen shortcut when the user finishes; the app registers it.
    let onFinish: (OrbitCore.KeyboardShortcut) -> Void
    /// Turns the macOS ⌘⇧5 shortcut off; returns an error message on failure.
    let takeOverSystemShortcut: () -> String?

    init(shortcut: OrbitCore.KeyboardShortcut, onFinish: @escaping (OrbitCore.KeyboardShortcut) -> Void, takeOverSystemShortcut: @escaping () -> String?) {
        self.shortcut = shortcut
        self.onFinish = onFinish
        self.takeOverSystemShortcut = takeOverSystemShortcut
        refreshPermissions()
    }

    var needsSystemShortcutTakeover: Bool { shortcut.isMacOSScreenshotShortcut && macOSOwnsScreenshotShortcut }

    func refreshPermissions() {
        camera = Self.status(AVCaptureDevice.authorizationStatus(for: .video))
        microphone = Self.status(AVCaptureDevice.authorizationStatus(for: .audio))
        screen = ScreenRecorder.hasPermission() ? .granted : .unknown
    }

    func request(_ permission: Permission) {
        switch permission {
        case .camera:
            Task { _ = await AVCaptureDevice.requestAccess(for: .video); refreshPermissions() }
        case .microphone:
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio); refreshPermissions() }
        case .screen:
            // Shows the system prompt and adds Orbit to the Screen Recording list. macOS applies it after a relaunch.
            _ = ScreenRecorder.requestPermission()
            if !ScreenRecorder.hasPermission(), let url = SettingsPane.screenRecording.url { NSWorkspace.shared.open(url) }
            refreshPermissions()
        }
    }

    func takeOverShortcut() {
        shortcutError = takeOverSystemShortcut()
        macOSOwnsScreenshotShortcut = SystemShortcut.macOSOwnsCommandShift5
    }

    func next() {
        if step == .shortcut, let problem = shortcut.validationProblem {
            shortcutError = problem.message
            return
        }
        shortcutError = nil
        if let following = Step(rawValue: step.rawValue + 1) { step = following } else { finish() }
    }

    func back() { if let previous = Step(rawValue: step.rawValue - 1) { step = previous } }

    func finish() { onFinish(shortcut) }

    private static func status(_ s: AVAuthorizationStatus) -> Status {
        switch s {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .intro: intro
                case .permissions: permissions
                case .shortcut: shortcutStep
                case .howTo: howTo
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 36)
            .padding(.top, 44)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(WelcomeModel.Step.allCases, id: \.rawValue) { s in
                        Circle().fill(s == model.step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if model.step != .intro { Button("Back") { model.back() } }
                Button(model.step == .howTo ? "Start using Orbit" : "Continue") { model.next() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 560, height: 520)
    }

    // MARK: Steps

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "record.circle").font(.system(size: 44)).foregroundStyle(.red)
            Text("Welcome to Orbit").font(.system(size: 30, weight: .bold))
            Text("Orbit records your screen with your face in a circle you can drag anywhere, during the recording or after it. Nothing is uploaded; everything stays on this Mac.")
                .font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Orbit lives in the menu bar (⏺ at the top right). It has no Dock icon.", systemImage: "menubar.arrow.up.rectangle")
                .padding(.top, 8)
            Label("Recordings are saved to ~/Movies/Orbit.", systemImage: "folder")
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Permissions").font(.system(size: 26, weight: .bold))
            Text("macOS asks for these the first time. Granting them now means your first recording just works.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            permissionRow("Camera", detail: "Shows your face in the circle.", status: model.camera) { model.request(.camera) }
            permissionRow("Microphone", detail: "Records your voice.", status: model.microphone) { model.request(.microphone) }
            permissionRow("Screen Recording", detail: "Captures the screen. macOS may ask you to quit and reopen Orbit after turning this on.", status: model.screen) { model.request(.screen) }
            Text("You can change any of these later in System Settings → Privacy & Security.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onAppear { model.refreshPermissions() }
    }

    private func permissionRow(_ name: String, detail: String, status: WelcomeModel.Status, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: status == .granted ? "checkmark.circle.fill" : status == .denied ? "xmark.circle.fill" : "circle")
                .foregroundStyle(status == .granted ? .green : status == .denied ? .red : .secondary)
                .font(.title3).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).fontWeight(.semibold)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if status != .granted {
                Button(status == .denied ? "Open Settings" : "Allow") { action() }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your shortcut").font(.system(size: 26, weight: .bold))
            Text("Press it anywhere to open Orbit's capture bar; press it again to stop recording.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                ShortcutRecorder(shortcut: $model.shortcut, isRecording: $model.isRecordingShortcut)
                    .fixedSize()
                Button("Use ⇧⌘5") { model.shortcut = .default; model.shortcutError = nil }
                    .disabled(model.shortcut.isMacOSScreenshotShortcut)
            }
            Text(model.isRecordingShortcut ? "Press the keys now. Esc to cancel." : "Click the box, then press the keys you want.")
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.shortcutError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
            if model.needsSystemShortcutTakeover {
                VStack(alignment: .leading, spacing: 8) {
                    Label("⇧⌘5 currently opens the macOS screenshot bar.", systemImage: "info.circle")
                    Text("Orbit can turn that macOS shortcut off so ⇧⌘5 opens Orbit instead. ⇧⌘3 and ⇧⌘4 keep working, and you can give it back from Orbit's menu.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Use ⇧⌘5 for Orbit") { model.takeOverShortcut() }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How to record").font(.system(size: 26, weight: .bold))
            howToStep(1, "Press \(model.shortcut.displayString).", "The capture bar appears at the bottom of the screen.")
            howToStep(2, "Pick what to record.", "Entire Screen or Selected Portion. Turn Face Cam on and drag the circle anywhere.")
            howToStep(3, "Click Record.", "Press \(model.shortcut.displayString) again, or the red button in the menu bar, to stop.")
            howToStep(4, "Fix it in the editor.", "Move or resize your face, even after recording. Then Export MP4.")
        }
    }

    private func howToStep(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(.system(size: 14, weight: .bold, design: .monospaced))
                .frame(width: 28, height: 28).background(Circle().fill(Color.accentColor)).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
