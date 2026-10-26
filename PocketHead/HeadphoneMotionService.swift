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

    var streamGeneration: UInt64 { generation }

    override init() {
        super.init()
        manager.delegate = self
        status = manager.isDeviceMotionAvailable ? .ready : .unavailable
    }

    func start() {
        guard !manager.isDeviceMotionActive else { return }
        guard manager.isDeviceMotionAvailable else {
            status = .unavailable
            latestSample = nil
            return
        }

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
                guard let self, self.generation == currentGeneration else { return }
                if let sample {
                    self.latestSample = sample
                    self.status = .streaming
                } else if let errorMessage {
                    self.latestSample = nil
                    let failure = Status.failed(errorMessage)
                    if self.status != failure {
                        self.status = failure
                        self.onFailure?(errorMessage)
                    }
                }
            }
        }
    }

    func stop() {
        generation &+= 1
        manager.stopDeviceMotionUpdates()
        latestSample = nil
        status = manager.isDeviceMotionAvailable ? .ready : .unavailable
    }
}

extension HeadphoneMotionService: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            self?.status = .ready
            self?.start()
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
}
