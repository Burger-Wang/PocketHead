import Foundation

/// Bounded absolute lens targets. The readout remains camera-reported, even
/// while the requested target follows a smooth curve on a monotonic clock.
public struct ZoomControlState: Equatable, Sendable {
    public static let interval: TimeInterval = 0.05
    public static let maximumReportAge: TimeInterval = 1.2
    public static let confirmationTimeout: TimeInterval = 3
    public static let continuousSpeed = 1.5
    public static let accelerationTime: TimeInterval = 0.2

    public enum Event: Equatable, Sendable {
        case set(Double)
        case feedbackLost
        case unavailable
        case unconfirmed
    }

    private struct Ramp: Equatable, Sendable {
        let start: Double
        let target: Double
        let startedAt: TimeInterval
        let duration: TimeInterval

        func value(at now: TimeInterval) -> Double {
            let t = min(1, max(0, (now - startedAt) / duration))
            return start + (target - start) * t * t * (3 - 2 * t)
        }
    }

    private struct Continuous: Equatable, Sendable {
        let start: Double
        let increasing: Bool
        let startedAt: TimeInterval

        func value(at now: TimeInterval) -> Double {
            let t = max(0, now - startedAt)
            let acceleration = ZoomControlState.accelerationTime
            let distance = t < acceleration ? t * t / (2 * acceleration) : t - acceleration / 2
            return start + (increasing ? 1 : -1) * ZoomControlState.continuousSpeed * distance
        }
    }

    public private(set) var reportedFactor: Double?
    public private(set) var targetFactor: Double?
    private var reportedAt: TimeInterval?
    private var ramp: Ramp?
    private var continuous: Continuous?
    private var lastSampleAt: TimeInterval?
    private var finalSentAt: TimeInterval?
    private var commandedFactor: Double?
    private var commandedAt: TimeInterval?
    private var movementMaximum: Double?

    public var isAdjusting: Bool { ramp != nil || continuous != nil }
    public var isContinuouslyAdjusting: Bool { continuous != nil }

    public init() {}

    public func hasFreshReport(at now: TimeInterval) -> Bool {
        guard now.isFinite, let reportedAt else { return false }
        return now >= reportedAt && now - reportedAt <= Self.maximumReportAge
    }

    public mutating func observe(_ factor: Double, at now: TimeInterval) {
        guard factor.isFinite, (1...12).contains(factor), now.isFinite,
              reportedAt.map({ now >= $0 }) ?? true else { return }
        reportedFactor = factor
        reportedAt = now
        // A report before the final dispatch cannot confirm that dispatch.
        if let targetFactor, let finalSentAt, now > finalSentAt,
           abs(factor - targetFactor) <= 0.03 { cancel() }
    }

    @discardableResult
    public mutating func request(_ target: Double, maximum: Double, at now: TimeInterval) -> Bool {
        guard target.isFinite, maximum.isFinite, (1...12).contains(maximum),
              (1...maximum).contains(target), hasFreshReport(at: now),
              let reportedFactor else { return false }
        let start = anchor(at: now) ?? reportedFactor
        guard (1...maximum).contains(start) else { return false }
        // Retarget from the current curve instead of jumping to delayed telemetry.
        ramp = Ramp(start: start, target: target, startedAt: now,
                    duration: max(0.35, abs(target - start) / 3.5))
        targetFactor = target
        continuous = nil
        lastSampleAt = nil
        finalSentAt = nil
        movementMaximum = maximum
        return true
    }

    @discardableResult
    public mutating func beginContinuous(increasing: Bool, maximum: Double, at now: TimeInterval) -> Bool {
        guard maximum.isFinite, (1...12).contains(maximum), hasFreshReport(at: now),
              let anchor = anchor(at: now) else { return false }
        let start = anchor
        guard (1...maximum).contains(start) else { return false }
        guard increasing ? start < maximum : start > 1 else { return false }
        continuous = Continuous(start: start, increasing: increasing, startedAt: now)
        ramp = nil
        targetFactor = nil
        lastSampleAt = nil
        finalSentAt = nil
        movementMaximum = maximum
        return true
    }

    public mutating func stopContinuous() {
        if continuous != nil { cancel() }
    }

    private func anchor(at now: TimeInterval) -> Double? {
        if let continuous { return continuous.value(at: now) }
        if let ramp { return ramp.value(at: now) }
        // Reversing immediately after release must not jump to a delayed lens report.
        if let commandedAt, now >= commandedAt, now - commandedAt <= 0.25 { return commandedFactor }
        return reportedFactor
    }

    public mutating func advance(at now: TimeInterval, maximum: Double, allowed: Bool) -> Event? {
        guard isAdjusting else { return nil }
        // A curve belongs to the range in which it was started. Never clamp an
        // old curve to a new mode: that can send either an illegal value or a jump.
        guard allowed, maximum.isFinite, (1...12).contains(maximum),
              movementMaximum == maximum, (targetFactor ?? 1) <= maximum else {
            cancel()
            return .unavailable
        }
        guard hasFreshReport(at: now) else {
            cancel()
            return .feedbackLost
        }
        if let finalSentAt {
            guard now - finalSentAt >= Self.confirmationTimeout else { return nil }
            cancel()
            return .unconfirmed
        }
        guard lastSampleAt.map({ now - $0 >= Self.interval - 1e-9 }) ?? true else { return nil }
        lastSampleAt = now
        if let continuous {
            let factor = min(maximum, max(1, continuous.value(at: now)))
            if continuous.increasing ? factor >= maximum : factor <= 1 { cancel() }
            return command(factor, maximum: maximum, at: now)
        }
        guard let ramp, let targetFactor else { return nil }
        if now >= ramp.startedAt + ramp.duration {
            finalSentAt = now
            return command(targetFactor, maximum: maximum, at: now)
        }
        return command(ramp.value(at: now), maximum: maximum, at: now)
    }

    private mutating func command(_ factor: Double, maximum: Double, at now: TimeInterval) -> Event {
        guard factor.isFinite, (1...maximum).contains(factor) else {
            cancel()
            return .unavailable
        }
        commandedFactor = factor
        commandedAt = now
        return .set(factor)
    }

    public mutating func cancel() {
        ramp = nil
        continuous = nil
        targetFactor = nil
        lastSampleAt = nil
        finalSentAt = nil
        movementMaximum = nil
    }

    public mutating func reset() { self = Self() }
}
