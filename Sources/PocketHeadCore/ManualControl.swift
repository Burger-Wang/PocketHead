import Foundation

/// A centered, circular stick. Right and up are positive, and diagonal input
/// never exceeds the same unit magnitude as a cardinal direction.
public struct ManualStick: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public static let zero = ManualStick(x: 0, y: 0)

    public init(x: Double, y: Double) {
        guard x.isFinite, y.isFinite else {
            self.x = 0
            self.y = 0
            return
        }
        let length = hypot(x, y)
        let scale = length > 1 ? 1 / length : 1
        self.x = x * scale
        self.y = y * scale
    }

    public var isCentered: Bool { x == 0 && y == 0 }

    /// A small radial dead zone prevents accidental motion at the center.
    public var effectiveAxes: (x: Double, y: Double) {
        let length = hypot(x, y)
        let deadZone = 0.07
        guard length > deadZone else { return (0, 0) }
        let magnitude = (length - deadZone) / (1 - deadZone)
        return (x / length * magnitude, y / length * magnitude)
    }
}

public enum ManualGimbalMotion {
    /// Used by the simulator only. A real camera adapter maps the normalized
    /// axes onto its native stick command and sends rest on release.
    public static func nextPose(
        from pose: GimbalPose,
        stick: ManualStick,
        sensitivity: Double,
        elapsed: TimeInterval,
        limits: GimbalLimits
    ) -> GimbalPose {
        guard sensitivity.isFinite, elapsed.isFinite else { return pose }
        let axes = stick.effectiveAxes
        let speed = 80 * min(max(sensitivity, 0), 1)
        let duration = min(max(elapsed, 0), 0.1)
        return limits.clamped(GimbalPose(
            panDegrees: pose.panDegrees + axes.x * speed * duration,
            tiltDegrees: pose.tiltDegrees + axes.y * speed * duration
        ))
    }
}
