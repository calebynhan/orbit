import CoreGraphics
import Foundation

public enum OverlayPlacement: String, Codable, Sendable, CaseIterable {
    /// Replay the path you dragged the bubble along while recording.
    case followRecording
    /// Pin the bubble at one spot for the whole video.
    case fixed
}

/// Editable face-cam overlay options. Value type; every change returns a copy.
public struct OverlaySettings: Codable, Equatable, Sendable {
    public static let defaultDiameter = 0.24
    public static let `default` = OverlaySettings(
        visible: true,
        placement: .followRecording,
        fixedCenter: CGPoint(x: 0.1, y: 0.82),
        diameterOverride: nil,
        mirrored: true
    )

    public let visible: Bool
    public let placement: OverlayPlacement
    public let fixedCenter: CGPoint
    /// When set, replaces the recorded size.
    public let diameterOverride: Double?
    public let mirrored: Bool

    public init(visible: Bool, placement: OverlayPlacement, fixedCenter: CGPoint, diameterOverride: Double?, mirrored: Bool) {
        self.visible = visible
        self.placement = placement
        self.fixedCenter = fixedCenter
        self.diameterOverride = diameterOverride
        self.mirrored = mirrored
    }

    public func with(visible: Bool) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored)
    }

    public func with(placement: OverlayPlacement) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored)
    }

    public func with(fixedCenter: CGPoint) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored)
    }

    public func with(diameterOverride: Double?) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored)
    }

    public func with(mirrored: Bool) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored)
    }

    /// Resolved bubble state at a point in the video, or `nil` when hidden.
    public func state(at time: Double, track: BubbleTrack) -> BubbleState? {
        guard visible else { return nil }
        let recorded = track.state(at: time)
        let center = (placement == .followRecording ? recorded?.center : nil) ?? fixedCenter
        let diameter = diameterOverride ?? recorded?.diameter ?? Self.defaultDiameter
        return BubbleState(center: center, diameter: diameter)
    }
}

public struct CameraSource: Codable, Equatable, Sendable {
    /// File name inside the project folder.
    public let file: String
    /// Screen-timeline time at which camera time 0 occurs.
    public let offset: Double
    /// Mix the clip's own audio into the export (post-recorded or imported takes).
    public let includeAudio: Bool

    public init(file: String, offset: Double, includeAudio: Bool) {
        self.file = file
        self.offset = offset
        self.includeAudio = includeAudio
    }
}

public enum RecordingProjectError: Error, Equatable, LocalizedError {
    case notAProject(URL)
    case unreadable(URL, String)
    case unsafeFileReference(String)

    public var errorDescription: String? {
        switch self {
        case .notAProject(let url): "“\(url.lastPathComponent)” isn’t an Orbit recording (no project.json)."
        case .unreadable(let url, let reason): "Couldn’t read “\(url.lastPathComponent)”: \(reason)"
        case .unsafeFileReference(let name): "This recording points at a file outside its folder (“\(name)”), so Orbit won’t open it."
        }
    }
}

/// A recording on disk: a folder holding the raw screen file, an optional camera file,
/// and `project.json` describing how to composite them.
public struct RecordingProject: Codable, Equatable, Sendable {
    public static let fileName = "project.json"
    public static let currentVersion = 1
    /// Frame rates accepted from `project.json`; anything else is refused at load.
    public static let supportedFrameRates = 1...240

    public let version: Int
    public let createdAt: Date
    public let screenFile: String
    public let camera: CameraSource?
    public let overlay: OverlaySettings
    public let bubbleTrack: BubbleTrack
    /// Capture frame rate; the editor renders and exports at exactly this rate. `nil` in older projects.
    public let framesPerSecond: Int?

    public init(
        version: Int = RecordingProject.currentVersion,
        createdAt: Date,
        screenFile: String,
        camera: CameraSource?,
        overlay: OverlaySettings,
        bubbleTrack: BubbleTrack,
        framesPerSecond: Int? = nil
    ) {
        self.version = version
        self.createdAt = createdAt
        self.screenFile = screenFile
        self.camera = camera
        self.overlay = overlay
        self.bubbleTrack = bubbleTrack
        self.framesPerSecond = framesPerSecond
    }

    public func with(camera: CameraSource?) -> RecordingProject {
        RecordingProject(version: version, createdAt: createdAt, screenFile: screenFile, camera: camera, overlay: overlay, bubbleTrack: bubbleTrack, framesPerSecond: framesPerSecond)
    }

    public func with(overlay: OverlaySettings) -> RecordingProject {
        RecordingProject(version: version, createdAt: createdAt, screenFile: screenFile, camera: camera, overlay: overlay, bubbleTrack: bubbleTrack, framesPerSecond: framesPerSecond)
    }

    public func save(to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
    }

    public static func load(from folder: URL) throws -> RecordingProject {
        let url = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { throw RecordingProjectError.notAProject(folder) }
        let project: RecordingProject
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            project = try decoder.decode(RecordingProject.self, from: Data(contentsOf: url))
        } catch {
            throw RecordingProjectError.unreadable(url, error.localizedDescription)
        }
        try project.validate(in: folder)
        return project
    }

    /// A recording folder can come from someone else (a shared zip, a synced drive), so check
    /// everything `project.json` points at before any of it is opened.
    public func validate(in folder: URL) throws {
        _ = try Self.fileURL(screenFile, in: folder)
        if let camera { _ = try Self.fileURL(camera.file, in: folder) }
        if let framesPerSecond, !Self.supportedFrameRates.contains(framesPerSecond) {
            throw RecordingProjectError.unreadable(folder.appendingPathComponent(Self.fileName), "unsupported frame rate \(framesPerSecond)")
        }
    }

    /// Resolves a file name from `project.json` to a file directly inside `folder`. Refuses
    /// anything that could reach outside it: path separators, `.`/`..`, and symlinks that lead elsewhere.
    public static func fileURL(_ name: String, in folder: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw RecordingProjectError.unsafeFileReference(name)
        }
        let resolvedFolder = folder.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = resolvedFolder.appendingPathComponent(name, isDirectory: false)
        guard candidate.resolvingSymlinksInPath().deletingLastPathComponent().path == resolvedFolder.path else {
            throw RecordingProjectError.unsafeFileReference(name)
        }
        return candidate
    }

    public static func folderName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "'Recording' yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }
}
