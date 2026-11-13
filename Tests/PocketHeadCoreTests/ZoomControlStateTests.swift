import XCTest
@testable import PocketHeadCore

final class ZoomControlStateTests: XCTestCase {
    func testRangeChangeCancelsEvenWhenFinalTargetRemainsLegal() {
        for continuous in [false, true] {
            var state = ZoomControlState()
            state.observe(9, at: 0)
            if continuous {
                XCTAssertTrue(state.beginContinuous(increasing: false, maximum: 12, at: 0))
            } else {
                XCTAssertTrue(state.request(1, maximum: 12, at: 0))
            }
            XCTAssertEqual(state.advance(at: 0.1, maximum: 3, allowed: true), .unavailable)
            XCTAssertFalse(state.isAdjusting)
            XCTAssertNil(state.advance(at: 0.2, maximum: 3, allowed: true))
            XCTAssertEqual(state.reportedFactor, 9)
        }
    }

    func testNewMoveCannotClampAnOutOfRangeStartingPosition() {
        var state = ZoomControlState()
        state.observe(9, at: 0)
        XCTAssertFalse(state.request(1, maximum: 3, at: 0))
        XCTAssertFalse(state.beginContinuous(increasing: false, maximum: 3, at: 0))
        XCTAssertFalse(state.isAdjusting)
    }

    func testExpandedRangeAlsoRequiresANewMove() {
        var state = ZoomControlState()
        state.observe(1, at: 0)
        XCTAssertTrue(state.beginContinuous(increasing: true, maximum: 3, at: 0))
        XCTAssertEqual(state.advance(at: 0.1, maximum: 12, allowed: true), .unavailable)
        XCTAssertTrue(state.beginContinuous(increasing: true, maximum: 12, at: 0.1))
        XCTAssertEqual(state.advance(at: 0.1, maximum: 12, allowed: true), .set(1))
    }

    func testHeldZoomHasContinuousSmallTargetsAndStopsAtRelease() {
        var state = ZoomControlState()
        state.observe(1, at: 0)
        XCTAssertTrue(state.beginContinuous(increasing: true, maximum: 12, at: 0))
        var factors: [Double] = []
        for tick in 0...20 {
            let now = Double(tick) * 0.05
            state.observe(factors.last ?? 1, at: now)
            if case .set(let factor) = state.advance(at: now, maximum: 12, allowed: true) { factors.append(factor) }
        }
        XCTAssertEqual(factors.count, 21)
        XCTAssertEqual(factors.last ?? 0, 2.35, accuracy: 1e-9)
        let differences = zip(factors.dropFirst(), factors).map(-)
        XCTAssertTrue(differences.allSatisfy { $0 >= 0 && $0 < 0.08 })
        XCTAssertLessThan(differences[0], differences[4])
        state.stopContinuous()
        XCTAssertFalse(state.isAdjusting)
        XCTAssertNil(state.advance(at: 1.05, maximum: 12, allowed: true))
        XCTAssertNil(state.advance(at: 1.5, maximum: 12, allowed: true))
    }

    func testHeldZoomClampsAtBothLimitsAndRetiresItsMove() {
        for increasing in [true, false] {
            var state = ZoomControlState()
            state.observe(increasing ? 11.99 : 1.01, at: 0)
            XCTAssertTrue(state.beginContinuous(increasing: increasing, maximum: 12, at: 0))
            XCTAssertEqual(state.advance(at: 0.2, maximum: 12, allowed: true), .set(increasing ? 12 : 1))
            XCTAssertFalse(state.isAdjusting)
            XCTAssertNil(state.advance(at: 0.3, maximum: 12, allowed: true))
        }
    }

    func testImmediateReversalUsesLastCommandAndReleaseCannotCancelPreset() {
        var state = ZoomControlState()
        state.observe(3, at: 0)
        XCTAssertTrue(state.beginContinuous(increasing: true, maximum: 12, at: 0))
        XCTAssertEqual(state.advance(at: 0.5, maximum: 12, allowed: true), .set(3.6))
        state.stopContinuous()
        XCTAssertTrue(state.beginContinuous(increasing: false, maximum: 12, at: 0.51))
        XCTAssertEqual(state.advance(at: 0.51, maximum: 12, allowed: true), .set(3.6))
        XCTAssertTrue(state.request(9, maximum: 12, at: 0.6))
        state.stopContinuous()
        XCTAssertEqual(state.targetFactor, 9)
        XCTAssertTrue(state.isAdjusting)
    }

    func testContinuousMoveStopsOnLostFeedbackOrUnavailableMode() {
        var state = ZoomControlState()
        state.observe(3, at: 0)
        XCTAssertTrue(state.beginContinuous(increasing: true, maximum: 12, at: 0))
        XCTAssertEqual(state.advance(at: 1.3, maximum: 12, allowed: true), .feedbackLost)
        XCTAssertFalse(state.isAdjusting)
        state.observe(3, at: 2)
        XCTAssertTrue(state.beginContinuous(increasing: false, maximum: 12, at: 2))
        XCTAssertEqual(state.advance(at: 2.1, maximum: 12, allowed: false), .unavailable)
        XCTAssertFalse(state.isAdjusting)
    }

