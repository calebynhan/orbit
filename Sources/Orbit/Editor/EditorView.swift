import AVFoundation
import OrbitCore
import SwiftUI

struct EditorView: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(spacing: 0) {
            PreviewArea(model: model)
            TransportBar(model: model)
            Divider()
            OverlayControls(model: model)
                .disabled(model.isExporting || model.isRecordingTake)
        }
        .frame(minWidth: 760, minHeight: 520)
        .task { await model.load() }
    }
}

// MARK: Preview with draggable bubble handle

private struct PreviewArea: View {
    @ObservedObject var model: EditorModel
    @State private var dragStartCenter: CGPoint?
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let videoRect = OverlayGeometry.aspectFitRect(content: model.renderSize, in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                PlayerLayerView(player: model.player)
                if let state = model.currentBubbleState, !model.isRecordingTake {
                    handle(for: state, in: videoRect)
                }
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.loadError {
                    Text(error).foregroundStyle(.white).padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color.black)
    }

    private func handle(for state: BubbleState, in videoRect: CGRect) -> some View {
        let rect = OverlayGeometry.viewRect(for: state, videoRect: videoRect)
        return Circle()
            .strokeBorder(Color.white.opacity(isHovering || dragStartCenter != nil ? 0.9 : 0.25), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .contentShape(Circle())
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .onHover { isHovering = $0 }
            .help("Drag to move your face cam")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartCenter ?? CGPoint(x: rect.midX, y: rect.midY)
                        if dragStartCenter == nil { dragStartCenter = start }
                        let point = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                        model.moveBubble(toCenter: clampedCenter(point, in: videoRect), commit: false)
                    }
                    .onEnded { value in
                        let start = dragStartCenter ?? CGPoint(x: rect.midX, y: rect.midY)
                        let point = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                        model.moveBubble(toCenter: clampedCenter(point, in: videoRect), commit: true)
                        dragStartCenter = nil
                    }
            )
    }

    private func clampedCenter(_ point: CGPoint, in videoRect: CGRect) -> CGPoint {
        let center = OverlayGeometry.normalizedCenter(fromViewPoint: point, videoRect: videoRect)
        let aspect = videoRect.height > 0 ? videoRect.width / videoRect.height : 1
        return OverlayGeometry.clamped(BubbleState(center: center, diameter: model.currentDiameter), aspect: aspect).center
    }
}

private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerNSView { PlayerNSView(player: player) }

    func updateNSView(_ nsView: PlayerNSView, context: Context) {}
}

final class PlayerNSView: NSView {
    private let playerLayer: AVPlayerLayer

    init(player: AVPlayer) {
        playerLayer = AVPlayerLayer(player: player)
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

// MARK: Transport

private struct TransportBar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            Button { model.togglePlay() } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model.isRecordingTake)

            Slider(
                value: Binding(get: { model.currentTime }, set: { model.seek(to: $0) }),
                in: 0...max(model.duration, 0.01)
            )
            .disabled(model.isRecordingTake)

            Text("\(Self.format(model.currentTime)) / \(Self.format(model.duration))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(seconds.isFinite ? seconds : 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: Overlay controls

private struct OverlayControls: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.hasCamera {
                bubbleSettings
            } else {
                Text("No face cam yet. Record one while this video plays, or add a clip you already have.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                sourceButtons
                Spacer()
                exportButton
            }
        }
        .padding(14)
    }

    private var bubbleSettings: some View {
        HStack(spacing: 18) {
            Toggle("Face cam", isOn: Binding(get: { model.overlay.visible }, set: { model.setVisible($0) }))
                .toggleStyle(.switch)

            Picker("Position", selection: Binding(get: { model.overlay.placement }, set: { model.setPlacement($0) })) {
                Text("Follow my recording").tag(OverlayPlacement.followRecording)
                Text("Pinned").tag(OverlayPlacement.fixed)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            .disabled(!model.hasRecordedPath)
            .help(model.hasRecordedPath ? "Replay where you dragged the bubble while recording, or pin it in one spot." : "Drag the bubble in the preview to place it.")

            HStack {
                Text("Size")
                Slider(
                    value: Binding(get: { model.currentDiameter }, set: { model.setDiameter($0, commit: false) }),
                    in: EditorModel.diameterRange,
                    onEditingChanged: { editing in if !editing { model.setDiameter(model.currentDiameter, commit: true) } }
                )
                .frame(width: 140)
            }

            Toggle("Mirror", isOn: Binding(get: { model.overlay.mirrored }, set: { model.setMirrored($0) }))
        }
        .disabled(!model.overlay.visible && false)
    }

    @ViewBuilder
    private var sourceButtons: some View {
        if model.isRecordingTake {
            Button(role: .destructive) {
                Task { await model.stopFaceCamTake() }
            } label: {
                Label("Stop Face Cam Recording", systemImage: "stop.circle.fill")
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                Task { await model.startFaceCamTake() }
            } label: {
                Label(model.hasCamera ? "Re-record Face Cam" : "Record Face Cam", systemImage: "record.circle")
            }
            .help("Plays the recording (muted) and records your camera and mic alongside it.")

            Button {
                Task { await model.importFaceVideo() }
            } label: {
                Label("Add Video…", systemImage: "person.crop.circle.badge.plus")
            }

            if model.hasCamera {
                Button("Remove Face Cam") { Task { await model.removeFaceCam() } }
            }
        }
    }

    @ViewBuilder
    private var exportButton: some View {
        if let progress = model.exportProgress {
            ProgressView(value: progress) { Text("Exporting… \(Int(progress * 100))%") }
                .frame(width: 200)
        } else {
            Button {
                Task { await model.export() }
            } label: {
                Label("Export MP4…", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("e", modifiers: .command)
            .disabled(model.isLoading || model.loadError != nil)
        }
    }
}
