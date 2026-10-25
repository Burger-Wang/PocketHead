import Foundation

@MainActor
final class HeadTrackingViewModel: ObservableObject {
    let sensor = HeadphoneMotionService()

    @Published private(set) var tracking = false
    @Published private(set) var statusMessage = "连接 AirPods 后，面向前方并校准。"
    @Published private(set) var cameraPose = GimbalPose(panDegrees: 0, tiltDegrees: 0)
    @Published private(set) var targetPose = GimbalPose(panDegrees: 0, tiltDegrees: 0)
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
    @Published var demoYawDegrees = 0.0
    @Published var demoPitchDegrees = 0.0
    @Published var sensitivity = FollowPreset.standard.settings.sensitivity { didSet { syncSettings() } }
    @Published var deadZoneDegrees = FollowPreset.standard.settings.deadZoneDegrees { didSet { syncSettings() } }
    @Published var smoothingSeconds = FollowPreset.standard.settings.smoothingSeconds { didSet { syncSettings() } }
    @Published var maximumSpeed = FollowPreset.standard.settings.maxSpeedDegreesPerSecond { didSet { syncSettings() } }

    private var engine = HeadTrackingEngine(limits: .referencePocket4Pro)
    private let gimbal: any HeadTrackGimbal
    private var pumpTask: Task<Void, Never>?
    private var previousTick: TimeInterval?
    private var calibratedSensorGeneration: UInt64?
    private var calibrationCameraPose = GimbalPose(panDegrees: 0, tiltDegrees: 0)

    init(gimbal: (any HeadTrackGimbal)? = nil) {
        self.gimbal = gimbal ?? SimulatedGimbal()
        #if targetEnvironment(simulator)
        demoHead = true
        statusMessage = "模拟头部已启用。面向前方并校准。"
        #endif
    }

    var cameraIsSimulated: Bool { gimbal.isSimulation }

    var cameraModeTitle: String {
        if gimbal.isSimulation { return "模拟云台" }
        return gimbal.observation == nil ? "相机未连接" : "相机已连接"
    }

    var cameraModeDetail: String {
        gimbal.isSimulation ? "实体相机尚未连接" : "Pocket 4 Pro 云台姿态"
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
    }

    func suspend() {
        stopTracking()
        pumpTask?.cancel()
        pumpTask = nil
        previousTick = nil
        sensor.stop()
    }

    func calibrate() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let head = currentSample(now: now) else {
            statusMessage = "尚无头部姿态数据，无法校准。"
            return
        }
        gimbal.endHeadTracking()
        guard let camera = gimbal.observation else {
            statusMessage = "云台姿态不可用，无法校准。"
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
                statusMessage = "云台尚未就绪，无法开始头追。"
                return
            }
            tracking = true
            calibratedSensorGeneration = demoHead ? nil : sensor.streamGeneration
            look = .zero
            cameraPose = camera.pose
            targetPose = camera.pose
            calibrationCameraPose = camera.pose
            statusMessage = "前方已校准，头追运行中。"
        } catch CalibrationError.movingHead {
            statusMessage = "请保持头部静止，再校准前方。"
        } catch CalibrationError.staleHead {
            statusMessage = "头部数据已过期，请检查 AirPods 连接。"
        } catch CalibrationError.staleGimbal {
            statusMessage = "云台姿态已过期，请重试。"
        } catch {
            statusMessage = "当前云台姿态无法作为校准起点。"
        }
    }

    func stopTracking() {
        tracking = false
        calibratedSensorGeneration = nil
        engine.reset()
        gimbal.endHeadTracking()
        look = .zero
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

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = max(0, min(now - (previousTick ?? now), 0.25))
        previousTick = now
        gimbal.advance(elapsed: elapsed, now: now)
        if let observation = gimbal.observation {
            cameraPose = observation.pose
        }

        guard tracking else { return }
        if !demoHead && calibratedSensorGeneration != sensor.streamGeneration {
            stopTracking()
            statusMessage = "AirPods 连接状态变化，头追已停止。请重新校准。"
            return
        }
        guard let camera = gimbal.observation,
              now >= camera.measuredAt,
              now - camera.measuredAt <= HeadTrackingEngine.maximumGimbalAge else {
            stopTracking()
            statusMessage = "云台姿态中断，头追已安全停止。请重新校准。"
            return
        }
        guard let head = currentSample(now: now),
              now >= head.measuredAt,
              now - head.measuredAt <= HeadTrackingEngine.maximumHeadAge else {
            stopTracking()
            statusMessage = "姿态数据中断，头追已安全停止。请重新校准。"
            return
        }
        if let nextTarget = engine.update(head: head, now: now) {
            targetPose = nextTarget
            look = engine.lastLook
            if !gimbal.submit(nextTarget, measuredAt: head.measuredAt) {
                stopTracking()
                statusMessage = "云台控制中断，头追已安全停止。请重新校准。"
            }
        }
    }
}
