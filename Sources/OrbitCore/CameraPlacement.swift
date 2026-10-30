/// Where a face-cam clip lands on the screen recording's timeline.
public struct CameraPlacement: Equatable, Sendable {
    /// Seconds into the camera clip where the used segment begins.
    public let sourceStart: Double
    /// Seconds into the screen recording where that segment is placed.
    public let insertAt: Double
    public let duration: Double

    public init(sourceStart: Double, insertAt: Double, duration: Double) {
        self.sourceStart = sourceStart
        self.insertAt = insertAt
        self.duration = duration
    }

    /// - Parameter offset: screen-timeline time at which camera time 0 occurs (negative = camera started first).
    /// - Returns: `nil` when the clip doesn't overlap the screen recording at all.
    public static func compute(offset: Double, cameraDuration: Double, screenDuration: Double) -> CameraPlacement? {
        let sourceStart = max(0, -offset)
        let insertAt = max(0, offset)
        let duration = min(cameraDuration - sourceStart, screenDuration - insertAt)
        guard duration > 0 else { return nil }
        return CameraPlacement(sourceStart: sourceStart, insertAt: insertAt, duration: duration)
    }

    /// Offset between two host-clock start times (e.g. `CACurrentMediaTime()` captured at each start callback).
    public static func offset(cameraStart: Double, screenStart: Double) -> Double {
        cameraStart - screenStart
    }
}
