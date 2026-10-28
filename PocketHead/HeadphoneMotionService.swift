import CoreMotion
import Foundation

@MainActor
final class HeadphoneMotionService: NSObject, ObservableObject {
    enum Status: Equatable {
        case unavailable
        case ready
        case streaming
        case failed(String)

        var title: String {
            switch self {
            case .unavailable: "未检测到兼容的 AirPods"
            case .ready: "AirPods 已就绪"
            case .streaming: "姿态数据接收中"
            case .failed: "读取失败"
            }
        }
    }

    @Published private(set) var status: Status = .unavailable
    @Published private(set) var latestSample: HeadMotionSample?
    var onFailure: ((String) -> Void)?

    private let manager = CMHeadphoneMotionManager()
    private let deliveryQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "PocketHead.AirPodsMotion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    private var generation: UInt64 = 0
    private var wantsUpdates = false
    private var recoveryTask: Task<Void, Never>?
    private var streamStartedAt: TimeInterval?
    private var lastStartAttemptAt = -Double.infinity
    private var connectionEventGeneration: UInt64 = 0
    private var lastReportedFailure: String?
    private var lastFailureReportAt = -Double.infinity

    private let staleStreamInterval: TimeInterval = 2
    private let initialSampleTimeout: TimeInterval = 10
    private let retryInterval: TimeInterval = 3

    var streamGeneration: UInt64 { generation }

    override init() {
        super.init()
        manager.delegate = self
        status = manager.isDeviceMotionAvailable ? .ready : .unavailable
        trace("init available=\(manager.isDeviceMotionAvailable) active=\(manager.isDeviceMotionActive) authorization=\(CMHeadphoneMotionManager.authorizationStatus().rawValue)")
    }

    func start() {
        trace("start available=\(manager.isDeviceMotionAvailable) active=\(manager.isDeviceMotionActive) authorization=\(CMHeadphoneMotionManager.authorizationStatus().rawValue)")
        wantsUpdates = true
        startMotionStreamIfAvailable()
        guard recoveryTask == nil else { return }
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self else { return }
                self.recoverIfNeeded()
            }
        }
    }

    func stop() {
        trace("stop active=\(manager.isDeviceMotionActive)")
        wantsUpdates = false
        recoveryTask?.cancel()
        recoveryTask = nil
        connectionEventGeneration &+= 1
        if manager.isConnectionStatusActive {
            manager.stopConnectionStatusUpdates()
        }
        stopMotionStream()
        lastReportedFailure = nil
        status = manager.isDeviceMotionAvailable ? .ready : .unavailable
    }

    private func recoverIfNeeded() {
        guard wantsUpdates else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Let the first Core Motion request finish, including its permission prompt.
        // Retrying while that request is still starting can prevent the first sample.
        if latestSample == nil, let streamStartedAt,
           now - streamStartedAt < initialSampleTimeout { return }
        guard manager.isDeviceMotionAvailable else {
            if manager.isDeviceMotionActive || latestSample != nil {
                stopMotionStream()
            }
            status = .unavailable
            return
        }
        if manager.isDeviceMotionActive {
            let lastMotionAt = latestSample?.measuredAt ?? streamStartedAt ?? now
            let timeout = latestSample == nil ? initialSampleTimeout : staleStreamInterval
            if now - lastMotionAt < timeout { return }
        }
        guard now - lastStartAttemptAt >= retryInterval else { return }
        trace("retry active=\(manager.isDeviceMotionActive) sample=\(latestSample != nil) available=\(manager.isDeviceMotionAvailable)")
        if manager.isDeviceMotionActive || latestSample != nil {
            stopMotionStream()
        }
        startMotionStreamIfAvailable()
    }

    private func startMotionStreamIfAvailable() {
        guard wantsUpdates, !manager.isDeviceMotionActive else { return }
        guard manager.isDeviceMotionAvailable else {
            status = .unavailable
            latestSample = nil
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        trace("startDeviceMotionUpdates authorization=\(CMHeadphoneMotionManager.authorizationStatus().rawValue)")
        lastStartAttemptAt = now
        streamStartedAt = now
        generation &+= 1
        let currentGeneration = generation
        status = .ready
        manager.startDeviceMotionUpdates(to: deliveryQueue) { [weak self] motion, error in
            let sample: HeadMotionSample? = motion.map {
                let rotation = $0.rotationRate
                return HeadMotionSample(
                    measuredAt: $0.timestamp,
                    orientation: Quaternion(
                        w: $0.attitude.quaternion.w,
                        x: $0.attitude.quaternion.x,
                        y: $0.attitude.quaternion.y,
                        z: $0.attitude.quaternion.z
                    ),
                    angularSpeedRadPerSecond: sqrt(
                        rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z
                    )
                )
            }
            let errorMessage = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.wantsUpdates, self.generation == currentGeneration else { return }
                if let sample {
                    if self.latestSample == nil { self.trace("first motion sample") }
                    self.latestSample = sample
                    self.status = .streaming
                    self.lastReportedFailure = nil
                    if !self.manager.isConnectionStatusActive {
                        self.manager.startConnectionStatusUpdates()
                    }
                } else if let errorMessage {
                    self.trace("motion error=\(errorMessage)")
                    self.latestSample = nil
                    let failure = Status.failed(errorMessage)
                    self.status = failure
                    let now = ProcessInfo.processInfo.systemUptime
                    if self.lastReportedFailure != errorMessage ||
                        now - self.lastFailureReportAt >= 15 {
                        self.lastReportedFailure = errorMessage
                        self.lastFailureReportAt = now
                        self.onFailure?(errorMessage)
                    }
                }
            }
        }
    }

    private func stopMotionStream() {
        trace("stopDeviceMotionUpdates active=\(manager.isDeviceMotionActive)")
        generation &+= 1
        manager.stopDeviceMotionUpdates()
        latestSample = nil
        streamStartedAt = nil
    }

    private func headphonesConnected() {
        trace("delegate didConnect active=\(manager.isDeviceMotionActive) available=\(manager.isDeviceMotionAvailable)")
        guard wantsUpdates else { return }
        connectionEventGeneration &+= 1
        // Core Motion also sends didConnect for the stream that just started.
        // Restarting an active stream here can prevent its first callback.
        guard !manager.isDeviceMotionActive else { return }
        startMotionStreamIfAvailable()
    }

    private func headphonesDisconnected() {
        trace("delegate didDisconnect active=\(manager.isDeviceMotionActive) available=\(manager.isDeviceMotionAvailable)")
        guard wantsUpdates else { return }
        connectionEventGeneration &+= 1
        let eventGeneration = connectionEventGeneration
        let now = ProcessInfo.processInfo.systemUptime
        if latestSample == nil, let streamStartedAt,
           now - streamStartedAt < initialSampleTimeout { return }
        // Initial connection monitoring can report an older disconnect event.
        // Keep an already streaming sensor alive if fresh samples still arrive.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.wantsUpdates,
                  self.connectionEventGeneration == eventGeneration else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if let sample = self.latestSample, now - sample.measuredAt < 0.5 { return }
            self.stopMotionStream()
            self.status = self.manager.isDeviceMotionAvailable ? .ready : .unavailable
        }
    }

    private func trace(_ message: String) {
        #if DEBUG
        NSLog("PocketHeadMotion %@", message)
        #endif
    }
}

extension HeadphoneMotionService: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            self?.headphonesConnected()
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            self?.headphonesDisconnected()
        }
    }
}
