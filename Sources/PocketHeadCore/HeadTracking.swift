import Foundation

public struct Quaternion: Equatable, Sendable {
    public let w: Double
    public let x: Double
    public let y: Double
    public let z: Double

    public static let identity = Quaternion(w: 1, x: 0, y: 0, z: 0)

    public init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    public var normalized: Quaternion? {
        let length = sqrt(w * w + x * x + y * y + z * z)
        guard length.isFinite, length > 1e-9 else { return nil }
        return Quaternion(w: w / length, x: x / length, y: y / length, z: z / length)
    }

    public var conjugate: Quaternion {
        Quaternion(w: w, x: -x, y: -y, z: -z)
    }

    public func multiplied(by other: Quaternion) -> Quaternion {
        Quaternion(
            w: w * other.w - x * other.x - y * other.y - z * other.z,
            x: w * other.x + x * other.w + y * other.z - z * other.y,
            y: w * other.y - x * other.z + y * other.w + z * other.x,
            z: w * other.z + x * other.y - y * other.x + z * other.w
        )
    }

    public func rotatingForward() -> (x: Double, y: Double, z: Double) {
        // AirPods attitude uses +Y as the direction of the face.
        let forward = Quaternion(w: 0, x: 0, y: 1, z: 0)
        let result = multiplied(by: forward).multiplied(by: conjugate)
        return (result.x, result.y, result.z)
    }

    public static func rotation(axisX: Double, axisY: Double, axisZ: Double, degrees: Double) -> Quaternion {
        let length = sqrt(axisX * axisX + axisY * axisY + axisZ * axisZ)
        guard length > 0 else { return .identity }
        let halfAngle = degrees * .pi / 360
        let scale = sin(halfAngle) / length
        return Quaternion(
            w: cos(halfAngle),
            x: axisX * scale,
            y: axisY * scale,
            z: axisZ * scale
        )
    }
}

public struct HeadMotionSample: Sendable {
    public let measuredAt: TimeInterval
    public let orientation: Quaternion
    public let angularSpeedRadPerSecond: Double

    public init(measuredAt: TimeInterval, orientation: Quaternion, angularSpeedRadPerSecond: Double) {
        self.measuredAt = measuredAt
        self.orientation = orientation
        self.angularSpeedRadPerSecond = angularSpeedRadPerSecond
    }
}

public struct GimbalPose: Equatable, Sendable {
    public var panDegrees: Double
    public var tiltDegrees: Double

    public init(panDegrees: Double, tiltDegrees: Double) {
        self.panDegrees = panDegrees
        self.tiltDegrees = tiltDegrees
    }
}

public struct GimbalLimits: Sendable {
    public let pan: ClosedRange<Double>
    public let tilt: ClosedRange<Double>

    public init(pan: ClosedRange<Double>, tilt: ClosedRange<Double>) {
        self.pan = pan
        self.tilt = tilt
    }

    // Values reported by OpenPocketCine for its 4 Pro path. The actual camera
    // adapter must supply validated bounds from the connected device.
    public static let referencePocket4Pro = GimbalLimits(pan: -48...225, tilt: -44...70)

    public func contains(_ pose: GimbalPose) -> Bool {
        pose.panDegrees.isFinite && pose.tiltDegrees.isFinite &&
            pan.contains(pose.panDegrees) && tilt.contains(pose.tiltDegrees)
    }

    public func clamped(_ pose: GimbalPose) -> GimbalPose {
        GimbalPose(
            panDegrees: min(max(pose.panDegrees, pan.lowerBound), pan.upperBound),
            tiltDegrees: min(max(pose.tiltDegrees, tilt.lowerBound), tilt.upperBound)
        )
    }
}

public struct LookAngles: Equatable, Sendable {
    public let rightDegrees: Double
    public let upDegrees: Double

    public static let zero = LookAngles(rightDegrees: 0, upDegrees: 0)
}

public struct FollowSettings: Equatable, Sendable {
    public var sensitivity: Double
    public var deadZoneDegrees: Double
    public var smoothingSeconds: Double
    public var maxSpeedDegreesPerSecond: Double

    public init(
        sensitivity: Double,
        deadZoneDegrees: Double,
        smoothingSeconds: Double,
        maxSpeedDegreesPerSecond: Double
    ) {
        self.sensitivity = sensitivity
        self.deadZoneDegrees = deadZoneDegrees
        self.smoothingSeconds = smoothingSeconds
        self.maxSpeedDegreesPerSecond = maxSpeedDegreesPerSecond
    }
}

public enum FollowPreset: String, CaseIterable, Sendable {
    case fast = "快速"
    case standard = "标准"
    case gentle = "轻柔"

    public var settings: FollowSettings {
        switch self {
        case .fast:
            FollowSettings(sensitivity: 1.2, deadZoneDegrees: 0.5, smoothingSeconds: 0.06, maxSpeedDegreesPerSecond: 120)
        case .standard:
            FollowSettings(sensitivity: 1, deadZoneDegrees: 1, smoothingSeconds: 0.12, maxSpeedDegreesPerSecond: 75)
        case .gentle:
            FollowSettings(sensitivity: 0.8, deadZoneDegrees: 2, smoothingSeconds: 0.22, maxSpeedDegreesPerSecond: 45)
        }
    }
}

public enum CalibrationError: Error, Equatable, Sendable {
    case staleHead
    case movingHead
    case staleGimbal
    case invalidGimbalPose
}

