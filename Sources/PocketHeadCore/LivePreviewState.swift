import Foundation

/// Picture recovery is independent of the camera's control/recording state.
public struct LivePreviewState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case disconnected, waitingForPicture, live, stalled, failed
    }

    public static let firstPictureTimeout: TimeInterval = 8
    public static let pictureTimeout: TimeInterval = 2
    public static let retryCooldown: TimeInterval = 3
    public static let maximumAutomaticRetries = 3

    public private(set) var phase: Phase = .disconnected
    public private(set) var generation: UInt64 = 0
    public private(set) var automaticRetries = 0
    private var startedAt: TimeInterval?
    private var lastPictureAt: TimeInterval?
    private var lastEnableAt: TimeInterval?

    public init() {}

    @discardableResult
    public mutating func connect(at now: TimeInterval) -> UInt64 {
        generation &+= 1
        phase = .waitingForPicture
        automaticRetries = 0
        startedAt = now
        lastPictureAt = nil
        lastEnableAt = now
        return generation
    }

    public mutating func disconnect() {
        generation &+= 1
        phase = .disconnected
        startedAt = nil
        lastPictureAt = nil
        lastEnableAt = nil
        automaticRetries = 0
    }

    public mutating func pictureArrived(generation: UInt64, at now: TimeInterval) {
        guard generation == self.generation, phase != .disconnected,
              let startedAt, now >= startedAt,
              lastPictureAt.map({ now > $0 }) ?? true else { return }
        lastPictureAt = now
        phase = .live
        automaticRetries = 0
    }

    public mutating func interrupted(generation: UInt64) {
        guard generation == self.generation, phase != .disconnected, phase != .failed else { return }
        phase = .stalled
    }

    public mutating func fail(generation: UInt64) {
        guard generation == self.generation, phase != .disconnected else { return }
        phase = .failed
    }

    public func canRetry(at now: TimeInterval) -> Bool {
        guard phase == .stalled || phase == .failed, let lastEnableAt else { return false }
        return now >= lastEnableAt && now - lastEnableAt >= Self.retryCooldown
    }

    /// True requests one picture-only enable; this never asks to reconnect the socket.
    public mutating func advance(at now: TimeInterval) -> Bool {
        guard phase != .disconnected, phase != .failed, let startedAt else { return false }
        let deadline = lastPictureAt.map { $0 + Self.pictureTimeout }
            ?? startedAt + Self.firstPictureTimeout
        guard phase == .stalled || now >= deadline else { return false }
        phase = .stalled
        guard canRetry(at: now) else { return false }
        guard automaticRetries < Self.maximumAutomaticRetries else {
            phase = .failed
            return false
        }
        automaticRetries += 1
        lastEnableAt = now
        return true
    }

    @discardableResult
    public mutating func retry(at now: TimeInterval) -> Bool {
        guard canRetry(at: now) else { return false }
        phase = .waitingForPicture
        startedAt = now
        lastPictureAt = nil
        lastEnableAt = now
        automaticRetries = 0
        return true
    }
}
