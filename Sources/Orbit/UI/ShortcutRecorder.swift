import AppKit
import OrbitCore
import SwiftUI

/// A field that captures the next key combination pressed and reports it as a `OrbitCore.KeyboardShortcut`.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: OrbitCore.KeyboardShortcut
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCapture = { captured in
            shortcut = captured
            isRecording = false
        }
        view.onRecordingChange = { isRecording = $0 }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.display(shortcut, recording: isRecording)
        if isRecording, view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) }
    }
}

final class RecorderView: NSView {
    var onCapture: ((OrbitCore.KeyboardShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var isRecording = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1.5
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 20, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            heightAnchor.constraint(equalToConstant: 56),
        ])
        toolTip = "Click, then press the keys you want to use"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 220, height: 56) }

    func display(_ shortcut: OrbitCore.KeyboardShortcut, recording: Bool) {
        isRecording = recording
        label.stringValue = recording ? "Press keys…" : shortcut.displayString
        // Styled for the dark welcome guide (see Theme).
        let accent = NSColor(red: 0.31, green: 0.49, blue: 1.0, alpha: 1)
        label.textColor = recording ? NSColor.white.withAlphaComponent(0.6) : .white
        layer?.borderColor = (recording ? accent : NSColor.white.withAlphaComponent(0.14)).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(recording ? 0.10 : 0.06).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onRecordingChange?(true)
    }

    override func becomeFirstResponder() -> Bool {
        onRecordingChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        onRecordingChange?(false)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        if event.keyCode == 53 { // Escape cancels
            window?.makeFirstResponder(nil)
            return
        }
        var modifiers: OrbitCore.KeyboardShortcut.Modifiers = []
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        onCapture?(OrbitCore.KeyboardShortcut(keyCode: Int(event.keyCode), modifiers: modifiers))
        window?.makeFirstResponder(nil)
    }

    // Swallow ⌘-combos so the menu bar doesn't eat them while recording.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        keyDown(with: event)
        return true
    }
}
