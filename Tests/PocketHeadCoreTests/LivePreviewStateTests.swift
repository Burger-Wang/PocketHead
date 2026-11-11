import XCTest
@testable import PocketHeadCore

final class LivePreviewStateTests: XCTestCase {
    func testDisconnectedPreviewNeverRequestsCameraCommands() {
        var state = LivePreviewState()
        XCTAssertFalse(state.advance(at: 100))
        XCTAssertFalse(state.retry(at: 100))
        XCTAssertEqual(state.phase, .disconnected)
    }

    func testFirstPictureTimeoutHasBoundedAutomaticRecovery() {
        var state = LivePreviewState()
        state.connect(at: 0)
        XCTAssertFalse(state.advance(at: 7.999))
        XCTAssertEqual(state.phase, .waitingForPicture)
        XCTAssertTrue(state.advance(at: 8))
        XCTAssertFalse(state.advance(at: 8.1))
        XCTAssertTrue(state.advance(at: 11))
        XCTAssertTrue(state.advance(at: 14))
        XCTAssertFalse(state.advance(at: 17))
        XCTAssertEqual(state.phase, .failed)
        XCTAssertFalse(state.advance(at: 100))
        XCTAssertEqual(state.automaticRetries, 3)
    }

    func testRepeatedOldPictureCannotHideAStalledFeed() {
        var state = LivePreviewState()
        let generation = state.connect(at: 0)
        state.pictureArrived(generation: generation, at: 1)
        XCTAssertEqual(state.phase, .live)
        XCTAssertFalse(state.advance(at: 2.999))
        XCTAssertTrue(state.advance(at: 3))
        state.pictureArrived(generation: generation, at: 1)
        XCTAssertEqual(state.phase, .stalled)
        state.pictureArrived(generation: generation, at: 3.1)
        XCTAssertEqual(state.phase, .live)
        XCTAssertEqual(state.automaticRetries, 0)
    }

    func testDiscontinuityRespectsTheEnableCooldown() {
        var state = LivePreviewState()
        let generation = state.connect(at: 10)
        state.pictureArrived(generation: generation, at: 10.1)
        state.interrupted(generation: generation)
        XCTAssertEqual(state.phase, .stalled)
        XCTAssertFalse(state.advance(at: 12.999))
        XCTAssertTrue(state.advance(at: 13))
        XCTAssertFalse(state.advance(at: 13.1))
    }

    func testManualRetryStartsANewFirstPictureBudgetWithoutReconnect() {
        var state = LivePreviewState()
        let generation = state.connect(at: 0)
        state.fail(generation: generation)
        XCTAssertFalse(state.retry(at: 2.999))
        XCTAssertTrue(state.retry(at: 3))
        XCTAssertEqual(state.generation, generation)
        XCTAssertEqual(state.phase, .waitingForPicture)
        XCTAssertFalse(state.retry(at: 3.1))
        XCTAssertFalse(state.advance(at: 10.999))
        XCTAssertTrue(state.advance(at: 11))
    }

    func testOldConnectionCannotPaintOrFailTheNewConnection() {
        var state = LivePreviewState()
        let old = state.connect(at: 0)
        state.disconnect()
        state.pictureArrived(generation: old, at: 1)
        XCTAssertEqual(state.phase, .disconnected)
        let current = state.connect(at: 2)
        XCTAssertNotEqual(current, old)
        state.pictureArrived(generation: old, at: 3)
        state.interrupted(generation: old)
        state.fail(generation: old)
        XCTAssertEqual(state.phase, .waitingForPicture)
        state.pictureArrived(generation: current, at: 3)
        XCTAssertEqual(state.phase, .live)
    }

    func testLateRealPictureCanRecoverAnExhaustedPreview() {
        var state = LivePreviewState()
        let generation = state.connect(at: 0)
        for time in [8.0, 11, 14, 17] { _ = state.advance(at: time) }
        XCTAssertEqual(state.phase, .failed)
        state.pictureArrived(generation: generation, at: 18)
        XCTAssertEqual(state.phase, .live)
        XCTAssertEqual(state.automaticRetries, 0)
    }

    func testPicturePredatingConnectionCannotCompleteStartup() {
        var state = LivePreviewState()
        let generation = state.connect(at: 10)
        state.pictureArrived(generation: generation, at: 9)
        XCTAssertEqual(state.phase, .waitingForPicture)
    }
}
