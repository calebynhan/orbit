import AppKit
import AVFoundation
import OrbitCore
import SwiftUI

/// First-run guide: what Orbit does, permissions, shortcut, how to record. Reopenable from the menu.
@MainActor
final class WelcomeWindowController: NSWindowController {
    static let size = CGSize(width: 760, height: 520)
    private let model: WelcomeModel

    init(model: WelcomeModel) {
        self.model = model
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Orbit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Theme.bg)
        window.appearance = NSAppearance(named: .darkAqua) // the guide is a single, dark design
        window.contentView = NSHostingView(rootView: WelcomeView(model: model))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// The guide's palette. Deep navy ground, one electric-blue accent, record red only for the record dot.
enum Theme {
    static let bg = Color(red: 0.055, green: 0.075, blue: 0.125)
    static let bgTop = Color(red: 0.10, green: 0.14, blue: 0.24)
    static let panel = Color.white.opacity(0.06)
    static let panelLine = Color.white.opacity(0.10)
    static let text = Color.white
    static let muted = Color.white.opacity(0.62)
    static let accent = Color(red: 0.31, green: 0.49, blue: 1.0)
    static let rec = Color(red: 1.0, green: 0.36, blue: 0.38)
    static let ok = Color(red: 0.33, green: 0.86, blue: 0.56)
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
    var allPermissionsGranted: Bool { camera == .granted && microphone == .granted && screen == .granted }

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
        if let following = Step(rawValue: step.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.25)) { step = following }
        } else {
            finish()
        }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.25)) { step = previous }
        }
    }

    func finish() { onFinish(shortcut) }

    private static func status(_ s: AVAuthorizationStatus) -> Status {
        switch s {
        case .authorized: .granted
        case .denied, .restricted: .denied
        default: .unknown
        }
    }
}

// MARK: - View

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        HStack(spacing: 0) {
            SidePanel(step: model.step)
                .frame(width: 300)
            VStack(alignment: .leading, spacing: 0) {
                ProgressStrip(current: model.step)
                    .padding(.top, 40)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 28)
                    .id(model.step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                footer
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 28)
        }
        .frame(width: WelcomeWindowController.size.width, height: WelcomeWindowController.size.height)
        .background(
            LinearGradient(colors: [Theme.bgTop, Theme.bg], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .intro: IntroStep()
        case .permissions: PermissionsStep(model: model)
        case .shortcut: ShortcutStep(model: model)
        case .howTo: HowToStep(shortcut: model.shortcut)
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.step != .intro {
                Button("Back") { model.back() }
                    .buttonStyle(GhostButtonStyle())
            }
            Spacer()
            Button(model.step == .howTo ? "Start using Orbit" : "Continue") { model.next() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: Side panel: brand + a drifting face circle over a mock screen

private struct SidePanel: View {
    let step: WelcomeModel.Step
    @State private var drift = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black.opacity(0.22))
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Circle().fill(Theme.rec).frame(width: 11, height: 11)
                        .shadow(color: Theme.rec.opacity(0.7), radius: 6)
                    Text("Orbit").font(.system(size: 19, weight: .bold))
                }
                .padding(.top, 44)
                Spacer()
                mock
                Spacer()
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut(duration: 0.25), value: step)
                    .padding(.bottom, 34)
            }
            .padding(.horizontal, 28)
        }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.panelLine).frame(width: 1) }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private var caption: String {
        switch step {
        case .intro: "Your face in a circle you can drag anywhere, during the recording or after it."
        case .permissions: "Permissions are only used while you record. Nothing is sent anywhere."
        case .shortcut: "One shortcut opens the capture bar and stops the recording."
        case .howTo: "Recordings open in an editor where the circle is still movable."
        }
    }

    private var mock: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.49, blue: 0.98), Color(red: 0.49, green: 0.23, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 170)
            // the "document" being recorded
            VStack(alignment: .leading, spacing: 7) {
                ForEach([0.62, 0.84, 0.48, 0.70], id: \.self) { w in
                    Capsule().fill(Color.black.opacity(0.18)).frame(width: 170 * w, height: 7)
                }
                Capsule().fill(Theme.rec).frame(width: 74, height: 20).padding(.top, 4)
                    .overlay(Text("Ship it").font(.system(size: 10, weight: .semibold)))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.92)).shadow(radius: 10, y: 6))
            .padding(.top, 22).padding(.leading, 22)
            .foregroundStyle(.white)
            // REC pill
            HStack(spacing: 6) {
                Circle().fill(Theme.rec).frame(width: 6, height: 6)
                Text("REC").font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(8)
            // the face circle, drifting
            FaceCircle()
                .frame(width: 58, height: 58)
                .offset(x: drift ? 160 : 60, y: drift ? 92 : 30)
        }
        .frame(width: 244, height: 170)
    }
}

private struct FaceCircle: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0.42), Color(red: 1, green: 0.48, blue: 0.35)], startPoint: .top, endPoint: .bottom))
            Circle().fill(Color(red: 0.96, green: 0.84, blue: 0.76)).frame(width: 18, height: 18).offset(y: -8)
            Circle().fill(Color(red: 0.96, green: 0.84, blue: 0.76)).frame(width: 34, height: 34).offset(y: 24)
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
        .overlay(Circle().stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).padding(-6))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

// MARK: Progress

