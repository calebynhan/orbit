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
        mirrored: true,
        style: .default
    )

    public let visible: Bool
    public let placement: OverlayPlacement
    public let fixedCenter: CGPoint
    /// When set, replaces the recorded size.
    public let diameterOverride: Double?
    public let mirrored: Bool
    public let style: BubbleStyle

    public init(visible: Bool, placement: OverlayPlacement, fixedCenter: CGPoint, diameterOverride: Double?, mirrored: Bool, style: BubbleStyle = .default) {
        self.visible = visible
        self.placement = placement
        self.fixedCenter = fixedCenter
        self.diameterOverride = diameterOverride
        self.mirrored = mirrored
        self.style = style
    }

    // Projects saved before `style` existed decode with the default look.
    private enum CodingKeys: String, CodingKey { case visible, placement, fixedCenter, diameterOverride, mirrored, style }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            visible: try c.decode(Bool.self, forKey: .visible),
            placement: try c.decode(OverlayPlacement.self, forKey: .placement),
            fixedCenter: try c.decode(CGPoint.self, forKey: .fixedCenter),
            diameterOverride: try c.decodeIfPresent(Double.self, forKey: .diameterOverride),
            mirrored: try c.decode(Bool.self, forKey: .mirrored),
            style: try c.decodeIfPresent(BubbleStyle.self, forKey: .style) ?? .default
        )
    }

    public func with(style: BubbleStyle) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored, style: style)
    }

    public func with(visible: Bool) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored, style: style)
    }

    public func with(placement: OverlayPlacement) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored, style: style)
    }

    public func with(fixedCenter: CGPoint) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored, style: style)
    }

    public func with(diameterOverride: Double?) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored, style: style)
    }

    public func with(mirrored: Bool) -> OverlaySettings {
        OverlaySettings(visible: visible, placement: placement, fixedCenter: fixedCenter, diameterOverride: diameterOverride, mirrored: mirrored, style: style)
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

    public var errorDescription: String? {
        switch self {
        case .notAProject(let url): "“\(url.lastPathComponent)” isn’t an Orbit recording (no project.json)."
        case .unreadable(let url, let reason): "Couldn’t read “\(url.lastPathComponent)”: \(reason)"
        }
    }
}

/// A recording on disk: a folder holding the raw screen file, an optional camera file,
/// and `project.json` describing how to composite them.
public struct RecordingProject: Codable, Equatable, Sendable {
    public static let fileName = "project.json"
    public static let currentVersion = 1

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
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(RecordingProject.self, from: Data(contentsOf: url))
        } catch {
            throw RecordingProjectError.unreadable(url, error.localizedDescription)
        }
    }

    public static func folderName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "'Recording' yyyy-MM-dd 'at' HH.mm.ss"
        return formatter.string(from: date)
    }
}
