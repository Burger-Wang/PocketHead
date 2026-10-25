import Foundation

struct GimbalObservation {
    let pose: GimbalPose
    let measuredAt: TimeInterval
}

/// Boundary for replacing the simulator with the Pocket 4 Pro native target stream.
/// A real implementation must own its connection token and reject submissions after
/// disconnect or a stale camera pose.
@MainActor
protocol HeadTrackGimbal: AnyObject {
    var isSimulation: Bool { get }
    var observation: GimbalObservation? { get }
    func advance(elapsed: TimeInterval, now: TimeInterval)
    func beginHeadTracking() -> Bool
    func submit(_ target: GimbalPose, measuredAt: TimeInterval) -> Bool
    func endHeadTracking()
}
