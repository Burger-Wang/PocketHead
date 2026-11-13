import Foundation
import OpenCineDJI
import OpenCineDJIApple
import OpenCineMotion

/// A deliberately small, manual-Wi-Fi Pocket 4 Pro path. A DHCP address alone
/// never counts as a connection: the DJI datalink handshake and a fresh gimbal
/// attitude are required before targets can be sent.
@MainActor
final class Pocket4ProGimbal: HeadTrackGimbal {
    enum Phase: Equatable {
        case disconnected
        case opening
        case scanningBluetooth
        case pairing
        case checkingWiFi(String)
        case waitingForAttitude
        case connected
        case failed(String)
    }

    let isSimulation = false
    var onPhaseChange: (() -> Void)?
    var onRecordingChange: (() -> Void)?
    var onRecordingFailure: ((String) -> Void)?
    var onZoomChange: (() -> Void)?
    var onZoomFailure: ((String) -> Void)?
    var phase: Phase = .disconnected {
        didSet {
            guard phase != oldValue else { return }
            waitingSince = phase == .waitingForAttitude
                ? ProcessInfo.processInfo.systemUptime : nil
            if oldValue == .connected && phase != .connected {
                recording.reset()
                cancelZoom()
            }
            onPhaseChange?()
        }
    }
    var isRecording: Bool? { recording.isRecording }
    var recordingTarget: Bool? { recording.target }
    var canControlRecording: Bool {
        phase == .connected && link?.isFlowHealthy == true
            && recording.canToggle
    }

    var title: String {
        switch phase {
        case .disconnected: "相机未连接"
        case .opening: "正在建立连接"
        case .scanningBluetooth: "搜索相机蓝牙"
        case .pairing: "正在配对相机"
        case .checkingWiFi: "检查相机 Wi‑Fi"
        case .waitingForAttitude: "等待云台反馈"
        case .connected: "实体云台已连接"
        case .failed: "连接失败"
        }
    }

    var detail: String {
        switch phase {
        case .disconnected: "请先加入相机 Wi‑Fi"
        case .opening: "正在建立控制链路"
        case .scanningBluetooth: "蓝牙扫描中"
        case .pairing: "请在相机上确认配对"
        case .checkingWiFi: "正在检查相机 Wi‑Fi"
        case .waitingForAttitude: "等待实时云台姿态"
        case .connected: "实时云台姿态接收中"
        case .failed: "点击连接重试"
        }
    }

    var link: DjiAppleDatalink?
    var heartbeat: Task<Void, Never>?
    var pairingBLE: DjiAppleBluetoothLink?
    var pairingExchange: DjiAppleControlExchange?
    var pairingHeartbeat: DjiAppleSessionHeartbeat?
    var pairingRun: DjiAppleConnectionRun?
    var pairingScan: Task<DjiAppleSighting?, Never>?
    var pairingSSID: String?
    var waitingSince: TimeInterval?
    var generation: UInt64 = 0
    var liveWaypoint: GimbalWaypoint?
    var receivedAt: TimeInterval?
    var streamToken: UInt64?
    var nextStreamToken: UInt64 = 0
    var nativePitchAtCalibration: Double?
    var tiltAtCalibration: Double?
    let recording = PocketRecordingController()
    var cameraStatus = CameraStatus()
    var zoomState = ZoomControlState()
    var zoomTask: Task<Void, Never>?
    var zoomSequences: [UInt16: TimeInterval] = [:]
    var lastZoomLens: UInt16?
    struct ZoomPresentation: Equatable {
        let factor: Double?
        let target: Double?
        let maximum: Double
        let reason: String?
        let atLowerLimit: Bool
        let atUpperLimit: Bool
    }
    var lastZoomPresentation: ZoomPresentation?
    let preview: PocketLivePreviewController
    var previewModel: CameraModel?
    var previewEnabled = false

    init(preview: PocketLivePreviewController) {
        self.preview = preview
        recording.onChange = { [weak self] in self?.onRecordingChange?() }
        recording.onFailure = { [weak self] message in self?.onRecordingFailure?(message) }
        preview.onRequestKeyframe = { [weak self] in self?.requestLivePicture() ?? false }
    }

    var observation: GimbalObservation? {
        guard phase == .connected, link?.isFlowHealthy == true,
              let waypoint = liveWaypoint, let receivedAt,
              ProcessInfo.processInfo.systemUptime - receivedAt <= HeadTrackingEngine.maximumGimbalAge
        else { return nil }
        return GimbalObservation(
            pose: GimbalPose(panDegrees: waypoint.yawDeg, tiltDegrees: waypoint.pitchDeg),
            measuredAt: receivedAt
        )
    }

    func advance(elapsed: TimeInterval, now: TimeInterval) {
        guard phase == .connected || phase == .waitingForAttitude else { return }
        if !DjiAppleWiFiJoiner.isCameraPathReady() || link?.isClosed != false {
            disconnect()
            phase = .failed("相机 Wi‑Fi 或控制链路已中断，请重新连接。")
        } else if phase == .connected, let receivedAt,
                  now - receivedAt > HeadTrackingEngine.maximumGimbalAge {
            endHeadTracking()
            phase = .waitingForAttitude
        } else if phase == .waitingForAttitude,
                  let waitingSince, now - waitingSince > 5 {
            disconnect()
            phase = .failed("控制握手成功，但 5 秒内没有收到云台姿态。请检查相机是否处于可控制状态后重试。")
        }
        recording.advance(at: now)
        notifyZoomChange()
    }

