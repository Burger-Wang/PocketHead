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
    private(set) var phase: Phase = .disconnected {
        didSet {
            guard phase != oldValue else { return }
            waitingSince = phase == .waitingForAttitude
                ? ProcessInfo.processInfo.systemUptime : nil
            onPhaseChange?()
        }
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

    private var link: DjiAppleDatalink?
    private var heartbeat: Task<Void, Never>?
    private var pairingBLE: DjiAppleBluetoothLink?
    private var pairingExchange: DjiAppleControlExchange?
    private var pairingHeartbeat: DjiAppleSessionHeartbeat?
    private var pairingRun: DjiAppleConnectionRun?
    private var pairingScan: Task<DjiAppleSighting?, Never>?
    private var pairingSSID: String?
    private var waitingSince: TimeInterval?
    private var generation: UInt64 = 0
    private var liveWaypoint: GimbalWaypoint?
    private var receivedAt: TimeInterval?
    private var streamToken: UInt64?
    private var nextStreamToken: UInt64 = 0
    private var nativePitchAtCalibration: Double?
    private var tiltAtCalibration: Double?

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

    var hasCameraWiFiPath: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return DjiAppleWiFiJoiner.isCameraPathReady()
        #endif
    }

    func connect() async {
        disconnect()
        #if targetEnvironment(simulator)
        phase = .failed("请在连接相机 Wi‑Fi 的实体 iPhone 上测试。")
        return
        #else
        guard DjiAppleWiFiJoiner.isCameraPathReady() else {
            phase = .failed("手机尚未取得相机 Wi‑Fi 地址。请在系统设置加入 Pocket 热点后重试。")
            return
        }

        generation &+= 1
        let attempt = generation
        phase = .opening
        let camera = CameraModel.resolve(modelId: 0x0022, name: "OsmoPocket4P")
        let driver = DjiAppleDatalink(
            port: UInt16(camera.datalinkPort), tcpPoke: camera.tcpPoke,
            pairingToken: camera.pairingToken,
            subscriptionKeys: Commands.subscriptionKeys(for: camera)
        )
        link = driver
        driver.onStatusFrame = { [weak self, weak driver] frame in
            guard let self, self.generation == attempt, self.link === driver else { return }
            self.receive(frame)
        }
        do {
            try await driver.open()
            guard generation == attempt, link === driver else { return }
            phase = liveWaypoint == nil ? .waitingForAttitude : .connected
            heartbeat = Task { [weak self, weak driver] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, self.generation == attempt, self.link === driver,
                          driver?.isClosed == false else { return }
                    driver?.keepalive()
                }
            }
        } catch {
            guard generation == attempt else { return }
            driver.onStatusFrame = nil
            driver.close()
            link = nil
            if case DjiAppleDatalink.DatalinkError.localNetworkDenied = error {
                phase = .failed("请在 iPhone 设置中允许 Pocket Head 访问本地网络。")
            } else {
                await connectThroughBluetooth(attempt: attempt, previousError: error)
            }
        }
        #endif
    }

    private enum ManualWiFiError: LocalizedError {
        case networkMissing(String)
        case wrongNetwork(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .networkMissing(let ssid):
                "请在 iPhone 系统设置手动加入相机 Wi‑Fi「\(ssid)」，回到 App 后重试。"
            case .wrongNetwork(let expected, let actual):
                "当前 Wi‑Fi 是「\(actual)」，请手动加入相机「\(expected)」后重试。"
            }
        }
    }

    /// The fallback follows OpenCine's BLE pairing/credential flow, but replaces
    /// its entitlement-gated hotspot apply with a check of the user's manual join.
    private func connectThroughBluetooth(attempt: UInt64, previousError: Error) async {
        guard generation == attempt, !Task.isCancelled else { return }
        phase = .scanningBluetooth
        let ble = DjiAppleBluetoothLink()
        pairingBLE = ble
        guard await ble.waitUntilPoweredOn(), generation == attempt, !Task.isCancelled else {
            if generation == attempt {
                phase = .failed("Wi‑Fi 握手未成功，且蓝牙不可用。请打开蓝牙并允许本 App 访问 Pocket。")
            }
            return
        }
        let scan = Task { () -> DjiAppleSighting? in
            for await sighting in ble.scan() {
                if Task.isCancelled { return nil }
                if sighting.model.isPocket4Pro || sighting.modelId == 0x0022 {
                    return sighting
                }
            }
            return nil
        }
        pairingScan = scan
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(12)) }
            catch { return }
            scan.cancel()
            ble.stopScan()
        }
        let found = await scan.value
        timeout.cancel()
        ble.stopScan()
        pairingScan = nil
        guard generation == attempt, !Task.isCancelled else { return }
        guard let found else {
            phase = .failed("相机握手失败（\(previousError.localizedDescription)）；蓝牙也未发现 Pocket 4 Pro。请在相机上开启无线连接。")
            return
        }

        phase = .pairing
        let exchange = DjiAppleControlExchange(
            endpoint: .init(bluetooth: ble, datalink: nil),
            context: { .init(canTransmit: true) }
        )
        pairingExchange = exchange
        let sessionHeartbeat = DjiAppleSessionHeartbeat(
            endpoint: .init(bluetooth: ble, datalink: nil),
            context: { [weak self] in
                .init(live: self?.phase == .connected, ownedConnection: true,
                      pathReady: DjiAppleWiFiJoiner.isCameraPathReady(), sceneActive: true)
            },
            event: { [weak self] event in
                if event == .cameraPathLost, self?.generation == attempt {
                    self?.disconnect()
                    self?.phase = .failed("相机 Wi‑Fi 已中断，请重新连接。")
                }
            }
        )
        pairingHeartbeat = sessionHeartbeat

        var transport = DjiAppleConnectionTransport(bluetooth: ble)
        transport.network.joinAccessPoint = { [weak self] request in
            guard request.isCurrent() else { throw CancellationError() }
            self?.pairingSSID = request.ssid
            self?.phase = .checkingWiFi(request.ssid)
            guard DjiAppleWiFiJoiner.isCameraPathReady() else {
                throw ManualWiFiError.networkMissing(request.ssid)
            }
            if let currentSSID = await DjiAppleWiFiJoiner.currentSSID(),
               currentSSID != request.ssid {
                throw ManualWiFiError.wrongNetwork(
                    expected: request.ssid, actual: currentSSID
                )
            }
        }

        let run = DjiAppleConnectionRun(
            transport: transport, exchange: exchange, heartbeat: sessionHeartbeat,
            credentials: .init(
                savedPath: { _, _ in .init() },
                resolveWiFi: { _ in .init() },
                joinPolicy: { _, _, _ in .init() },
                validateSSID: { target, ssid, _ in
                    if CameraBodyFamily.ssidConflictsWithBody(
                        ssid: ssid, modelId: target.modelId, advertisedName: target.name
                    ) { throw DjiAppleConnectionRun.Failure.wrongCamera }
                },
                persist: { _, _, _ in }, rejectCached: { _, _ in }
            ),
            native: .init(
                observe: { [weak self] in
                    .init(ownsConnection: true, endpoint: self?.link)
                },
                prepare: { _, _, _ in },
                attach: { [weak self, weak ble, weak exchange, weak sessionHeartbeat] endpoint, _, current in
                    guard let self, current.isCurrent, self.generation == attempt else { return }
                    guard let driver = endpoint as? DjiAppleDatalink else {
                        self.link?.onStatusFrame = nil
                        self.link?.close()
                        self.link = nil
                        exchange?.endpoint = .init(bluetooth: ble, datalink: nil)
                        sessionHeartbeat?.endpoint = .init(bluetooth: ble, datalink: nil)
                        return
                    }
                    self.link = driver
                    driver.onStatusFrame = { [weak self, weak driver] frame in
                        guard let self, self.generation == attempt,
                              self.link === driver else { return }
                        self.receive(frame)
                    }
                    exchange?.endpoint = .init(bluetooth: ble, datalink: driver)
                    sessionHeartbeat?.endpoint = .init(bluetooth: ble, datalink: driver)
                },
                registered: { [weak self] endpoint, _, current in
                    guard let self, current.isCurrent, self.generation == attempt,
                          self.link === endpoint else { return }
                    self.phase = self.liveWaypoint == nil ? .waitingForAttitude : .connected
                }
            ),
            event: { [weak self] event in
                guard let self, self.generation == attempt else { return }
                switch event {
                case .stage(let stage, _):
                    switch stage {
                    case .connectingBluetooth, .pairing, .awaitingApproval, .readingWiFi:
                        self.phase = .pairing
                    case .joiningWiFi, .findingCamera:
                        self.phase = .checkingWiFi(self.pairingSSID ?? found.name)
                    case .openingDatalink:
                        self.phase = .opening
                    case .scanning:
                        self.phase = .scanningBluetooth
                    }
                case .finished(.failure(let error), _):
                    let message = Self.connectionFailureMessage(error)
                    self.disconnect()
                    self.phase = .failed(message)
                case .finished(.success, _), .path, .progress:
                    break
                }
            }
        )
        pairingRun = run
        run.replace(target: DJISighting(
            id: found.id.uuidString, name: found.name,
            model: found.model, modelId: found.modelId
        ), route: .cameraAccessPoint)
    }

    private static func connectionFailureMessage(_ error: Error) -> String {
        if let run = error as? DjiAppleConnectionRun.Failure {
            switch run {
            case .pairingTimeout:
                return "等待相机配对确认超时。请在 Pocket 屏幕上允许连接后重试。"
            case .pairingDeferred, .heldSession:
                return "相机暂未允许新控制会话。请关闭 Mimo 后重试。"
            case .credentialsEmpty, .credentialsRefused, .commandTimeout:
                return "蓝牙已连接，但未取得相机 Wi‑Fi 信息。请确认相机允许配对后重试。"
            case .wrongCamera:
                return "蓝牙发现的设备与当前相机 Wi‑Fi 不匹配。"
            default:
                return "Pocket 连接未完成（\(String(describing: run))）。请重试。"
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func disconnect() {
        generation &+= 1
        endHeadTracking()
        heartbeat?.cancel()
        heartbeat = nil
        pairingScan?.cancel()
        pairingScan = nil
        pairingSSID = nil
        pairingRun?.retire()
        pairingRun = nil
        pairingHeartbeat?.stop()
        pairingHeartbeat = nil
        pairingExchange?.stopBLEDrain()
        pairingExchange = nil
        pairingBLE?.stopScan()
        pairingBLE?.disconnect()
        pairingBLE = nil
        link?.onStatusFrame = nil
        link?.close()
        link = nil
        liveWaypoint = nil
        receivedAt = nil
        phase = .disconnected
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
                  waypoint: waypoint, duration: HeadTrackNative.commandDuration
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

    private func receive(_ frame: Duml.Frame) {
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
