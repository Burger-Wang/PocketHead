import Foundation

/// Used by the simulator and the explicit demo mode. The UI identifies it as
/// "模拟云台" so test motion cannot be mistaken for a connected camera.
@MainActor
final class SimulatedGimbal: HeadTrackGimbal {
    let isSimulation = true
    private(set) var pose = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    private(set) var measuredAt = ProcessInfo.processInfo.systemUptime
    private var target = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    private var active = false

    var observation: GimbalObservation? {
        GimbalObservation(pose: pose, measuredAt: measuredAt)
    }

    func beginHeadTracking() -> Bool {
        active = true
        target = pose
        return true
    }

    func submit(_ target: GimbalPose, measuredAt: TimeInterval) -> Bool {
        guard active else { return false }
        self.target = target
        return true
    }

    func advance(elapsed: TimeInterval, now: TimeInterval) {
        if active {
            let maximumStep = 90 * max(0, elapsed)
            let deltaPan = target.panDegrees - pose.panDegrees
            let deltaTilt = target.tiltDegrees - pose.tiltDegrees
            let distance = hypot(deltaPan, deltaTilt)
            let scale = distance > maximumStep && distance > 0 ? maximumStep / distance : 1
            pose.panDegrees += deltaPan * scale
            pose.tiltDegrees += deltaTilt * scale
        }
        measuredAt = now
    }

    func endHeadTracking() {
        active = false
        target = pose
    }
}
