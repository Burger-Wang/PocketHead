import XCTest
@testable import PocketHeadCore

final class TouchGuardStateTests: XCTestCase {
    func testDimmingStartsAtOriginalBrightnessAndFinishesAtTarget() {
        XCTAssertEqual(TouchGuardState.brightnessDuringDimming(from: 0.8, elapsed: -1), 0.8)
        XCTAssertEqual(TouchGuardState.brightnessDuringDimming(from: 0.8, elapsed: 0), 0.8)
        let halfway = TouchGuardState.brightnessDuringDimming(from: 0.8, elapsed: 0.5)
        XCTAssertGreaterThan(halfway, 0.05)
        XCTAssertLessThan(halfway, 0.8)
        XCTAssertEqual(TouchGuardState.brightnessDuringDimming(from: 0.8, elapsed: 1), 0.05, accuracy: 1e-9)
        XCTAssertEqual(TouchGuardState.brightnessDuringDimming(from: 0.8, elapsed: 10), 0.05, accuracy: 1e-9)
    }

    func testDimmingIsMonotonicAndNeverBrightensAnAlreadyDarkScreen() {
        var previous = 0.8
        for frame in 0...60 {
            let elapsed = Double(frame) / 60
            let brightness = TouchGuardState.brightnessDuringDimming(from: 0.8, elapsed: elapsed)
            XCTAssertLessThanOrEqual(brightness, previous)
            XCTAssertGreaterThanOrEqual(brightness, 0.05 - 1e-9)
            XCTAssertEqual(TouchGuardState.brightnessDuringDimming(from: 0.01, elapsed: elapsed), 0.01)
            previous = brightness
        }
    }

    func testDimsOnlyAfterThreeIdleSeconds() {
        var state = TouchGuardState()
        state.enter(at: 10)
        state.advance(at: 12.999)
        XCTAssertFalse(state.isDimmed)
        state.advance(at: 13)
        XCTAssertTrue(state.isDimmed)
        XCTAssertTrue(state.isActive)
        XCTAssertNil(state.nextDeadline)
    }

