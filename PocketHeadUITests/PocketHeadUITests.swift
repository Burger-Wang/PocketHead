import XCTest

final class PocketHeadUITests: XCTestCase {
    @MainActor
    func testFullscreenClosesBackToMountedTrackingPage() {
        let app = XCUIApplication()
        app.launch()
        let open = app.buttons["camera.preview.fullscreen.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let close = app.buttons["camera.preview.fullscreen.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["camera.preview.fullscreen"].exists)
        close.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["校准前方并开始"].exists)
    }

    @MainActor
    func testGuardShortPressStaysLockedAndLongPressUnlocks() {
        let app = XCUIApplication()
        app.launch()
        let calibrate = app.buttons["校准前方并开始"]
        XCTAssertTrue(calibrate.waitForExistence(timeout: 5))
        if !calibrate.isHittable { app.swipeUp() }
        calibrate.tap()
        let guardButton = app.buttons["touchGuard.enter"]
        if !guardButton.isHittable { app.swipeDown() }
        XCTAssertTrue(guardButton.waitForExistence(timeout: 3))
        guardButton.tap()
        let unlock = app.buttons["touchGuard.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 3))
        unlock.press(forDuration: 0.3)
        XCTAssertTrue(unlock.exists)
        unlock.press(forDuration: 1.7)
        XCTAssertTrue(guardButton.waitForExistence(timeout: 3))
    }
}
