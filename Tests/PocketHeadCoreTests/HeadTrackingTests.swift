import XCTest
@testable import PocketHeadCore

final class HeadTrackingTests: XCTestCase {
    private let limits = GimbalLimits(pan: -48...225, tilt: -44...70)

    private func sample(
        at time: TimeInterval,
        yawRight: Double = 0,
        pitchUp: Double = 0,
        speed: Double = 0
    ) -> HeadMotionSample {
        let yaw = Quaternion.rotation(axisX: 0, axisY: 0, axisZ: 1, degrees: -yawRight)
        let pitch = Quaternion.rotation(axisX: 1, axisY: 0, axisZ: 0, degrees: pitchUp)
        return HeadMotionSample(
            measuredAt: time,
            orientation: yaw.multiplied(by: pitch),
            angularSpeedRadPerSecond: speed
        )
    }

    func testCalibratedLookMapsRightAndUpToGimbal() throws {
        var engine = HeadTrackingEngine(
            limits: limits,
            settings: FollowSettings(sensitivity: 1, deadZoneDegrees: 0, smoothingSeconds: 0, maxSpeedDegreesPerSecond: 1_000)
        )
        try engine.calibrate(
            head: sample(at: 10),
            gimbal: GimbalPose(panDegrees: 12, tiltDegrees: -5),
            gimbalMeasuredAt: 10,
            now: 10
        )
        let target = try XCTUnwrap(engine.update(head: sample(at: 10.04, yawRight: 20, pitchUp: 10), now: 10.04))
        XCTAssertEqual(engine.lastLook.rightDegrees, 20, accuracy: 0.001)
        XCTAssertEqual(engine.lastLook.upDegrees, 10, accuracy: 0.001)
        XCTAssertEqual(target.panDegrees, 32, accuracy: 0.001)
        XCTAssertEqual(target.tiltDegrees, 5, accuracy: 0.001)
    }

    func testNodAtTurnedHeadingDoesNotDriftHorizontally() throws {
        var engine = HeadTrackingEngine(
            limits: limits,
            settings: FollowSettings(sensitivity: 1, deadZoneDegrees: 0, smoothingSeconds: 0, maxSpeedDegreesPerSecond: 1_000)
        )
        try engine.calibrate(head: sample(at: 10), gimbal: GimbalPose(panDegrees: 0, tiltDegrees: 0), gimbalMeasuredAt: 10, now: 10)
        _ = engine.update(head: sample(at: 10.04, yawRight: 45), now: 10.04)
        _ = engine.update(head: sample(at: 10.08, yawRight: 45, pitchUp: 20), now: 10.08)
        XCTAssertEqual(engine.lastLook.rightDegrees, 45, accuracy: 0.001)
        XCTAssertEqual(engine.lastLook.upDegrees, 20, accuracy: 0.001)
    }

    func testCalibrationRequiresFreshStillHeadAndFreshPose() {
        var engine = HeadTrackingEngine(limits: limits)
        XCTAssertThrowsError(try engine.calibrate(
            head: sample(at: 9), gimbal: GimbalPose(panDegrees: 0, tiltDegrees: 0),
            gimbalMeasuredAt: 10, now: 10
        )) { XCTAssertEqual($0 as? CalibrationError, .staleHead) }
        XCTAssertThrowsError(try engine.calibrate(
            head: sample(at: 10, speed: 0.1), gimbal: GimbalPose(panDegrees: 0, tiltDegrees: 0),
            gimbalMeasuredAt: 10, now: 10
        )) { XCTAssertEqual($0 as? CalibrationError, .movingHead) }
        XCTAssertThrowsError(try engine.calibrate(
            head: sample(at: 10), gimbal: GimbalPose(panDegrees: 0, tiltDegrees: 0),
            gimbalMeasuredAt: 9, now: 10
        )) { XCTAssertEqual($0 as? CalibrationError, .staleGimbal) }
    }

    func testStaleAndDuplicateSamplesProduceNoCommand() throws {
        var engine = HeadTrackingEngine(limits: limits)
        try engine.calibrate(head: sample(at: 10), gimbal: GimbalPose(panDegrees: 0, tiltDegrees: 0), gimbalMeasuredAt: 10, now: 10)
        XCTAssertNil(engine.update(head: sample(at: 10.01), now: 10.3))
        XCTAssertNotNil(engine.update(head: sample(at: 10.31), now: 10.31))
        XCTAssertNil(engine.update(head: sample(at: 10.31), now: 10.35))
    }

    func testDeadZoneSpeedLimitAndReach() throws {
        var engine = HeadTrackingEngine(
            limits: limits,
            settings: FollowSettings(sensitivity: 3, deadZoneDegrees: 2, smoothingSeconds: 0, maxSpeedDegreesPerSecond: 50)
        )
        try engine.calibrate(head: sample(at: 10), gimbal: GimbalPose(panDegrees: 0, tiltDegrees: 0), gimbalMeasuredAt: 10, now: 10)
        let still = try XCTUnwrap(engine.update(head: sample(at: 10.04, yawRight: 1), now: 10.04))
        XCTAssertEqual(still.panDegrees, 0, accuracy: 0.001)
        let first = try XCTUnwrap(engine.update(head: sample(at: 10.08, yawRight: 90), now: 10.08))
        XCTAssertEqual(first.panDegrees, 2, accuracy: 0.001)
        let later = try XCTUnwrap(engine.update(head: sample(at: 10.12, yawRight: 90), now: 10.12))
        XCTAssertEqual(later.panDegrees, 4, accuracy: 0.001)
        XCTAssertTrue(limits.contains(later))
    }

    func testUnwrapAcrossHalfTurn() throws {
        var engine = HeadTrackingEngine(
            limits: GimbalLimits(pan: -500...500, tilt: -90...90),
            settings: FollowSettings(sensitivity: 1, deadZoneDegrees: 0, smoothingSeconds: 0, maxSpeedDegreesPerSecond: 1_000)
        )
        try engine.calibrate(head: sample(at: 10), gimbal: GimbalPose(panDegrees: 0, tiltDegrees: 0), gimbalMeasuredAt: 10, now: 10)
        _ = engine.update(head: sample(at: 10.04, yawRight: 179), now: 10.04)
        _ = engine.update(head: sample(at: 10.08, yawRight: 181), now: 10.08)
        XCTAssertEqual(engine.lastLook.rightDegrees, 181, accuracy: 0.001)
    }
}
