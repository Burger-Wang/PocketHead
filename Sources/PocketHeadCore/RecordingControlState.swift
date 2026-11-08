import Foundation

/// A write/ACK is not proof of recording. Only camera telemetry changes the
/// reported value, and each request belongs to one connection lifetime.
public struct RecordingControlState: Equatable, Sendable {
    public static let maximumReportAge: TimeInterval = 5
    public static let commandTimeout: TimeInterval = 5

    public struct Request: Equatable, Sendable {
        public let id: UInt64
        public let target: Bool
        public let startedAt: TimeInterval
    }

    public enum Failure: Equatable, Sendable {
        case commandTimedOut
        case reportExpired
    }

    public private(set) var isRecording: Bool?
    public private(set) var pending: Request?
    private var reportedAt: TimeInterval?
    private var serial: UInt64 = 0

    public init() {}

    public func canToggle(at now: TimeInterval) -> Bool {
        guard pending == nil, isRecording != nil, let reportedAt else { return false }
        return now >= reportedAt && now - reportedAt <= Self.maximumReportAge
    }

    public mutating func requestToggle(at now: TimeInterval) -> Request? {
        guard canToggle(at: now), let isRecording else { return nil }
        serial &+= 1
        let request = Request(id: serial, target: !isRecording, startedAt: now)
        pending = request
        return request
    }

    public mutating func observe(_ recording: Bool, at now: TimeInterval) {
        isRecording = recording
        reportedAt = now
        if pending?.target == recording { pending = nil }
    }

    @discardableResult
    public mutating func fail(requestID: UInt64) -> Bool {
        guard pending?.id == requestID else { return false }
        pending = nil
        return true
    }

    public mutating func advance(at now: TimeInterval) -> Failure? {
        if let reportedAt,
           now < reportedAt || now - reportedAt > Self.maximumReportAge {
            let hadPendingRequest = pending != nil
            isRecording = nil
            self.reportedAt = nil
            pending = nil
            return hadPendingRequest ? .reportExpired : nil
        }
        if let pending, now < pending.startedAt || now - pending.startedAt >= Self.commandTimeout {
            self.pending = nil
            return .commandTimedOut
        }
        return nil
    }

    public mutating func reset() {
        serial &+= 1
        isRecording = nil
        reportedAt = nil
        pending = nil
    }
}
