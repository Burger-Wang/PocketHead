import SwiftUI
import XCTest
@testable import PocketHead

@MainActor
final class LivePreviewIntegrationTests: XCTestCase {
    private func units() throws -> [[UInt8]] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "color-bars", withExtension: "hevc"))
        let bytes = [UInt8](try Data(contentsOf: url))
        let starts = (0..<(bytes.count - 4)).filter {
            Array(bytes[$0..<($0 + 4)]) == [0, 0, 0, 1] && (bytes[$0 + 4] >> 1) & 0x3f == 32
        }
        return starts.enumerated().map { index, start in
            Array(bytes[start..<(index + 1 < starts.count ? starts[index + 1] : bytes.count)])
        }
    }

    func testValidHEVCRecoversActualRendererAndClearsPriorCodecError() async throws {
        let controller = PocketLivePreviewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView:
            PocketLivePreviewView(displayLayer: controller.displayLayer, isActive: true))
        window.makeKeyAndVisible()
        defer { controller.disconnect(); window.isHidden = true }
        let generation = controller.connect()
        controller.receive([0, 0, 0, 1, 0x67, 0x42, 0, 0x1e], generation: generation)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(controller.phase, .failed)
        XCTAssertNotNil(controller.failureMessage)
        let units = try units()
        for tick in 0..<50 {
            controller.receive(units[tick % units.count], generation: generation)
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertEqual(controller.phase, .live)
        XCTAssertNil(controller.failureMessage)
        XCTAssertEqual(controller.pictureOrientation, .landscape)
        controller.disconnect()
        controller.receive(units[0], generation: generation)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(controller.phase, .disconnected)
        XCTAssertNil(controller.pictureOrientation)
    }

    func testOldVideoGenerationCannotPopulateReconnectedPreview() async throws {
        let controller = PocketLivePreviewController()
        let old = controller.connect()
        controller.disconnect()
        let current = controller.connect()
        XCTAssertNotEqual(old, current)
        controller.receive(try XCTUnwrap(units().first), generation: old)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(controller.phase, .waitingForPicture)
        XCTAssertNil(controller.pictureOrientation)
        controller.disconnect()
    }
}
