import Foundation
import OpenCineDJI
import OpenCineDJIApple

/// A recording transaction owns one connection generation. Injecting the SDK's
/// endpoint exercises the production wire/exchange path without a physical camera.
@MainActor
final class PocketRecordingController {
    var onChange: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private var state = RecordingControlState()
    private var exchange: DjiAppleControlExchange?
    private var generation: UInt64 = 0
    private let now: () -> TimeInterval

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    var isRecording: Bool? { state.isRecording }
    var target: Bool? { state.pending?.target }
    var canToggle: Bool { state.canToggle(at: now()) }

    @discardableResult
    func requestToggle(endpoint: DjiAppleControlEndpoint, admission: DJICommandAdmission,
                       isCurrent: @escaping () -> Bool,
                       timing: DjiAppleExchangeTiming? = nil) -> Bool {
        guard isCurrent(), let request = state.requestToggle(at: now()) else { return false }
        retireExchange()
        let attempt = generation
        let current = { [weak self] in self?.generation == attempt && isCurrent() }
        let exchange = DjiAppleControlExchange(
            endpoint: endpoint, timing: timing ?? .continuous, context: { .init(canTransmit: current()) },
            event: { [weak self] event in
                guard current() else { return }
                if case .refused(_, let message) = event {
                    self?.fail(requestID: request.id, message: "相机拒绝录制指令：\(message)")
                }
            })
        self.exchange = exchange
        onChange?()
        // An ACK only acknowledges receipt. A 02/80 status report confirms it.
        exchange.submit(.init(request.target ? Commands.recordStart() : Commands.recordStop(),
                              name: request.target ? "开始录制" : "停止录制",
                              retransmits: false, admission: admission)) { [weak self] event in
            guard current() else { return }
            switch event {
            case .failed, .settled(false):
                self?.fail(requestID: request.id, message: "录制指令未能完成，请检查相机模式和连接后重试。")
            case .stage, .settled(true): break
            }
        }
        return true
    }

    func receive(_ frame: Duml.Frame) {
        if frame.cmdSet == 0x02, frame.cmdId == 0x80 {
            var status = CameraStatus()
            if CameraStatusDecoder.apply(frame, to: &status), status.recordingReported {
                let previous = state
                state.observe(status.isRecording, at: now())
                if state.pending == nil { retireExchange() }
                notify(previous)
            }
        }
        exchange?.receive(frame)
    }

    func advance(at now: TimeInterval) {
        let previous = state
        let failure = state.advance(at: now)
        if state.pending == nil { retireExchange() }
        notify(previous)
        if let failure {
            onFailure?(failure == .commandTimedOut
                ? "相机未确认录制状态，请检查相机屏幕后重试。"
                : "相机录制状态回报已中断，请确认相机状态后重试。")
        }
    }

    func reset() {
        generation &+= 1
        let previous = state
        state.reset()
        retireExchange()
        notify(previous)
    }

    private func fail(requestID: UInt64, message: String) {
        guard state.fail(requestID: requestID) else { return }
        retireExchange()
        onChange?()
        onFailure?(message)
    }

    private func retireExchange() {
        exchange?.retire(DjiAppleControlExchange.Error.disconnected)
        exchange = nil
    }

    private func notify(_ previous: RecordingControlState) {
        if previous.isRecording != isRecording || previous.pending?.target != target { onChange?() }
    }
}
