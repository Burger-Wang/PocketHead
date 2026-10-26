import Foundation

struct GimbalObservation {
    let pose: GimbalPose
    let measuredAt: TimeInterval
}

/// Shared boundary for the simulated and Pocket 4 Pro native target streams.
/// A real implementation owns its connection token and rejects submissions after
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
