import AVFoundation

enum ExportError: LocalizedError {
    case cannotCreateSession

    var errorDescription: String? {
        "This video can’t be exported with the current settings."
    }
}

/// Renders the composited video (screen + face-cam bubble) to an .mp4.
enum Exporter {
    static func export(_ editable: EditableComposition, to url: URL, progress: @escaping @MainActor (Double) -> Void) async throws {
        guard let session = AVAssetExportSession(asset: editable.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.cannotCreateSession
        }
        session.videoComposition = editable.videoComposition
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        let monitor = Task {
            for await state in session.states(updateInterval: 0.2) {
                if case .exporting(let exportProgress) = state {
                    await progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { monitor.cancel() }
        try await session.export(to: url, as: .mp4)
        await progress(1)
    }
}