public struct HeadTrackingEngine: Sendable {
    public static let maximumHeadAge: TimeInterval = 0.2
    public static let maximumGimbalAge: TimeInterval = 0.3
    public static let maximumCalibrationAngularSpeed = 0.08

    public var settings: FollowSettings
    public let limits: GimbalLimits
    public private(set) var lastLook: LookAngles = .zero
    public private(set) var isCalibrated = false

    private var originHead: Quaternion = .identity
    private var originGimbal = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    private var lastUnwrappedRight = 0.0
    private var lastSampleTime: TimeInterval?
    private var lastOutputTime: TimeInterval?
    private var lastOutput = GimbalPose(panDegrees: 0, tiltDegrees: 0)

    public init(limits: GimbalLimits, settings: FollowSettings = FollowPreset.standard.settings) {
        self.limits = limits
        self.settings = settings
    }

    public mutating func reset() {
        isCalibrated = false
        lastLook = .zero
        lastUnwrappedRight = 0
        lastSampleTime = nil
        lastOutputTime = nil
    }

    public mutating func calibrate(
        head: HeadMotionSample,
        gimbal: GimbalPose,
        gimbalMeasuredAt: TimeInterval,
        now: TimeInterval
    ) throws {
        guard Self.isFresh(head.measuredAt, now: now, maximumAge: Self.maximumHeadAge),
              let orientation = head.orientation.normalized else {
            throw CalibrationError.staleHead
        }
        guard head.angularSpeedRadPerSecond.isFinite,
              head.angularSpeedRadPerSecond < Self.maximumCalibrationAngularSpeed else {
            throw CalibrationError.movingHead
        }
        guard Self.isFresh(gimbalMeasuredAt, now: now, maximumAge: Self.maximumGimbalAge) else {
            throw CalibrationError.staleGimbal
        }
        guard limits.contains(gimbal) else { throw CalibrationError.invalidGimbalPose }

        originHead = orientation
        originGimbal = gimbal
        lastOutput = gimbal
        lastOutputTime = now
        lastSampleTime = head.measuredAt
        lastUnwrappedRight = 0
        lastLook = .zero
        isCalibrated = true
    }

    public mutating func update(head: HeadMotionSample, now: TimeInterval) -> GimbalPose? {
        guard isCalibrated,
              Self.isFresh(head.measuredAt, now: now, maximumAge: Self.maximumHeadAge),
              let orientation = head.orientation.normalized,
              head.measuredAt > (lastSampleTime ?? -.infinity),
              let lastOutputTime else { return nil }

        let relative = originHead.conjugate.multiplied(by: orientation)
        let forward = relative.rotatingForward()
        let wrappedRight = atan2(forward.x, forward.y) * 180 / .pi
        let up = atan2(forward.z, hypot(forward.x, forward.y)) * 180 / .pi
        guard wrappedRight.isFinite, up.isFinite else { return nil }

        let unwrappedRight = lastUnwrappedRight + Self.wrap(wrappedRight - lastUnwrappedRight)
        lastUnwrappedRight = unwrappedRight
        lastLook = LookAngles(rightDegrees: unwrappedRight, upDegrees: up)
        lastSampleTime = head.measuredAt

        let deadZone = max(0, settings.deadZoneDegrees)
        let sensitivity = max(0, settings.sensitivity)
        let desired = limits.clamped(GimbalPose(
            panDegrees: originGimbal.panDegrees + sensitivity * Self.applyDeadZone(unwrappedRight, deadZone: deadZone),
            tiltDegrees: originGimbal.tiltDegrees + sensitivity * Self.applyDeadZone(up, deadZone: deadZone)
        ))

        let elapsed = max(0, min(now - lastOutputTime, 0.25))
        guard elapsed > 0 else { return lastOutput }
        let smoothing = max(0, settings.smoothingSeconds)
        let alpha = smoothing == 0 ? 1 : 1 - exp(-elapsed / smoothing)
        let filtered = GimbalPose(
            panDegrees: lastOutput.panDegrees + alpha * (desired.panDegrees - lastOutput.panDegrees),
            tiltDegrees: lastOutput.tiltDegrees + alpha * (desired.tiltDegrees - lastOutput.tiltDegrees)
        )

        let panStep = filtered.panDegrees - lastOutput.panDegrees
        let tiltStep = filtered.tiltDegrees - lastOutput.tiltDegrees
        let distance = hypot(panStep, tiltStep)
        let maxStep = max(0, settings.maxSpeedDegreesPerSecond) * elapsed
        let scale = distance > maxStep && distance > 0 ? maxStep / distance : 1
        lastOutput = limits.clamped(GimbalPose(
            panDegrees: lastOutput.panDegrees + panStep * scale,
            tiltDegrees: lastOutput.tiltDegrees + tiltStep * scale
        ))
        self.lastOutputTime = now
        return lastOutput
    }

    private static func isFresh(_ measuredAt: TimeInterval, now: TimeInterval, maximumAge: TimeInterval) -> Bool {
        measuredAt.isFinite && now.isFinite && now >= measuredAt && now - measuredAt <= maximumAge
    }

    private static func applyDeadZone(_ value: Double, deadZone: Double) -> Double {
        let magnitude = max(0, abs(value) - deadZone)
        return value < 0 ? -magnitude : magnitude
    }

    private static func wrap(_ angle: Double) -> Double {
        var result = angle.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result <= -180 { result += 360 }
        return result
    }
}
