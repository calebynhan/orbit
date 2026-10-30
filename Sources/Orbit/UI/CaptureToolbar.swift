import AppKit
import OrbitCore
import SwiftUI

/// The bottom-of-screen bar, modeled on the macOS ⌘⇧5 toolbar, plus a face-cam toggle.
@MainActor
final class CaptureToolbarController {
    private let panel: ToolbarPanel

    init(coordinator: RecordingCoordinator, on screen: NSScreen) {
        let hosting = NSHostingView(rootView: CaptureToolbarView(coordinator: coordinator))
        let size = hosting.fittingSize
        let visible = screen.visibleFrame
        let frame = CGRect(x: visible.midX - size.width / 2, y: visible.minY + 60, width: size.width, height: size.height)
        panel = ToolbarPanel(frame: frame, onCancel: { coordinator.cancel() })
        panel.contentView = hosting
    }

    func show() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() { panel.close() }
}

private final class ToolbarPanel: NSPanel {
    private let onCancel: () -> Void

    init(frame: CGRect, onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onCancel() }
}

struct CaptureToolbarView: View {
    @ObservedObject var coordinator: RecordingCoordinator

    var body: some View {
        HStack(spacing: 6) {
            ToolbarButton(systemImage: "xmark.circle.fill", label: nil, isOn: false) { coordinator.cancel() }
                .help("Close (Esc)")

            Divider().frame(height: 32)

            ToolbarButton(
                systemImage: "rectangle.inset.filled.badge.record",
                label: "Entire Screen",
                isOn: coordinator.captureMode == .entireScreen
            ) { coordinator.captureMode = .entireScreen }

            ToolbarButton(
                systemImage: "rectangle.dashed.badge.record",
                label: "Selected Portion",
                isOn: coordinator.captureMode == .selection
            ) { coordinator.captureMode = .selection }
                .help("Drag to draw an area. Drag inside to move it, or the edges to resize.")

            if coordinator.displays.count > 1 {
                Picker("", selection: $coordinator.selectedDisplayID) {
                    ForEach(coordinator.displays) { display in
                        Text(display.name).tag(display.id)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            Divider().frame(height: 32)

            ToolbarButton(
                systemImage: coordinator.cameraOn ? "person.crop.circle.fill" : "person.crop.circle",
                label: "Face Cam",
                isOn: coordinator.cameraOn
            ) { coordinator.toggleCamera() }
                .help("Show your camera in a draggable circle. You can also add or move it after recording.")

            ToolbarButton(
                systemImage: coordinator.microphoneOn ? "mic.fill" : "mic.slash",
                label: "Mic",
                isOn: coordinator.microphoneOn
            ) { coordinator.microphoneOn.toggle() }

            ToolbarButton(
                systemImage: coordinator.systemAudioOn ? "speaker.wave.2.fill" : "speaker.slash",
                label: "System Audio",
                isOn: coordinator.systemAudioOn
            ) { coordinator.systemAudioOn.toggle() }

            Divider().frame(height: 32)

            Menu {
                Picker("Resolution", selection: $coordinator.resolution) {
                    ForEach(OutputResolution.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Selection Shape", selection: $coordinator.aspect) {
                    ForEach(SelectionAspect.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Frame Rate", selection: $coordinator.framesPerSecond) {
                    ForEach(RecordingCoordinator.frameRates, id: \.self) { Text("\($0) fps").tag($0) }
                }
            } label: {
                Text("\(coordinator.resolution.label) · \(coordinator.framesPerSecond)fps")
                    .font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Resolution, selection shape, and frame rate")

            Button {
                coordinator.startRecording()
            } label: {
                Text("Record")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .disabled(coordinator.isBusy)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .environment(\.colorScheme, .dark)
    }
}

private struct ToolbarButton: View {
    let systemImage: String
    let label: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                    .frame(height: 22)
                if let label {
                    Text(label).font(.system(size: 9))
                }
            }
            .frame(minWidth: label == nil ? 28 : 64, minHeight: 40)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isOn ? Color.white.opacity(0.16) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
