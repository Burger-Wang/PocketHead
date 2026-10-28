import Foundation

@MainActor
final class HeadTrackingViewModel: ObservableObject {
    let sensor = HeadphoneMotionService()

    @Published private(set) var tracking = false
    @Published private(set) var statusMessage = "连接 AirPods 后，面向前方并校准。"
    @Published private(set) var errorToast: String?
    @Published private(set) var cameraPose = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    @Published private(set) var targetPose = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    @Published private(set) var cameraPoseAvailable = false
    @Published private(set) var look = LookAngles.zero
    @Published private(set) var preset: FollowPreset? = .standard

    @Published var demoHead = false {
        didSet {
            stopTracking()
            demoYawDegrees = 0
            demoPitchDegrees = 0
            if demoHead {
                sensor.stop()
            } else if pumpTask != nil {
                sensor.start()
            }
            statusMessage = demoHead ? "模拟头部已启用。面向前方并校准。" : "等待 AirPods 姿态数据。"
        }
    }
    @Published var demoCamera = false {
        didSet {
            if oldValue { simulatedGimbal.endHeadTracking() }
            else { realGimbal.endHeadTracking() }
            stopTracking()
            if demoCamera { realGimbal.disconnect() }
            statusMessage = demoCamera
                ? "模拟云台已启用。面向前方并校准。"
                : "加入相机 Wi‑Fi 后，点击连接 Pocket。"
        }
    }
    @Published var demoYawDegrees = 0.0
    @Published var demoPitchDegrees = 0.0
    @Published var sensitivity = FollowPreset.standard.settings.sensitivity { didSet { syncSettings() } }
    @Published var deadZoneDegrees = FollowPreset.standard.settings.deadZoneDegrees { didSet { syncSettings() } }
    @Published var smoothingSeconds = FollowPreset.standard.settings.smoothingSeconds { didSet { syncSettings() } }
    @Published var maximumSpeed = FollowPreset.standard.settings.maxSpeedDegreesPerSecond { didSet { syncSettings() } }

    private var engine = HeadTrackingEngine(limits: .referencePocket4Pro)
    private let simulatedGimbal = SimulatedGimbal()
    private let realGimbal = Pocket4ProGimbal()
    private var gimbal: any HeadTrackGimbal { demoCamera ? simulatedGimbal : realGimbal }
    @Published private var connectionRevision: UInt64 = 0
    private var connectTask: Task<Void, Never>?
    private var errorToastDismissTask: Task<Void, Never>?
    private var errorToastRevision: UInt64 = 0
    private var pumpTask: Task<Void, Never>?
    private var previousTick: TimeInterval?
    private var calibratedSensorGeneration: UInt64?
    private var calibrationCameraPose = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    private var isInBackground = false

    init() {
        sensor.onFailure = { [weak self] message in
            if self?.tracking == true { self?.stopTracking() }
            self?.reportError("AirPods 姿态读取失败：\(message)")
        }
        realGimbal.onPhaseChange = { [weak self] in
            guard let self else { return }
            self.connectionRevision &+= 1
            if self.tracking && self.realGimbal.observation == nil {
                self.stopTracking()
                self.statusMessage = "相机反馈中断，头追已安全停止。请重新连接并校准。"
                if case .failed(let message) = self.realGimbal.phase {
                    self.showErrorToast(message)
                } else {
                    self.showErrorToast(self.statusMessage)
                }
            } else if !self.tracking && !self.demoCamera {
                switch self.realGimbal.phase {
                case .disconnected:
                    self.statusMessage = "加入相机 Wi‑Fi 后，点击连接 Pocket。"
                case .opening, .scanningBluetooth, .pairing, .checkingWiFi:
                    self.statusMessage = "正在连接 Pocket 控制链路。"
                case .waitingForAttitude:
                    self.statusMessage = "已建立控制链路，等待云台姿态。"
                case .connected:
                    self.statusMessage = "Pocket 已连接。面向前方并校准。"
                case .failed(let message):
                    self.statusMessage = "相机连接失败，请查看上方提示后重试。"
                    self.showErrorToast(message)
                }
            }
        }
        #if targetEnvironment(simulator)
        demoHead = true
        demoCamera = true
        statusMessage = "模拟头部已启用。面向前方并校准。"
        #else
        statusMessage = "加入相机 Wi‑Fi 后，点击连接 Pocket。"
        #endif
    }

    var cameraModeTitle: String {
        demoCamera ? "模拟云台" : realGimbal.title
    }

