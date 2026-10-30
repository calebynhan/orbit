import AppKit
import AVFoundation
import OrbitCore
import SwiftUI

/// First-run guide. One picture, one line, one button per step. Reopenable from the menu.
@MainActor
final class WelcomeWindowController: NSWindowController {
    static let size = CGSize(width: 520, height: 560)
    private let model: WelcomeModel

    init(model: WelcomeModel) {
        self.model = model
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Orbit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(Theme.bg)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: WelcomeView(model: model))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Near-black ground, white type, record red. Nothing else.
enum Theme {
    static let bg = Color(white: 0.07)
    static let panel = Color.white.opacity(0.07)
    static let panelLine = Color.white.opacity(0.12)
    static let text = Color.white
    static let muted = Color.white.opacity(0.5)
    static let rec = Color(red: 1.0, green: 0.30, blue: 0.32)
    static let ok = Color(red: 0.36, green: 0.84, blue: 0.56)
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
        VStack(spacing: 0) {
            Spacer(minLength: 36)
            picture
                .frame(width: 400, height: 250)
                .id(model.step)
                .transition(.opacity)
            Spacer(minLength: 0)
            caption
                .padding(.top, 8)
            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 28)
        .frame(width: WelcomeWindowController.size.width, height: WelcomeWindowController.size.height)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var picture: some View {
        switch model.step {
        case .intro: MockRecording(drifting: true)
        case .permissions: PermissionTiles(model: model)
        case .shortcut: ShortcutPicture(model: model)
        case .howTo: CaptureBarPicture(shortcut: model.shortcut)
        }
    }

    @ViewBuilder private var caption: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 24, weight: .semibold))
            if let line = subtitle {
                Text(line).font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: model.step)
    }

    private var title: String {
        switch model.step {
        case .intro: "Orbit"
        case .permissions: "Allow"
        case .shortcut: "Your shortcut"
        case .howTo: "Press \(model.shortcut.displayString)"
        }
    }

    private var subtitle: String? {
        switch model.step {
        case .intro: "Your face, anywhere. Even after you stop."
        case .permissions: nil
        case .shortcut: model.shortcutError ?? (model.isRecordingShortcut ? "Press keys" : "Click the box")
        case .howTo: "Opens the bar. Press again to stop."
        }
    }

    private var footer: some View {
        HStack {
            if model.step != .intro {
                Button { model.back() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(GhostButtonStyle())
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(WelcomeModel.Step.allCases, id: \.rawValue) { s in
                    Circle().fill(s == model.step ? Theme.text : Theme.panelLine).frame(width: 6, height: 6)
                }
            }
            Spacer()
            Button(model.step == .howTo ? "Done" : "Continue") { model.next() }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: Pictures

/// A mock window on a desktop with the face circle drifting over it.
private struct MockRecording: View {
    let drifting: Bool
    @State private var drift = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.49, blue: 0.98), Color(red: 0.49, green: 0.23, blue: 0.93)], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 10) {
                ForEach([0.6, 0.85, 0.45, 0.7], id: \.self) { w in
                    Capsule().fill(Color.black.opacity(0.15)).frame(width: 260 * w, height: 9)
                }
                Capsule().fill(Theme.rec).frame(width: 96, height: 26).padding(.top, 6)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.94)).shadow(radius: 12, y: 8))
            .padding(.top, 34).padding(.leading, 40)
            HStack(spacing: 6) {
                Circle().fill(Theme.rec).frame(width: 7, height: 7)
                Text("REC").font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .padding(12)
            FaceCircle()
                .frame(width: 84, height: 84)
                .offset(x: drift ? 280 : 90, y: drift ? 140 : 56)
        }
        .onAppear {
            guard drifting else { return }
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

private struct FaceCircle: View {
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0.42), Color(red: 1, green: 0.48, blue: 0.35)], startPoint: .top, endPoint: .bottom))
            Circle().fill(Color(red: 0.96, green: 0.84, blue: 0.76)).frame(width: 26, height: 26).offset(y: -12)
            Circle().fill(Color(red: 0.96, green: 0.84, blue: 0.76)).frame(width: 50, height: 50).offset(y: 34)
        }
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 3))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
    }
}

/// Three tappable tiles: camera, mic, screen. A tick replaces the icon once granted.
private struct PermissionTiles: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        HStack(spacing: 14) {
            tile("camera.fill", "Camera", model.camera) { model.request(.camera) }
            tile("mic.fill", "Microphone", model.microphone) { model.request(.microphone) }
            tile("rectangle.inset.filled.badge.record", "Screen", model.screen) { model.request(.screen) }
        }
        .onAppear { model.refreshPermissions() }
    }

    private func tile(_ icon: String, _ name: String, _ status: WelcomeModel.Status, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(status == .granted ? Theme.ok.opacity(0.18) : Color.white.opacity(0.08)).frame(width: 64, height: 64)
                    Image(systemName: status == .granted ? "checkmark" : icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(status == .granted ? Theme.ok : status == .denied ? Theme.rec : Theme.text)
                }
                Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(status == .granted ? Theme.muted : Theme.text)
            }
            .frame(width: 118, height: 150)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(status == .granted ? Theme.ok.opacity(0.4) : Theme.panelLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(status == .granted)
        .help(status == .denied ? "Open System Settings" : "Allow \(name)")
    }
}

/// The key recorder, big, with the macOS takeover as a single button when it applies.
private struct ShortcutPicture: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        VStack(spacing: 18) {
            ShortcutRecorder(shortcut: $model.shortcut, isRecording: $model.isRecordingShortcut)
                .frame(width: 260, height: 96)
            if model.needsSystemShortcutTakeover {
                Button("Take ⇧⌘5 from macOS") { model.takeOverShortcut() }
                    .buttonStyle(GhostButtonStyle())
                    .help("Turns off the macOS screenshot-bar shortcut. ⇧⌘3 and ⇧⌘4 keep working. Undo from Orbit's menu.")
            } else if !model.shortcut.isMacOSScreenshotShortcut {
                Button("Use ⇧⌘5") { model.shortcut = .default; model.shortcutError = nil }
                    .buttonStyle(GhostButtonStyle())
            }
        }
    }
}

/// A drawing of Orbit's capture bar, with the Record button pulsing.
private struct CaptureBarPicture: View {
    let shortcut: OrbitCore.KeyboardShortcut
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 22) {
            Text(shortcut.displayString)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.panelLine, lineWidth: 1))
            Image(systemName: "arrow.down").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                barItem("rectangle.inset.filled.badge.record")
                barItem("rectangle.dashed.badge.record")
                Rectangle().fill(Theme.panelLine).frame(width: 1, height: 22)
                barItem("person.crop.circle.fill")
                barItem("mic.fill")
                Rectangle().fill(Theme.panelLine).frame(width: 1, height: 22)
                Text("Record")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.rec.opacity(pulse ? 1 : 0.7)))
            }
            .font(.system(size: 16))
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.panelLine, lineWidth: 1))
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true } }
    }

    private func barItem(_ icon: String) -> some View {
        Image(systemName: icon).frame(width: 26)
    }
}

// MARK: Buttons

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 22).padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.8 : 1)))
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(Theme.text.opacity(configuration.isPressed ? 0.6 : 0.9))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Capsule().fill(Theme.panel))
            .overlay(Capsule().stroke(Theme.panelLine, lineWidth: 1))
    }
}