private struct ProgressStrip: View {
    let current: WelcomeModel.Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(WelcomeModel.Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= current.rawValue ? Theme.accent : Theme.panelLine)
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: current)
            }
        }
        .frame(width: 160)
    }
}

// MARK: Steps

private struct StepTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(Theme.accent)
            Text(title).font(.system(size: 28, weight: .bold))
            Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IntroStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepTitle(eyebrow: "Welcome", title: "Record your screen. Put your face anywhere.",
                      subtitle: "Orbit keeps the camera separate from the screen, so the circle can move during the recording and after it. Nothing is uploaded; everything stays on this Mac.")
            VStack(alignment: .leading, spacing: 10) {
                FactRow(icon: "menubar.arrow.up.rectangle", text: "Orbit lives in the menu bar (⏺ at the top right). There is no Dock icon.")
                FactRow(icon: "folder", text: "Recordings are saved to ~/Movies/Orbit.")
                FactRow(icon: "lock", text: "No account. No upload. No analytics.")
            }
        }
    }
}

private struct FactRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent).frame(width: 20)
            Text(text).font(.system(size: 13.5)).foregroundStyle(Theme.text.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PermissionsStep: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(eyebrow: "Step 1 of 3", title: "Allow three things",
                      subtitle: "macOS asks for these the first time you record. Doing it now means your first recording just works.")
            VStack(spacing: 8) {
                PermissionCard(name: "Camera", detail: "Shows your face in the circle.", status: model.camera) { model.request(.camera) }
                PermissionCard(name: "Microphone", detail: "Records your voice.", status: model.microphone) { model.request(.microphone) }
                PermissionCard(name: "Screen Recording", detail: "Captures the screen. macOS may ask you to quit and reopen Orbit.", status: model.screen) { model.request(.screen) }
            }
            if model.allPermissionsGranted {
                Label("All set.", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.ok).font(.system(size: 13, weight: .medium))
            } else {
                Text("You can change any of these later in System Settings → Privacy & Security.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .onAppear { model.refreshPermissions() }
    }
}

private struct PermissionCard: View {
    let name: String
    let detail: String
    let status: WelcomeModel.Status
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(status == .granted ? Theme.ok.opacity(0.18) : Theme.panel).frame(width: 30, height: 30)
                Image(systemName: status == .granted ? "checkmark" : status == .denied ? "xmark" : icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(status == .granted ? Theme.ok : status == .denied ? Theme.rec : Theme.muted)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if status != .granted {
                Button(status == .denied ? "Open Settings" : "Allow", action: action)
                    .buttonStyle(SmallPillButtonStyle())
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelLine, lineWidth: 1))
    }

    private var icon: String {
        switch name {
        case "Camera": "camera"
        case "Microphone": "mic"
        default: "rectangle.dashed.badge.record"
        }
    }
}

private struct ShortcutStep: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(eyebrow: "Step 2 of 3", title: "Pick your shortcut",
                      subtitle: "Press it anywhere to open the capture bar. Press it again to stop recording.")
            HStack(spacing: 12) {
                ShortcutRecorder(shortcut: $model.shortcut, isRecording: $model.isRecordingShortcut)
                    .fixedSize()
                if !model.shortcut.isMacOSScreenshotShortcut {
                    Button("Use ⇧⌘5") { model.shortcut = .default; model.shortcutError = nil }
                        .buttonStyle(GhostButtonStyle())
                }
            }
            Text(model.isRecordingShortcut ? "Press the keys now. Esc cancels." : "Click the box, then press the keys you want.")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            if let error = model.shortcutError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).foregroundStyle(Color(red: 1, green: 0.78, blue: 0.4))
            }
            if model.needsSystemShortcutTakeover {
                VStack(alignment: .leading, spacing: 10) {
                    Text("⇧⌘5 currently opens the macOS screenshot bar.").font(.system(size: 13, weight: .semibold))
                    Text("Orbit can switch that macOS shortcut off so ⇧⌘5 opens Orbit instead. ⇧⌘3 and ⇧⌘4 keep working, and you can give it back from Orbit's menu.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    Button("Use ⇧⌘5 for Orbit") { model.takeOverShortcut() }
                        .buttonStyle(SmallPillButtonStyle())
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelLine, lineWidth: 1))
            }
        }
    }
}

private struct HowToStep: View {
    let shortcut: OrbitCore.KeyboardShortcut

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(eyebrow: "Step 3 of 3", title: "You're ready",
                      subtitle: "Four things to know. The guide is always in the menu bar if you want it again.")
            VStack(alignment: .leading, spacing: 12) {
                HowToRow(n: 1, title: "Press \(shortcut.displayString).", detail: "The capture bar appears at the bottom of the screen.")
                HowToRow(n: 2, title: "Choose Entire Screen or Selected Portion.", detail: "Turn on Face Cam and drag the circle anywhere.")
                HowToRow(n: 3, title: "Click Record.", detail: "Press \(shortcut.displayString) again, or the red button in the menu bar, to stop.")
                HowToRow(n: 4, title: "Fix it in the editor.", detail: "Move or resize your face after recording, then Export MP4.")
            }
        }
    }
}

private struct HowToRow: View {
    let n: Int
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 24, height: 24).background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Buttons

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(Capsule().fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
            .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 6)
    }
}

struct SmallPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(Theme.text.opacity(configuration.isPressed ? 0.6 : 0.85))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Theme.panel))
            .overlay(Capsule().stroke(Theme.panelLine, lineWidth: 1))
    }
}
