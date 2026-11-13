import Combine
import OpenCineDJI
import OpenCineDJIApple
import SwiftUI
import XCTest
@testable import PocketHead

@MainActor
final class CameraIntegrationTests: XCTestCase {
    private func admission() -> DJICommandAdmission {
        DJICommandAdmission(owner: DJICommandOwner(), isCurrent: { true })
    }

    private func report(recording: Bool) -> Duml.Frame {
        var bytes = [UInt8](repeating: 0, count: 13)
        bytes[0] = recording ? 0x80 : 0
        return Duml.Frame(sender: 1, receiver: Duml.senderApp, seq: 1, flags: 0,
                          cmdSet: 2, cmdId: 0x80, payload: bytes)
    }

    func testRecordingUsesActualWireAndWaitsForTelemetryAfterACK() {
        var now = 0.0
        var sent: [Duml.Frame] = []
        let controller = PocketRecordingController(now: { now })
        controller.receive(report(recording: false))
        let endpoint = DjiAppleControlEndpoint(writeAdmittedDatalink: { frame, gate in
            guard gate.isCurrent else { return .skipped }
            sent.append(frame)
            return .queued(42)
        })
        let timing = DjiAppleExchangeTiming(now: { now }, schedule: { _, _ in })
        XCTAssertTrue(controller.requestToggle(endpoint: endpoint, admission: admission(), isCurrent: { true }, timing: timing))
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].cmdSet, 2)
        XCTAssertEqual(sent[0].cmdId, 2)
        XCTAssertEqual(sent[0].payload, [1])
        controller.receive(Duml.Frame(sender: 1, receiver: Duml.senderApp, seq: 42, flags: 0x80,
                                     cmdSet: 2, cmdId: 2, payload: [0]))
        XCTAssertEqual(controller.isRecording, false)
        XCTAssertEqual(controller.target, true)
        now = 0.3
        controller.receive(report(recording: true))
        XCTAssertEqual(controller.isRecording, true)
        XCTAssertNil(controller.target)
        XCTAssertTrue(controller.requestToggle(endpoint: endpoint, admission: admission(), isCurrent: { true }, timing: timing))
        XCTAssertEqual(sent.last?.payload, [0])
    }

    func testRetiredRecordingExchangeCannotAffectNewConnection() {
        var scheduled: [@MainActor @Sendable () -> Void] = []
        var errors: [String] = []
        var current = true
        let controller = PocketRecordingController(now: { 0 })
        controller.onFailure = { errors.append($0) }
        controller.receive(report(recording: false))
        XCTAssertTrue(controller.requestToggle(endpoint: .init(writeAdmittedDatalink: { _, _ in .queued(1) }),
            admission: admission(), isCurrent: { current }, timing: .init(now: { 0 }, schedule: { _, task in scheduled.append(task) })))
        current = false
        controller.reset()
        scheduled.forEach { $0() }
        XCTAssertNil(controller.isRecording)
        XCTAssertNil(controller.target)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertFalse(controller.canToggle)
    }

    func testGimbalDisconnectRetiresPreviewZoomAndRecordingTogether() {
        let preview = PocketLivePreviewController()
        let gimbal = Pocket4ProGimbal(preview: preview)
        _ = preview.connect()
        gimbal.phase = .connected
        let now = ProcessInfo.processInfo.systemUptime
        gimbal.zoomState.observe(3, at: now)
        XCTAssertTrue(gimbal.zoomState.beginContinuous(increasing: true, maximum: 12, at: now))
        gimbal.recording.receive(report(recording: false))
        XCTAssertTrue(gimbal.recording.requestToggle(
            endpoint: .init(writeAdmittedDatalink: { _, _ in .queued(1) }), admission: admission(),
            isCurrent: { true }, timing: .init(now: { now }, schedule: { _, _ in })))
        let oldGeneration = gimbal.generation
        gimbal.disconnect()
        XCTAssertNotEqual(gimbal.generation, oldGeneration)
        XCTAssertEqual(gimbal.phase, .disconnected)
        XCTAssertEqual(preview.phase, .disconnected)
        XCTAssertFalse(gimbal.zoomState.isAdjusting)
        XCTAssertNil(gimbal.zoomState.reportedFactor)
        XCTAssertNil(gimbal.isRecording)
        XCTAssertNil(gimbal.recordingTarget)
    }

    func testRejectedRecordingWriteDoesNotChangeReportedState() {
        let controller = PocketRecordingController(now: { 0 })
        controller.receive(report(recording: false))
        var failures = 0
        controller.onFailure = { _ in failures += 1 }
        _ = controller.requestToggle(endpoint: .init(), admission: admission(), isCurrent: { true },
            timing: .init(now: { 0 }, schedule: { _, _ in }))
        XCTAssertEqual(controller.isRecording, false)
        XCTAssertNil(controller.target)
        XCTAssertEqual(failures, 1)
    }

    func testHeldButtonEndsOnDragCancelAndDetachWithoutExtraWrites() {
        for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit] {
            let button = ContinuousZoomButton.HoldButton(frame: .zero)
            var transitions: [Bool] = []
            button.onPress = { transitions.append($0) }
            button.sendActions(for: .touchDown)
            button.sendActions(for: event)
            button.sendActions(for: .touchUpInside)
            XCTAssertEqual(transitions, [true, false])
        }
        let button = ContinuousZoomButton.HoldButton(frame: .zero)
        var transitions: [Bool] = []
        button.onPress = { transitions.append($0) }
        button.sendActions(for: .touchDown)
        button.didMoveToWindow()
        XCTAssertEqual(transitions, [true, false])
    }

    func testDirectionUpdatesDoNotPublishWholePageOrSubprecisionChanges() {
        let model = HeadTrackingViewModel()
        var pageUpdates = 0
        var directionUpdates = 0
        let page = model.objectWillChange.sink { pageUpdates += 1 }
        let direction = model.directionDisplay.objectWillChange.sink { directionUpdates += 1 }
        for tick in 0..<100 {
            model.directionDisplay.update(head: LookAngles(rightDegrees: Double(tick) / 10000, upDegrees: 0),
                                          cameraLook: nil, cameraPose: nil)
        }
        XCTAssertEqual(pageUpdates, 0)
        XCTAssertEqual(directionUpdates, 0)
        model.directionDisplay.update(head: LookAngles(rightDegrees: 0.15, upDegrees: 0),
                                      cameraLook: nil, cameraPose: nil)
        XCTAssertEqual(directionUpdates, 1)
        XCTAssertEqual(pageUpdates, 0)
        withExtendedLifetime((page, direction)) {}
    }

    func testTrackingPumpPublishesDirectionWithoutInvalidatingPage() async throws {
        let model = HeadTrackingViewModel()
        model.demoHead = true
        model.demoCamera = true
        model.start()
        model.calibrate()
        XCTAssertTrue(model.tracking)
        model.demoYawDegrees = 20
        var pageUpdates = 0
        var directionUpdates = 0
        let page = model.objectWillChange.sink { pageUpdates += 1 }
        let direction = model.directionDisplay.objectWillChange.sink { directionUpdates += 1 }
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertTrue(model.tracking)
        XCTAssertGreaterThan(directionUpdates, 3)
        XCTAssertEqual(pageUpdates, 0)
        page.cancel()
        direction.cancel()
        model.suspend()
    }

    func testWiFiAndBLEIdentityNeverAssume4ProForOtherBodies() {
        XCTAssertNil(PocketCameraIdentity.directModel(ssid: nil))
        for ssid in ["OsmoPocket3-123", "OsmoPocket4-123", "OsmoNano-123", "Home WiFi"] {
            XCTAssertNil(PocketCameraIdentity.directModel(ssid: ssid))
        }
        XCTAssertTrue(PocketCameraIdentity.directModel(ssid: "OsmoPocket4P-123")?.isPocket4Pro == true)
        XCTAssertFalse(PocketCameraIdentity.supports(modelId: 0x0020, name: "OsmoPocket4Pro"))
        XCTAssertTrue(PocketCameraIdentity.supports(modelId: 0x0022, name: "My camera"))
    }
}
