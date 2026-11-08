import XCTest
@testable import PocketHeadCore

final class RecordingControlStateTests: XCTestCase {
    func testUnknownStateCannotSendARecordingCommand() {
        var state = RecordingControlState()
        XCTAssertFalse(state.canToggle(at: 1))
        XCTAssertNil(state.requestToggle(at: 1))
        XCTAssertNil(state.isRecording)
    }

    func testStartAndStopWaitForActualCameraReports() throws {
        var state = RecordingControlState()
        state.observe(false, at: 1)
        let start = try XCTUnwrap(state.requestToggle(at: 2))
        XCTAssertTrue(start.target)
        XCTAssertEqual(state.isRecording, false)
        XCTAssertFalse(state.canToggle(at: 2))
        XCTAssertNil(state.requestToggle(at: 2.1))

        // A repeated idle report cannot confirm the start command.
        state.observe(false, at: 2.2)
        XCTAssertEqual(state.pending, start)
        state.observe(true, at: 2.3)
        XCTAssertNil(state.pending)
        XCTAssertEqual(state.isRecording, true)
        let stop = try XCTUnwrap(state.requestToggle(at: 3))
        XCTAssertFalse(stop.target)
        XCTAssertGreaterThan(stop.id, start.id)
        XCTAssertEqual(state.isRecording, true)
        state.observe(false, at: 3.1)
        XCTAssertNil(state.pending)
        XCTAssertEqual(state.isRecording, false)
        XCTAssertTrue(state.canToggle(at: 3.1))
    }

    func testRefusedCommandKeepsReportedStateAndAllowsRetry() throws {
        var state = RecordingControlState()
        state.observe(true, at: 1)
        let request = try XCTUnwrap(state.requestToggle(at: 2))
        XCTAssertTrue(state.fail(requestID: request.id))
        XCTAssertEqual(state.isRecording, true)
        XCTAssertNil(state.pending)
        XCTAssertTrue(state.canToggle(at: 2))
        XCTAssertFalse(state.fail(requestID: request.id))
    }

    func testLateStartFailureCannotCancelANewerStopRequest() throws {
        var state = RecordingControlState()
        state.observe(false, at: 1)
        let start = try XCTUnwrap(state.requestToggle(at: 2))
        state.observe(true, at: 2.1)
        let stop = try XCTUnwrap(state.requestToggle(at: 2.2))
        XCTAssertFalse(state.fail(requestID: start.id))
        XCTAssertEqual(state.pending, stop)
        XCTAssertEqual(state.isRecording, true)
        state.observe(false, at: 2.3)
        XCTAssertNil(state.pending)
    }

    func testFreshReportsDoNotKeepAnUnconfirmedCommandWaitingForever() throws {
        var state = RecordingControlState()
        state.observe(false, at: 0)
        _ = try XCTUnwrap(state.requestToggle(at: 0))
        state.observe(false, at: 4.9)
        XCTAssertNil(state.advance(at: 4.999))
        XCTAssertEqual(state.advance(at: 5), .commandTimedOut)
        XCTAssertNil(state.pending)
        XCTAssertEqual(state.isRecording, false)
        XCTAssertTrue(state.canToggle(at: 5))
        // A late physical state change must still update the UI.
        state.observe(true, at: 6)
        XCTAssertEqual(state.isRecording, true)
    }

    func testStaleReportDisablesCommandsAndClearsPendingRequest() throws {
        var state = RecordingControlState()
        state.observe(false, at: 10)
        XCTAssertTrue(state.canToggle(at: 15))
        XCTAssertFalse(state.canToggle(at: 15.001))
        XCTAssertNil(state.requestToggle(at: 15.001))
        _ = try XCTUnwrap(state.requestToggle(at: 14))
        XCTAssertEqual(state.advance(at: 15.001), .reportExpired)
        XCTAssertNil(state.isRecording)
        XCTAssertNil(state.pending)
        XCTAssertFalse(state.canToggle(at: 15.001))
        state.observe(true, at: 16)
        XCTAssertTrue(state.canToggle(at: 16))
    }

    func testIdleReportExpiryDoesNotReportAnOperationFailure() {
        var state = RecordingControlState()
        state.observe(false, at: 0)
        XCTAssertNil(state.advance(at: 5.001))
        XCTAssertNil(state.isRecording)
        XCTAssertNil(state.pending)
    }

    func testDisconnectInvalidatesOldCallbacksEvenAfterReconnection() throws {
        var state = RecordingControlState()
        state.observe(false, at: 1)
        let old = try XCTUnwrap(state.requestToggle(at: 2))
        state.reset()
        XCTAssertNil(state.isRecording)
        XCTAssertNil(state.pending)
        XCTAssertFalse(state.fail(requestID: old.id))
        state.observe(true, at: 3)
        let new = try XCTUnwrap(state.requestToggle(at: 4))
        XCTAssertGreaterThan(new.id, old.id)
        XCTAssertFalse(state.fail(requestID: old.id))
        XCTAssertEqual(state.pending, new)
        XCTAssertEqual(state.isRecording, true)
    }

    func testReportFromAFutureClockCannotAuthorizeCommands() {
        var state = RecordingControlState()
        state.observe(false, at: 10)
        XCTAssertFalse(state.canToggle(at: 9))
        XCTAssertNil(state.requestToggle(at: 9))
        XCTAssertNil(state.advance(at: 9))
        XCTAssertNil(state.isRecording)
    }
}
