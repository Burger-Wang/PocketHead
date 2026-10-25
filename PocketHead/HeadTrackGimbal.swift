import Foundation

struct GimbalObservation {
    let pose: GimbalPose
    let measuredAt: TimeInterval
}

/// Boundary for replacing the simulator with the Pocket 4 Pro native target stream.
/// A real implementation must own its connection token and reject submissions after
/// disconnect, manual takeover, or a stale camera pose.
@MainActor
protocol HeadTrackGimbal: AnyObject {
    var isSimulation: Bool { get }
    var observation: GimbalObservation? { get }
    func advance(elapsed: TimeInterval, now: TimeInterval)
    func beginHeadTracking() -> Bool
    func submit(_ target: GimbalPose, measuredAt: TimeInterval) -> Bool
    func endHeadTracking()
    func beginManualControl() -> Bool
    func updateManualStick(_ stick: ManualStick, sensitivity: Double) -> Bool
    /// Must send a neutral/rest command before relinquishing manual control.
    func endManualControl()
}
