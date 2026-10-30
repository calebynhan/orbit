import AppKit
import OrbitCore
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController {
    private let model: EditorModel

    init(folder: URL, project: RecordingProject) {
        model = EditorModel(folder: folder, project: project)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1100, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = folder.lastPathComponent
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func tearDown() { model.tearDown() }
}
