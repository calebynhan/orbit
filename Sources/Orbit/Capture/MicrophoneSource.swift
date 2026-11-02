@preconcurrency import AVFoundation

/// An audio input the user can record from.
struct MicrophoneSource: Identifiable, Hashable {
    let id: String // AVCaptureDevice.uniqueID
    let name: String

    /// Every microphone currently attached, built-in first.
    static func available() -> [MicrophoneSource] {
        let session = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        let defaultID = AVCaptureDevice.default(for: .audio)?.uniqueID
        return session.devices
            .map { MicrophoneSource(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { lhs, rhs in
                if lhs.id == defaultID { return true }
                if rhs.id == defaultID { return false }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// The device ID to record from: the chosen one if it's still plugged in, else the system default.
    static func resolve(_ chosenID: String?, among sources: [MicrophoneSource]) -> String? {
        if let chosenID, sources.contains(where: { $0.id == chosenID }) { return chosenID }
        return sources.first?.id ?? AVCaptureDevice.default(for: .audio)?.uniqueID
    }
}
