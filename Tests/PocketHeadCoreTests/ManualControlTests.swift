import XCTest
@testable import PocketHeadCore

final class ManualControlTests: XCTestCase {
    private let limits = GimbalLimits(pan: -48...225, tilt: -44...70)

    func testStickClampsDiagonalAndRejectsInvalidValues() {
        let stick = ManualStick(x: 1, y: 1)
        XCTAssertEqual(hypot(stick.x, stick.y), 1, accuracy: 0.0001)
        XCTAssertEqual(ManualStick(x: .nan, y: 1), .zero)
    }

    func testRightAndUpMoveTheCorrespondingAxes() {
        let next = ManualGimbalMotion.nextPose(
            from: GimbalPose(panDegrees: 0, tiltDegrees: 0),
            stick: ManualStick(x: 1, y: 0.5),
            sensitivity: 1,
            elapsed: 0.04,
            limits: limits
        )
        XCTAssertGreaterThan(next.panDegrees, 0)
        XCTAssertGreaterThan(next.tiltDegrees, 0)
        XCTAssertGreaterThan(next.panDegrees, next.tiltDegrees)
    }

    func testCenteredStickStopsAndDeadZoneSuppressesDrift() {
        let pose = GimbalPose(panDegrees: 12, tiltDegrees: -5)
        XCTAssertEqual(ManualGimbalMotion.nextPose(from: pose, stick: .zero, sensitivity: 1, elapsed: 0.1, limits: limits), pose)
        XCTAssertEqual(ManualGimbalMotion.nextPose(from: pose, stick: ManualStick(x: 0.03, y: 0), sensitivity: 1, elapsed: 0.1, limits: limits), pose)
    }

    func testManualMotionRespectsCameraBounds() {
        let next = ManualGimbalMotion.nextPose(
            from: GimbalPose(panDegrees: 224, tiltDegrees: 69),
            stick: ManualStick(x: 1, y: 1),
            sensitivity: 1,
            elapsed: 1,
            limits: limits
        )
        XCTAssertEqual(next.panDegrees, 225)
        XCTAssertEqual(next.tiltDegrees, 70)
    }
}
