import CoreGraphics

/// Where the face-cam bubble sits, independent of resolution.
///
/// `center` is normalized to the recorded display with a **top-left** origin
/// (0,0 = top-left corner, 1,1 = bottom-right). `diameter` is a fraction of the display height.
public struct BubbleState: Codable, Equatable, Sendable {
    public let center: CGPoint
    public let diameter: Double

    public init(center: CGPoint, diameter: Double) {
        self.center = center
        self.diameter = diameter
    }

    func interpolated(to other: BubbleState, fraction t: Double) -> BubbleState {
        BubbleState(
            center: CGPoint(
                x: center.x + (other.center.x - center.x) * t,
                y: center.y + (other.center.y - center.y) * t
            ),
            diameter: diameter + (other.diameter - diameter) * t
        )
    }
}

public struct BubbleKeyframe: Codable, Equatable, Sendable {
    /// Seconds from the start of the screen recording.
    public let time: Double
    public let state: BubbleState

    public init(time: Double, state: BubbleState) {
        self.time = time
        self.state = state
    }
}

/// The path the bubble took while recording, sampled as keyframes.
public struct BubbleTrack: Codable, Equatable, Sendable {
    public let keyframes: [BubbleKeyframe]

    public init(keyframes: [BubbleKeyframe] = []) {
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    public var isEmpty: Bool { keyframes.isEmpty }

    public func appending(_ keyframe: BubbleKeyframe) -> BubbleTrack {
        BubbleTrack(keyframes: keyframes + [keyframe])
    }

    /// Bubble state at `time`, linearly interpolated between keyframes and held at the ends.
    public func state(at time: Double) -> BubbleState? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if time <= first.time { return first.state }
        if time >= last.time { return last.state }

        // Binary search for the last keyframe at or before `time`.
        var low = 0
        var high = keyframes.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if keyframes[mid].time <= time { low = mid } else { high = mid }
        }
        let a = keyframes[low]
        let b = keyframes[high]
        let span = b.time - a.time
        guard span > 0 else { return b.state }
        return a.state.interpolated(to: b.state, fraction: (time - a.time) / span)
    }
}

/// Builds a compact `BubbleTrack` from periodic samples: only changes become keyframes,
/// and a "hold" keyframe is inserted before a move so interpolation doesn't drift
/// across the time the bubble sat still.
public struct BubbleTrackRecorder: Sendable {
    public let track: BubbleTrack
    private let lastSample: BubbleKeyframe?

    public init() {
        self.init(track: BubbleTrack(), lastSample: nil)
    }

    private init(track: BubbleTrack, lastSample: BubbleKeyframe?) {
        self.track = track
        self.lastSample = lastSample
    }

    public func recording(_ state: BubbleState, at time: Double) -> BubbleTrackRecorder {
        let sample = BubbleKeyframe(time: time, state: state)
        guard let last = lastSample else {
            return BubbleTrackRecorder(track: track.appending(sample), lastSample: sample)
        }
        if last.state == state {
            return BubbleTrackRecorder(track: track, lastSample: sample)
        }
        return BubbleTrackRecorder(track: withHold(from: last).appending(sample), lastSample: sample)
    }

    /// The final track, including a hold keyframe at the last sample time.
    public func finished() -> BubbleTrack {
        guard let last = lastSample else { return track }
        return withHold(from: last)
    }

    private func withHold(from last: BubbleKeyframe) -> BubbleTrack {
        let lastKeyframeTime = track.keyframes.last?.time ?? -.infinity
        return last.time > lastKeyframeTime ? track.appending(last) : track
    }
}