    var cameraModeDetail: String {
        demoCamera ? "实体相机未参与控制" : realGimbal.detail
    }

    var cameraIsConnecting: Bool {
        switch realGimbal.phase {
        case .opening, .scanningBluetooth, .pairing, .checkingWiFi, .waitingForAttitude: true
        default: false
        }
    }
    var cameraIsConnected: Bool { realGimbal.phase == .connected }
    var canRecenterCamera: Bool { !demoCamera && realGimbal.observation != nil }

    func dismissErrorToast() {
        errorToastRevision &+= 1
        errorToastDismissTask?.cancel()
        errorToastDismissTask = nil
        errorToast = nil
    }

    func connectCamera() {
        guard !demoCamera else { return }
        stopTracking()
        connectTask?.cancel()
        connectTask = Task { [weak self] in await self?.realGimbal.connect() }
    }

    private func connectCameraIfAvailableOnActivation() {
        guard !demoCamera, !cameraIsConnected, !cameraIsConnecting,
              realGimbal.hasCameraWiFiPath else { return }
        connectCamera()
    }

    func disconnectCamera() {
        stopTracking()
        connectTask?.cancel()
        connectTask = nil
        realGimbal.disconnect()
        statusMessage = "相机已断开。重新连接后请再次校准。"
    }

    func recenterCamera() {
        guard !demoCamera else { return }
        stopTracking()
        realGimbal.recenter()
    }

    var displayLook: LookAngles {
        if tracking { return look }
        if demoHead {
            return LookAngles(rightDegrees: demoYawDegrees, upDegrees: demoPitchDegrees)
        }
        return .zero
    }

    var cameraLook: LookAngles? {
        guard tracking else { return nil }
        return LookAngles(
            rightDegrees: cameraPose.panDegrees - calibrationCameraPose.panDegrees,
            upDegrees: cameraPose.tiltDegrees - calibrationCameraPose.tiltDegrees
        )
    }

    func start() {
        if !demoHead { sensor.start() }
        guard pumpTask == nil else { return }
        previousTick = ProcessInfo.processInfo.systemUptime
        pumpTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
        connectCameraIfAvailableOnActivation()
    }

    func becameActive() {
        isInBackground = false
        start()
    }

    func enteredBackground() {
        isInBackground = true
        if !tracking || !hasBackgroundReservation {
            suspend()
        }
    }

