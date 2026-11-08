import Foundation

/// Screen interaction only. Motion samples must never reset these deadlines.
public struct TouchGuardState: Equatable, Sendable {
    public static let inactivityDuration: TimeInterval = 3
    public static let unlockDuration: TimeInterval = 1.5
    public static let dimmingDuration: TimeInterval = 1

    public static func brightnessDuringDimming(from initial: Double, elapsed: TimeInterval) -> Double {
        let progress = min(1, max(0, elapsed / dimmingDuration))
        let easedProgress = progress * progress * (3 - 2 * progress)
        return initial + (min(initial, 0.05) - initial) * easedProgress
    }

    public private(set) var isActive = false
    public private(set) var isDimmed = false
    // Keep swallowing the current touch sequence after a successful hold.
    public private(set) var isUnlocking = false
    public private(set) var dimDeadline: TimeInterval?
    public private(set) var holdStartedAt: TimeInterval?
    private var touches: Set<Int> = []
    private var unlockTouch: Int?

    public init() {}

    public var nextDeadline: TimeInterval? {
        guard isActive, !isUnlocking else { return nil }
        return holdStartedAt.map { $0 + Self.unlockDuration } ?? dimDeadline
    }

    public func holdProgress(at now: TimeInterval) -> Double {
        if isUnlocking { return 1 }
        guard let holdStartedAt else { return 0 }
        return min(1, max(0, (now - holdStartedAt) / Self.unlockDuration))
    }

    public mutating func enter(at now: TimeInterval) {
        self = Self()
        isActive = true
        dimDeadline = now + Self.inactivityDuration
    }

    public mutating func exit() {
        self = Self()
    }

    public mutating func touchBegan(id: Int, canUnlock: Bool, at now: TimeInterval) {
        guard isActive, touches.insert(id).inserted else { return }
        isDimmed = false
        dimDeadline = nil
        guard !isUnlocking else { return }
        if touches.count == 1, canUnlock {
            unlockTouch = id
            holdStartedAt = now
        } else {
            cancelHold()
        }
    }

    public mutating func touchMoved(id: Int, canUnlock: Bool) {
        guard isActive, !isUnlocking, touches.contains(id) else { return }
        if unlockTouch == id, !canUnlock { cancelHold() }
    }

    public mutating func touchEnded(id: Int, cancelled: Bool, at now: TimeInterval) {
        guard isActive, touches.contains(id) else { return }
        // The main-thread timer may be delayed. A release after the hold deadline
        // still counts, but a cancelled touch must not complete a hold.
        if !cancelled { advance(at: now) }
        touches.remove(id)
        if unlockTouch == id { cancelHold() }
        if isUnlocking {
            if touches.isEmpty { exit() }
        } else if touches.isEmpty {
            dimDeadline = now + Self.inactivityDuration
        }
    }

    public mutating func cancelTouches(at now: TimeInterval) {
        guard isActive else { return }
        if isUnlocking {
            exit()
            return
        }
        touches.removeAll()
        cancelHold()
        isDimmed = false
        dimDeadline = now + Self.inactivityDuration
    }

    public mutating func advance(at now: TimeInterval) {
        guard isActive, !isUnlocking else { return }
        if let holdStartedAt, touches.count == 1,
           now >= holdStartedAt + Self.unlockDuration {
            isUnlocking = true
            isDimmed = false
            dimDeadline = nil
        } else if touches.isEmpty, let dimDeadline, now >= dimDeadline {
            isDimmed = true
            self.dimDeadline = nil
        }
    }

    private mutating func cancelHold() {
        unlockTouch = nil
        holdStartedAt = nil
    }
}
