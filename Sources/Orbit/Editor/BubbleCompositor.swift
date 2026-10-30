import AVFoundation
import CoreImage
import os
import OrbitCore

/// Thread-safe holder for the overlay settings the compositor reads on every frame,
/// so editor changes show up without rebuilding the composition.
final class OverlaySettingsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: OverlaySettings
    private let track: BubbleTrack

    init(settings: OverlaySettings, track: BubbleTrack) {
        self.settings = settings
        self.track = track
    }

    func update(_ newSettings: OverlaySettings) {
        lock.withLock { settings = newSettings }
    }

    func snapshot() -> (OverlaySettings, BubbleTrack) {
        lock.withLock { (settings, track) }
    }
}

/// Composition instruction carrying everything the compositor needs for one recording.
final class BubbleInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid

    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    let cameraTransform: CGAffineTransform
    /// Where the camera clip sits on the timeline; outside it AVFoundation would repeat the last frame.
    let cameraTimeRange: CMTimeRange
    let store: OverlaySettingsStore

    init(timeRange: CMTimeRange, screenTrackID: CMPersistentTrackID, cameraTrackID: CMPersistentTrackID?, cameraTransform: CGAffineTransform, cameraTimeRange: CMTimeRange, store: OverlaySettingsStore) {
        self.timeRange = timeRange
        self.screenTrackID = screenTrackID
        self.cameraTrackID = cameraTrackID
        self.cameraTransform = cameraTransform
        self.cameraTimeRange = cameraTimeRange
        self.store = store
        self.requiredSourceTrackIDs = ([screenTrackID] + (cameraTrackID.map { [$0] } ?? [])).map { NSNumber(value: $0) }
    }
}

/// Draws the screen frame, then the camera frame cropped into a white-ringed circle.
final class BubbleCompositor: NSObject, AVVideoCompositing {
    private static let log = Logger(subsystem: "dev.orbit.Orbit", category: "Compositor")
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private let renderQueue = DispatchQueue(label: "orbit.compositor", qos: .userInitiated)

    let sourcePixelBufferAttributes: [String: any Sendable]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
    let requiredPixelBufferAttributesForRenderContext: [String: any Sendable] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async {
            do {
                request.finish(withComposedVideoFrame: try Self.render(request))
            } catch {
                Self.log.error("Frame render failed: \(error.localizedDescription)")
                request.finish(with: error)
            }
        }
    }

    func cancelAllPendingVideoCompositionRequests() {}

    private enum RenderError: Error {
        case badInstruction, missingScreenFrame, noOutputBuffer
    }

    private static func render(_ request: AVAsynchronousVideoCompositionRequest) throws -> CVPixelBuffer {
        guard let instruction = request.videoCompositionInstruction as? BubbleInstruction else { throw RenderError.badInstruction }
        guard let screenBuffer = request.sourceFrame(byTrackID: instruction.screenTrackID) else { throw RenderError.missingScreenFrame }
        guard let output = request.renderContext.newPixelBuffer() else { throw RenderError.noOutputBuffer }

        let renderSize = request.renderContext.size
        let canvas = CGRect(origin: .zero, size: renderSize)
        let screen = CIImage(cvPixelBuffer: screenBuffer)
        let screenScaled = screen.transformed(by: CGAffineTransform(
            scaleX: renderSize.width / screen.extent.width,
            y: renderSize.height / screen.extent.height
        ))

        let (settings, track) = instruction.store.snapshot()
        let time = request.compositionTime.seconds
        var image = screenScaled
        if
            let cameraTrackID = instruction.cameraTrackID,
            instruction.cameraTimeRange.containsTime(request.compositionTime),
            let cameraBuffer = request.sourceFrame(byTrackID: cameraTrackID),
            let rawState = settings.state(at: time, track: track)
        {
            let state = OverlayGeometry.clamped(rawState, aspect: renderSize.width / renderSize.height)
            let rect = OverlayGeometry.renderRect(for: state, renderSize: renderSize)
            let camera = Self.circleContent(
                from: CIImage(cvPixelBuffer: cameraBuffer),
                transform: instruction.cameraTransform,
                mirrored: settings.mirrored,
                into: rect
            )
            image = Self.bubble(camera: camera, in: rect, style: settings.style).composited(over: screenScaled)
        }

        ciContext.render(image.cropped(to: canvas), to: output, bounds: canvas, colorSpace: colorSpace)
        return output
    }

    /// Orients the camera frame, crops it to a centered square, mirrors it, and fits it to `rect`.
    private static func circleContent(from frame: CIImage, transform: CGAffineTransform, mirrored: Bool, into rect: CGRect) -> CIImage {
        var image = frame.transformed(by: transform)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let crop = OverlayGeometry.centeredSquareCrop(of: image.extent.size)
        image = image.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        if mirrored {
            image = image.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -crop.width, y: 0))
        }
        let scale = rect.width / max(crop.width, 1)
        return image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }

    /// Camera inside the chosen shape with an outline around it, on a transparent background.
    private static func bubble(camera: CIImage, in rect: CGRect, style: BubbleStyle) -> CIImage {
        let outline = rect.width * style.outlineWidth
        let inner = rect.insetBy(dx: outline, dy: outline)
        let photo = camera.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: shapeMask(rect: inner, shape: style.shape),
        ])
        guard outline > 0 else { return photo }
        let c = style.outlineColor
        let ring = shapeMask(rect: rect, shape: style.shape)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: c.red),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: c.green),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: c.blue),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: c.alpha),
            ])
        return photo.composited(over: ring)
    }

    /// White inside the shape, transparent outside, antialiased edge.
    private static func shapeMask(rect: CGRect, shape: BubbleShape) -> CIImage {
        if shape == .circle {
            let radius = rect.width / 2
            return CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: rect.midX, y: rect.midY),
                "inputRadius0": max(radius - 1, 0),
                "inputRadius1": radius,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.clear,
            ])?.outputImage?.cropped(to: rect.insetBy(dx: -2, dy: -2)) ?? .empty()
        }
        return CIFilter(name: "CIRoundedRectangleGenerator", parameters: [
            "inputExtent": CIVector(cgRect: rect),
            "inputRadius": rect.width * shape.cornerRadiusFraction,
            "inputColor": CIColor.white,
        ])?.outputImage ?? .empty()
    }
}