    func testPresetSendsIntermediateValuesAndRequiresCameraConfirmation() throws {
        var state = ZoomControlState()
        state.observe(1, at: 0)
        XCTAssertTrue(state.request(9, maximum: 12, at: 0))
        var targets: [Double] = []
        for tick in 0...50 {
            let now = Double(tick) * 0.05
            if tick.isMultiple(of: 4) { state.observe(targets.last ?? 1, at: now) }
            if case .set(let factor) = state.advance(at: now, maximum: 12, allowed: true) {
                targets.append(factor)
            }
        }
        XCTAssertGreaterThan(targets.count, 30)
        XCTAssertEqual(try XCTUnwrap(targets.first), 1)
        XCTAssertTrue(targets.contains { $0 > 3 && $0 < 8 })
        XCTAssertTrue(zip(targets, targets.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertEqual(try XCTUnwrap(targets.last), 9)
        XCTAssertNil(state.targetFactor)
        XCTAssertEqual(state.reportedFactor, 9)
    }

    func testRapidRetargetContinuesFromCurveInsteadOfOldTelemetry() throws {
        var state = ZoomControlState()
        state.observe(1, at: 0)
        XCTAssertTrue(state.request(9, maximum: 12, at: 0))
        guard case .set(let before) = state.advance(at: 0.6, maximum: 12, allowed: true) else {
            return XCTFail("Expected an intermediate zoom target")
        }
        XCTAssertTrue(state.request(3, maximum: 12, at: 0.6))
        guard case .set(let after) = state.advance(at: 0.6, maximum: 12, allowed: true) else {
            return XCTFail("Expected a continuous retarget")
        }
        XCTAssertEqual(before, after, accuracy: 1e-9)
        XCTAssertGreaterThan(after, 1)
        XCTAssertEqual(state.reportedFactor, 1)
    }

    func testNoWritesWithoutFreshFeedbackAndNoOutOfRangeRequests() {
        var state = ZoomControlState()
        XCTAssertFalse(state.request(3, maximum: 12, at: 0))
        state.observe(1, at: 0)
        XCTAssertFalse(state.request(9, maximum: 2, at: 0))
        XCTAssertFalse(state.request(.nan, maximum: 12, at: 0))
        XCTAssertFalse(state.request(3, maximum: .infinity, at: 0))
        XCTAssertFalse(state.request(3, maximum: 12, at: 1.3))
        XCTAssertTrue(state.request(2, maximum: 2, at: 0.2))
        XCTAssertEqual(state.advance(at: 1.3, maximum: 2, allowed: true), .feedbackLost)
        XCTAssertNil(state.targetFactor)
        XCTAssertNil(state.advance(at: 1.4, maximum: 2, allowed: true))
    }

    func testModeChangeCancelsBeforeAnotherLensWrite() {
        for maximum in [1.0, 2, 12] {
            var state = ZoomControlState()
            state.observe(1, at: 0)
            XCTAssertTrue(state.request(9, maximum: 12, at: 0))
            XCTAssertEqual(state.advance(at: 0.1, maximum: maximum, allowed: maximum != 12), .unavailable)
            XCTAssertNil(state.targetFactor)
        }
    }

    func testFinalSetDoesNotOptimisticallyChangeReadoutAndTimesOut() {
        var state = ZoomControlState()
        state.observe(1, at: 0)
        XCTAssertTrue(state.request(1.5, maximum: 12, at: 0))
        XCTAssertEqual(state.advance(at: 0.4, maximum: 12, allowed: true), .set(1.5))
        XCTAssertEqual(state.reportedFactor, 1)
        for tick in 1...3 {
            state.observe(1, at: Double(tick))
            XCTAssertNil(state.advance(at: Double(tick), maximum: 12, allowed: true))
        }
        XCTAssertEqual(state.advance(at: 3.5, maximum: 12, allowed: true), .unconfirmed)
        XCTAssertNil(state.targetFactor)
        XCTAssertEqual(state.reportedFactor, 1)
    }

    func testConfirmationBeforeFinalDispatchCannotCompleteNewRequest() {
        var state = ZoomControlState()
        state.observe(3, at: 0)
        XCTAssertTrue(state.request(3, maximum: 12, at: 0))
        state.observe(3, at: 0.1)
        XCTAssertEqual(state.targetFactor, 3)
        XCTAssertEqual(state.advance(at: 0.4, maximum: 12, allowed: true), .set(3))
        state.observe(3, at: 0.5)
        XCTAssertNil(state.targetFactor)
    }

    func testDispatchRateIsBoundedAndResetForgetsOldTargetAndReadout() {
        var state = ZoomControlState()
        state.observe(1, at: 0)
        XCTAssertTrue(state.request(9, maximum: 12, at: 0))
        XCTAssertEqual(state.advance(at: 0, maximum: 12, allowed: true), .set(1))
        XCTAssertNil(state.advance(at: 0.02, maximum: 12, allowed: true))
        state.reset()
        XCTAssertNil(state.advance(at: 0.1, maximum: 12, allowed: true))
        XCTAssertNil(state.reportedFactor)
        XCTAssertFalse(state.request(3, maximum: 12, at: 0.1))
    }

    func testZoomGraceDelaysOnlyPictureRecoveryAndStillExpires() {
        var preview = LivePreviewState()
        let generation = preview.connect(at: 0)
        preview.pictureArrived(generation: generation, at: 1)
        XCTAssertFalse(preview.advance(at: 3.1, holdRecovery: true))
        XCTAssertEqual(preview.phase, .stalled)
        XCTAssertEqual(preview.automaticRetries, 0)
        XCTAssertTrue(preview.advance(at: 5.1, holdRecovery: false))
        XCTAssertEqual(preview.automaticRetries, 1)
    }
}