    func testTouchRestoresBrightnessAndIdleStartsAfterRelease() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.advance(at: 3)
        state.touchBegan(id: 1, canUnlock: false, at: 5)
        XCTAssertFalse(state.isDimmed)
        state.advance(at: 100)
        XCTAssertFalse(state.isDimmed)
        XCTAssertFalse(state.isUnlocking)
        state.touchEnded(id: 1, cancelled: false, at: 100)
        state.advance(at: 102.999)
        XCTAssertFalse(state.isDimmed)
        state.advance(at: 103)
        XCTAssertTrue(state.isDimmed)
    }

    func testSuccessfulHoldDrainsTouchesBeforeExposingUnderlyingControls() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: true, at: 1)
        state.advance(at: 2.499)
        XCTAssertFalse(state.isUnlocking)
        state.advance(at: 2.5)
        XCTAssertTrue(state.isUnlocking)
        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.isDimmed)
        XCTAssertEqual(state.holdProgress(at: 2.5), 1)
        state.touchBegan(id: 2, canUnlock: false, at: 2.6)
        state.touchEnded(id: 1, cancelled: false, at: 2.7)
        XCTAssertTrue(state.isActive)
        state.touchEnded(id: 2, cancelled: false, at: 2.8)
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.nextDeadline)
    }

    func testShortPressesNeverAccumulate() {
        var state = TouchGuardState()
        state.enter(at: 0)
        for id in 1...5 {
            let start = Double(id * 3)
            state.touchBegan(id: id, canUnlock: true, at: start)
            state.touchEnded(id: id, cancelled: false, at: start + 1.499)
            XCTAssertTrue(state.isActive)
            XCTAssertFalse(state.isUnlocking)
            XCTAssertEqual(state.holdProgress(at: start + 1.499), 0)
        }
    }

    func testMovingOutCancelsHoldEvenAfterMovingBackInside() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: true, at: 0)
        state.touchMoved(id: 1, canUnlock: false)
        state.touchMoved(id: 1, canUnlock: true)
        state.advance(at: 5)
        XCTAssertFalse(state.isUnlocking)
        XCTAssertFalse(state.isDimmed)
        XCTAssertEqual(state.holdProgress(at: 5), 0)
    }

    func testTouchMustStartInsideUnlockControl() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: false, at: 0)
        state.touchMoved(id: 1, canUnlock: true)
        state.touchEnded(id: 1, cancelled: false, at: 10)
        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.isUnlocking)
    }

    func testSecondFingerCancelsHoldUntilANewSequence() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: true, at: 0)
        state.touchBegan(id: 2, canUnlock: true, at: 1)
        state.touchEnded(id: 2, cancelled: false, at: 1.1)
        state.advance(at: 6)
        XCTAssertFalse(state.isUnlocking)
        XCTAssertNil(state.holdStartedAt)
        state.touchEnded(id: 1, cancelled: false, at: 6)
        state.touchBegan(id: 3, canUnlock: true, at: 7)
        state.advance(at: 10)
        XCTAssertTrue(state.isUnlocking)
    }

    func testCancelledTouchCannotCompleteADelayedHold() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: true, at: 0)
        state.touchEnded(id: 1, cancelled: true, at: 10)
        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.isUnlocking)
        XCTAssertEqual(state.dimDeadline, 13)
    }

    func testValidReleaseCompletesHoldWhenTimerWasDelayed() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: true, at: 0)
        state.touchEnded(id: 1, cancelled: false, at: 1.5)
        XCTAssertFalse(state.isActive)
    }

    func testInterruptedSceneDiscardsHoldAndRestartsIdleDeadline() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: true, at: 0)
        state.cancelTouches(at: 1.4)
        state.advance(at: 1.5)
        XCTAssertTrue(state.isActive)
        XCTAssertFalse(state.isUnlocking)
        XCTAssertFalse(state.isDimmed)
        XCTAssertEqual(state.dimDeadline, 4.4)
        state.touchEnded(id: 1, cancelled: false, at: 4)
        XCTAssertEqual(state.dimDeadline, 4.4)
    }

    func testReenterDoesNotReusePreviousIdleOrHoldDeadlines() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: true, at: 1)
        state.exit()
        state.enter(at: 2)
        state.advance(at: 4)
        XCTAssertFalse(state.isDimmed)
        XCTAssertFalse(state.isUnlocking)
        XCTAssertNil(state.holdStartedAt)
        state.advance(at: 5)
        XCTAssertTrue(state.isDimmed)
    }

    func testTouchAtDeadlinePreventsStaleTimerFromDimming() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: true, at: 3)
        state.advance(at: 3)
        XCTAssertFalse(state.isDimmed)
        XCTAssertEqual(state.nextDeadline, 4.5)
        XCTAssertEqual(state.holdProgress(at: 3.75), 0.5)
    }

    func testOnlyLastFingerReleaseRestartsIdleCountdown() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.touchBegan(id: 1, canUnlock: false, at: 0)
        state.touchBegan(id: 2, canUnlock: false, at: 1)
        state.touchEnded(id: 1, cancelled: false, at: 2)
        state.advance(at: 10)
        XCTAssertFalse(state.isDimmed)
        XCTAssertNil(state.dimDeadline)
        state.touchEnded(id: 2, cancelled: true, at: 10)
        XCTAssertEqual(state.dimDeadline, 13)
    }

    func testExitDiscardsEveryPendingTransition() {
        var state = TouchGuardState()
        state.enter(at: 0)
        state.advance(at: 3)
        state.exit()
        state.advance(at: 100)
        state.touchBegan(id: 1, canUnlock: true, at: 100)
        XCTAssertEqual(state, TouchGuardState())
    }
}
