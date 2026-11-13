import Foundation

/// Recorded aspect wins because a portrait take may still use a landscape
/// live-view transport raster. Encoded picture dimensions are the fallback.
public struct PreviewGeometry: Equatable, Sendable {
    public enum Orientation: Equatable, Sendable { case portrait, landscape }
    private var recordingAspect: Double?
    private var pictureAspect: Double?

    public init() {}

    public var orientation: Orientation? {
        guard let ratio = recordingAspect ?? pictureAspect else { return nil }
        return ratio > 1 ? .landscape : .portrait
    }

    public mutating func observeRecordingAspect(_ ratio: Double?) {
        recordingAspect = ratio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    public mutating func observePicture(width: Int32, height: Int32) {
        guard width > 0, height > 0 else { return }
        pictureAspect = Double(width) / Double(height)
    }
}