    @discardableResult
    func requestRecordingToggle() -> Bool {
        guard canControlRecording, let driver = link else { return false }
        let attempt = generation
        return recording.requestToggle(endpoint: .init(datalink: driver),
            admission: DJICommandAdmission(owner: driver.commandOwner, isCurrent: { true }),
            isCurrent: { [weak self, weak driver] in
                guard let self, let driver else { return false }
                return self.generation == attempt && self.link === driver
                    && self.phase == .connected && driver.isFlowHealthy
            })
    }

    func beginHeadTracking() -> Bool {
        guard streamToken == nil, observation != nil,
              let nativePitch = liveWaypoint?.nativePitchDeg, let liveWaypoint,
              nativePitch.isFinite, (-180...180).contains(nativePitch),
              let link, link.isFlowHealthy else { return false }
        nativePitchAtCalibration = nativePitch
        tiltAtCalibration = liveWaypoint.pitchDeg
        nextStreamToken &+= 1
        streamToken = nextStreamToken
        link.beginNativeTargets(token: nextStreamToken)
        return true
    }

    func submit(_ target: GimbalPose, measuredAt: TimeInterval) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= measuredAt, now - measuredAt <= HeadTrackingEngine.maximumHeadAge,
              let token = streamToken, let link, link.isFlowHealthy,
              let live = liveWaypoint, observation != nil,
              let nativePitchAtCalibration, let tiltAtCalibration else {
            endHeadTracking()
            return false
        }
        let nativePitch = GimbalPath.wrapAngle(
            nativePitchAtCalibration - (target.tiltDegrees - tiltAtCalibration)
        )
        let waypoint = GimbalWaypoint(
            yawDeg: target.panDegrees, pitchDeg: target.tiltDegrees,
            zoom: 1, nativePitchDeg: nativePitch
        )
        guard GimbalMoveEngine.canSendNativeTarget(from: live, to: waypoint),
              let frame = Commands.gimbalTimedTarget(
                  waypoint: waypoint,
                  duration: HeadTrackNative.commandDuration
              ), link.noteNativeTarget(frame, token: token) else {
            endHeadTracking()
            return false
        }
        return true
    }

    func endHeadTracking() {
        if let token = streamToken { link?.endNativeTargets(token: token) }
        streamToken = nil
        nativePitchAtCalibration = nil
        tiltAtCalibration = nil
    }

    @discardableResult
    func recenter() -> Bool {
        endHeadTracking()
        guard phase == .connected, observation != nil,
              let link, link.isFlowHealthy else { return false }
        let admission = DJICommandAdmission(owner: link.commandOwner, isCurrent: { true })
        if case .queued = link.send(Commands.gimbalRecenter(), admission: admission) {
            return true
        }
        return false
    }

    @discardableResult
    func flip() -> Bool {
        endHeadTracking()
        guard phase == .connected, observation != nil,
              let link, link.isFlowHealthy else { return false }
        let admission = DJICommandAdmission(owner: link.commandOwner, isCurrent: { true })
        if case .queued = link.send(Commands.gimbalFlip(), admission: admission) {
            return true
        }
        return false
    }

    func receive(_ frame: Duml.Frame) {
        let now = ProcessInfo.processInfo.systemUptime
        CameraStatusDecoder.apply(frame, to: &cameraStatus, model: previewModel)
        preview.observeRecordingAspect(cameraStatus.videoResolution?.ratio)
        if frame.cmdSet == 0, frame.cmdId == 0x99,
           let item = SubscribePush.parse(frame.payload) {
            let measuresZoom = item.name == "cam_lens_state" && CamFov.lensAt14(item.value) != nil
                || item.name == "cam_fov" && cameraStatus.zoomLens == nil && CamFov.rawAt0(item.value) != nil
            if measuresZoom, let factor = cameraStatus.zoomFactor {
                zoomState.observe(factor, at: now)
                if !zoomState.isAdjusting {
                    zoomTask?.cancel()
                    zoomTask = nil
                    zoomSequences.removeAll()
                }
            }
        }
        if frame.cmdSet == 0x02, frame.cmdId == 0xB8, frame.flags & 0x80 != 0,
           let sentAt = zoomSequences.removeValue(forKey: frame.seq), now - sentAt <= 2,
           CameraReply.parse(frame.payload) != .ok {
            failZoom("相机拒绝变焦指令，请检查拍摄模式和倍率上限。")
        }
        notifyZoomChange()
        recording.receive(frame)
        guard frame.cmdSet == 0x04, frame.cmdId == 0x05,
              let waypoint = GimbalWaypoint.from(
                  yawTenth: GimbalStick.yawTenthDeg(frame.payload),
                  pitchTenth: GimbalStick.pitchTenthDeg(frame.payload), zoom: 1,
                  nativePitchTenth: GimbalStick.nativePitchTenthDeg(frame.payload)
              ), waypoint == waypoint.clamped(to: GimbalReach.bounds),
              let native = waypoint.nativePitchDeg,
              native.isFinite, (-180...180).contains(native)
        else { return }
        liveWaypoint = waypoint
        receivedAt = ProcessInfo.processInfo.systemUptime
        if phase == .waitingForAttitude { phase = .connected }
    }
}