    private var hasBackgroundReservation: Bool {
        if #available(iOS 26.0, *) {
            return ContinuedTrackingSession.shared.isReserved
        }
        return false
    }

    func suspend() {
        stopTracking()
        if !isInBackground { releaseIdleResources() }
    }

    private func releaseIdleResources() {
        connectTask?.cancel()
        connectTask = nil
        realGimbal.disconnect()
        pumpTask?.cancel()
        pumpTask = nil
        previousTick = nil
        sensor.stop()
    }

    func calibrate() {
        stopTracking(keepingBackgroundTask: true)
        defer {
            if !tracking, #available(iOS 26.0, *) {
                ContinuedTrackingSession.shared.end(success: false)
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard let head = currentSample(now: now) else {
            reportError("尚无头部姿态数据，无法校准。")
            return
        }
        guard let camera = gimbal.observation else {
            reportError("云台姿态不可用，无法校准。")
            return
        }
        do {
            try engine.calibrate(
                head: head,
                gimbal: camera.pose,
                gimbalMeasuredAt: camera.measuredAt,
                now: now
            )
            guard gimbal.beginHeadTracking() else {
                engine.reset()
                reportError("云台尚未就绪，无法开始头追。")
                return
            }
            var foregroundOnly = false
            if !demoHead && !demoCamera {
                if #available(iOS 26.0, *) {
                    let backgroundReserved = ContinuedTrackingSession.shared.begin(
                        onExpired: { [weak self] in
                            self?.stopTracking()
                            self?.reportError("后台头追任务已结束，请重新校准。")
                        },
                        onFailed: { [weak self] reason in
                            guard let self else { return }
                            if self.isInBackground {
                                self.stopTracking()
                                self.reportError(reason)
                            } else {
                                self.statusMessage = "后台头追不可用，当前仅前台运行。"
                                self.showErrorToast("\(reason) 当前仅前台运行。")
                            }
                        }
                    )
                    if !backgroundReserved {
                        foregroundOnly = true
                        showErrorToast("\(ContinuedTrackingSession.shared.startFailureMessage) 当前仅前台运行。")
                    }
                } else {
                    foregroundOnly = true
                }
            }
            tracking = true
            calibratedSensorGeneration = demoHead ? nil : sensor.streamGeneration
            look = .zero
            cameraPose = camera.pose
            targetPose = camera.pose
            calibrationCameraPose = camera.pose
            statusMessage = foregroundOnly
                ? "前方已校准，头追仅在前台运行。"
                : "前方已校准，头追运行中。"
        } catch CalibrationError.movingHead {
            reportError("请保持头部静止，再校准前方。")
        } catch CalibrationError.staleHead {
            reportError("头部数据已过期，请检查 AirPods 连接。")
        } catch CalibrationError.staleGimbal {
            reportError("云台姿态已过期，请重试。")
        } catch {
            reportError("当前云台姿态无法作为校准起点。")
        }
    }

    func stopTracking() {
        stopTracking(keepingBackgroundTask: false)
    }

    private func stopTracking(keepingBackgroundTask: Bool) {
        let wasTracking = tracking
        tracking = false
        calibratedSensorGeneration = nil
        engine.reset()
        gimbal.endHeadTracking()
        look = .zero
        if wasTracking {
            statusMessage = "头追已停止。面向前方重新校准。"
        }
        if !keepingBackgroundTask {
            if #available(iOS 26.0, *) {
                ContinuedTrackingSession.shared.end(success: true)
            }
            if isInBackground { releaseIdleResources() }
        }
    }

    func applyPreset(_ newPreset: FollowPreset) {
        let settings = newPreset.settings
        sensitivity = settings.sensitivity
        deadZoneDegrees = settings.deadZoneDegrees
        smoothingSeconds = settings.smoothingSeconds
        maximumSpeed = settings.maxSpeedDegreesPerSecond
        syncSettings()
        preset = newPreset
    }

    private func currentSample(now: TimeInterval) -> HeadMotionSample? {
        if demoHead {
            let yaw = Quaternion.rotation(axisX: 0, axisY: 0, axisZ: 1, degrees: -demoYawDegrees)
            let pitch = Quaternion.rotation(axisX: 1, axisY: 0, axisZ: 0, degrees: demoPitchDegrees)
            return HeadMotionSample(
                measuredAt: now,
                orientation: yaw.multiplied(by: pitch),
                angularSpeedRadPerSecond: 0
            )
        }
        return sensor.latestSample
    }

    private func syncSettings() {
        let settings = FollowSettings(
            sensitivity: sensitivity,
            deadZoneDegrees: deadZoneDegrees,
            smoothingSeconds: smoothingSeconds,
            maxSpeedDegreesPerSecond: maximumSpeed
        )
        engine.settings = settings
        if let preset, preset.settings != settings {
            self.preset = nil
        }
    }

    private func reportError(_ message: String) {
        statusMessage = message
        showErrorToast(message)
    }

    private func showErrorToast(_ message: String) {
        errorToastDismissTask?.cancel()
        errorToastRevision &+= 1
        let revision = errorToastRevision
        errorToast = message
        errorToastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.errorToastRevision == revision else { return }
            self.dismissErrorToast()
        }
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, min(now - (previousTick ?? now), 0.25))
        previousTick = now
        gimbal.advance(elapsed: elapsed, now: now)
        if let observation = gimbal.observation {
            cameraPose = observation.pose
            cameraPoseAvailable = true
        } else {
            cameraPoseAvailable = false
        }

        guard tracking else { return }
        if !demoHead && calibratedSensorGeneration != sensor.streamGeneration {
            stopTracking()
            reportError("AirPods 连接状态变化，头追已停止。请重新校准。")
            return
        }
        guard let camera = gimbal.observation,
              now >= camera.measuredAt,
              now - camera.measuredAt <= HeadTrackingEngine.maximumGimbalAge else {
            stopTracking()
            reportError("云台姿态中断，头追已安全停止。请重新校准。")
            return
        }
        guard let head = currentSample(now: now),
              now >= head.measuredAt,
              now - head.measuredAt <= HeadTrackingEngine.maximumHeadAge else {
            stopTracking()
            if case .failed(let message) = sensor.status {
                reportError("AirPods 姿态读取失败：\(message)")
            } else {
                reportError("姿态数据中断，头追已安全停止。请重新校准。")
            }
            return
        }
        if let nextTarget = engine.update(head: head, now: now) {
            targetPose = nextTarget
            look = engine.lastLook
            if !gimbal.submit(nextTarget, measuredAt: head.measuredAt) {
                stopTracking()
                reportError("云台控制中断，头追已安全停止。请重新校准。")
            }
        }
    }
}
