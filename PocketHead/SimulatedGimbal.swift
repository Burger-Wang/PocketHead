import Foundation

/// The UI uses this while the Pocket 4 Pro transport is being integrated.
/// The visible "模拟云台" label is always shown when this implementation is active.
@MainActor
final class SimulatedGimbal: HeadTrackGimbal {
    let isSimulation = true
    private(set) var pose = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    private(set) var measuredAt = ProcessInfo.processInfo.systemUptime
    private var target = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    private var headTrackingActive = false
    private var manualControlActive = false
    private var stick = ManualStick.zero
    private var manualSensitivity = 0.7

    var observation: GimbalObservation? {
        GimbalObservation(pose: pose, measuredAt: measuredAt)
    }

    func beginHeadTracking() -> Bool {
        guard !manualControlActive else { return false }
        headTrackingActive = true
        target = pose
        return true
    }

    func submit(_ target: GimbalPose, measuredAt: TimeInterval) -> Bool {
        guard headTrackingActive, !manualControlActive else { return false }
        self.target = target
        return true
    }

    func advance(elapsed: TimeInterval, now: TimeInterval) {
        if manualControlActive {
            pose = ManualGimbalMotion.nextPose(
                from: pose,
                stick: stick,
                sensitivity: manualSensitivity,
                elapsed: elapsed,
                limits: .referencePocket4Pro
            )
            target = pose
        } else if headTrackingActive {
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
        headTrackingActive = false
        target = pose
    }

    func beginManualControl() -> Bool {
        endHeadTracking()
        manualControlActive = true
        stick = .zero
        return true
    }

    func updateManualStick(_ stick: ManualStick, sensitivity: Double) -> Bool {
        guard manualControlActive else { return false }
        self.stick = stick
        manualSensitivity = sensitivity
        return true
    }

    func endManualControl() {
        stick = .zero
        manualControlActive = false
        target = pose
    }
}
