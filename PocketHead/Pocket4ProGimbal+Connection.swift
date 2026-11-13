import Foundation
import OpenCineDJI
import OpenCineDJIApple
import OpenCineMotion

// The facade owns session generation and transport; this module cannot create
// an independent command lifetime.
extension Pocket4ProGimbal {
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
        let ssid = await DjiAppleWiFiJoiner.currentSSID()
        guard generation == attempt, !Task.isCancelled else { return }
        // A camera-subnet address is not a model identity. Unknown/hidden SSIDs
        // must go through the BLE identification path before choosing a profile.
        guard let camera = PocketCameraIdentity.directModel(ssid: ssid) else {
            await connectThroughBluetooth(attempt: attempt,
                previousError: ManualWiFiError.unverifiedModel)
            return
        }
        let driver = DjiAppleDatalink(
            port: UInt16(camera.datalinkPort), tcpPoke: camera.tcpPoke,
            pairingToken: camera.pairingToken,
            subscriptionKeys: Commands.subscriptionKeys(for: camera),
            assembleLiveVideo: true
        )
        link = driver
        driver.onStatusFrame = { [weak self, weak driver] frame in
            guard let self, self.generation == attempt, self.link === driver else { return }
            self.receive(frame)
        }
        bindPreview(to: driver, attempt: attempt, model: camera)
        do {
            try await driver.open(afterHandshake: { [weak self, weak driver] in
                guard let self, self.generation == attempt, self.link === driver else { return }
                _ = self.requestLivePicture()
            })
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
            preview.disconnect()
            previewEnabled = false
            if case DjiAppleDatalink.DatalinkError.localNetworkDenied = error {
                phase = .failed("请在 iPhone 设置中允许「Pocket动态追踪」访问本地网络。")
            } else {
                await connectThroughBluetooth(attempt: attempt, previousError: error)
            }
        }
        #endif
    }

    enum ManualWiFiError: LocalizedError {
        case unverifiedModel
        case networkMissing(String)
        case wrongNetwork(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .unverifiedModel:
                "尚未确认 Pocket 4 Pro 机型，需要蓝牙识别。"
            case .networkMissing(let ssid):
                "请在 iPhone 系统设置手动加入相机 Wi‑Fi「\(ssid)」，回到 App 后重试。"
            case .wrongNetwork(let expected, let actual):
                "当前 Wi‑Fi 是「\(actual)」，请手动加入相机「\(expected)」后重试。"
            }
        }
    }

    /// The fallback follows OpenCine's BLE pairing/credential flow, but replaces
    /// its entitlement-gated hotspot apply with a check of the user's manual join.
    func connectThroughBluetooth(attempt: UInt64, previousError: Error) async {
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
                if PocketCameraIdentity.supports(modelId: sighting.modelId, name: sighting.name) {
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
        guard generation == attempt, !Task.isCancelled else { return }
        pairingScan = nil
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
                        self.preview.disconnect()
                        self.previewEnabled = false
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
                    self.bindPreview(to: driver, attempt: attempt, model: found.model)
                    exchange?.endpoint = .init(bluetooth: ble, datalink: driver)
                    sessionHeartbeat?.endpoint = .init(bluetooth: ble, datalink: driver)
                },
                registered: { [weak self] endpoint, _, current in
                    guard let self, current.isCurrent, self.generation == attempt,
                          self.link === endpoint else { return }
                    self.phase = self.liveWaypoint == nil ? .waitingForAttitude : .connected
                    _ = self.requestLivePicture()
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

    static func connectionFailureMessage(_ error: Error) -> String {
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
        preview.disconnect()
        previewEnabled = false
        previewModel = nil
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
        recording.reset()
        cancelZoom()
        zoomState.reset()
        cameraStatus = CameraStatus()
        notifyZoomChange()
        phase = .disconnected
    }

    func bindPreview(to driver: DjiAppleDatalink, attempt: UInt64, model: CameraModel?) {
        previewModel = model
        previewEnabled = false
        let videoGeneration = preview.connect()
        driver.onAccessUnit = { [weak self, weak driver] bytes in
            guard let self, self.generation == attempt, self.link === driver else { return }
            self.preview.receive(bytes, generation: videoGeneration)
        }
        driver.onVideoDiscontinuity = { [weak self, weak driver] in
            guard let self, self.generation == attempt, self.link === driver else { return }
            self.preview.interrupt(generation: videoGeneration)
        }
    }

    func requestLivePicture() -> Bool {
        guard let driver = link, driver.isFlowHealthy else { return false }
        if !previewEnabled, previewModel?.sendsLiveViewPrepare != false {
            let admission = DJICommandAdmission(owner: driver.commandOwner, isCurrent: { true })
            guard case .queued = driver.sendUntracked(Commands.liveViewPrepare(), admission: admission) else {
                return false
            }
        }
        driver.startLiveView(receiver: previewModel?.liveViewEnableReceiver ?? 0x08)
        previewEnabled = true
        return true
    }

}
