import XCTest
@testable import PocketHeadCore

final class PreviewGeometryTests: XCTestCase {
    func testStreamDimensionsSelectLandscapeOrPortrait() {
        var geometry = PreviewGeometry()
        XCTAssertNil(geometry.orientation)
        geometry.observePicture(width: 320, height: 180)
        XCTAssertEqual(geometry.orientation, .landscape)
        geometry.observePicture(width: 180, height: 320)
        XCTAssertEqual(geometry.orientation, .portrait)
    }

    func testPortraitRecordingOverridesLandscapeTransportRaster() {
        var geometry = PreviewGeometry()
        geometry.observePicture(width: 320, height: 180)
        geometry.observeRecordingAspect(9.0 / 16)
        XCTAssertEqual(geometry.orientation, .portrait)
        geometry.observePicture(width: 640, height: 360)
        XCTAssertEqual(geometry.orientation, .portrait)
        geometry.observeRecordingAspect(16.0 / 9)
        XCTAssertEqual(geometry.orientation, .landscape)
        geometry.observeRecordingAspect(nil)
        geometry.observePicture(width: 180, height: 320)
        XCTAssertEqual(geometry.orientation, .portrait)
    }

    func testInvalidGeometryCannotInventAnOrientation() {
        var geometry = PreviewGeometry()
        geometry.observePicture(width: 0, height: -1)
        geometry.observeRecordingAspect(.nan)
        XCTAssertNil(geometry.orientation)
        geometry.observePicture(width: 320, height: 180)
        geometry.observeRecordingAspect(.infinity)
        XCTAssertEqual(geometry.orientation, .landscape)
        geometry = PreviewGeometry()
        XCTAssertNil(geometry.orientation)
    }
}
