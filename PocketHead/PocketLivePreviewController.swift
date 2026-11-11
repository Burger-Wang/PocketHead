import AVFoundation
import Foundation
import OpenCineDJI
import os

@MainActor
final class PocketLivePreviewController: ObservableObject {
    let displayLayer = AVSampleBufferDisplayLayer()
    @Published private(set) var phase: LivePreviewState.Phase = .disconnected
    @Published private(set) var canRetry = false
    @Published private(set) var failureMessage: String?
    /// Requests only a new video GOP on the existing datalink, never a reconnect.
    var onRequestKeyframe: (() -> Bool)?

    private var state = LivePreviewState()
    private var monitor: Task<Void, Never>?
    private lazy var pipeline = LivePreviewPipeline(renderer: displayLayer.sampleBufferRenderer)

    init() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
        // Keep screen-awake ownership with the existing touch-guard controller.
        displayLayer.preventsDisplaySleepDuringVideoPlayback = false
    }

    deinit { monitor?.cancel() }

    @discardableResult
    func connect() -> UInt64 {
        monitor?.cancel()
        let generation = state.connect(at: ProcessInfo.processInfo.systemUptime)
        failureMessage = nil
        pipeline.start(generation: generation)
        publish()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll(generation: generation)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return generation
    }

    func disconnect() {
        monitor?.cancel()
        monitor = nil
        state.disconnect()
        pipeline.stop(generation: state.generation)
        failureMessage = nil
        publish()
    }

    func receive(_ accessUnit: [UInt8], generation: UInt64) {
        guard generation == state.generation, phase != .disconnected else { return }
        pipeline.submit(accessUnit, generation: generation)
    }

    func interrupt(generation: UInt64) {
        guard generation == state.generation else { return }
        state.interrupted(generation: generation)
        pipeline.recover(generation: generation)
        publish()
    }

    func retry() {
        guard state.retry(at: ProcessInfo.processInfo.systemUptime) else { return }
        failureMessage = nil
        pipeline.recover(generation: state.generation)
        if onRequestKeyframe?() != true {
            state.fail(generation: state.generation)
            failureMessage = "相机链路尚未就绪，请检查连接后重试"
        }
        publish()
    }

    private func poll(generation: UInt64) {
        pipeline.snapshot { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self, generation == self.state.generation,
                      snapshot.generation == generation, self.phase != .disconnected else { return }
                if let error = snapshot.error {
                    self.failureMessage = error
                    self.state.fail(generation: generation)
                } else if !snapshot.awaitingRandomAccess, snapshot.hasDisplayedImage,
                          let pictureAt = snapshot.lastSubmittedAt {
                    self.state.pictureArrived(generation: generation, at: pictureAt)
                } else if snapshot.awaitingRandomAccess, self.state.phase == .live {
                    self.state.interrupted(generation: generation)
                }
                if self.state.advance(at: ProcessInfo.processInfo.systemUptime) {
                    self.pipeline.recover(generation: generation)
                    if self.onRequestKeyframe?() != true {
                        self.state.fail(generation: generation)
                        self.failureMessage = "相机链路尚未就绪，请检查连接后重试"
                    }
                }
                self.publish()
            }
        }
    }

    private func publish() {
        if phase != state.phase { phase = state.phase }
        let retry = state.canRetry(at: ProcessInfo.processInfo.systemUptime)
        if canRetry != retry { canRetry = retry }
    }
}

/// The input mailbox is bounded before dispatching work. A burst creates one
/// drain, rather than an unbounded Dispatch/Task queue that competes with control.
private final class LivePreviewPipeline: @unchecked Sendable {
    struct Snapshot: Sendable {
        let generation: UInt64
        let lastSubmittedAt: TimeInterval?
        let awaitingRandomAccess: Bool
        let hasDisplayedImage: Bool
        let error: String?
    }

    private enum Event {
        case accessUnit([UInt8], TimeInterval)
        case discontinuity
    }
    private struct Inbox {
        var generation: UInt64 = 0
        var accepting = false
        var events: [Event] = []
        var bytes = 0
        var scheduled = false
    }
    private let inbox = OSAllocatedUnfairLock(initialState: Inbox())
    private let queue = DispatchQueue(label: "pockethead.live-video", qos: .userInitiated)
    private let renderer: AVSampleBufferVideoRenderer
    // The following fields belong exclusively to queue.
    private var generation: UInt64 = 0
    private var builder = LiveVideoSampleBuilder()
    private var awaitingRandomAccess = true
    private var lastSubmittedAt: TimeInterval?
    private var error: String?
    private var flushing = false
    private var flushRevision: UInt64 = 0

    init(renderer: AVSampleBufferVideoRenderer) { self.renderer = renderer }

    func start(generation: UInt64) {
        replaceInbox(generation: generation, accepting: true)
        queue.async { [self] in
            guard isCurrent(generation) else { return }
            self.generation = generation
            builder.reset()
            error = nil
            lastSubmittedAt = nil
            flush(generation: generation)
        }
    }

    func stop(generation: UInt64) {
        replaceInbox(generation: generation, accepting: false)
        queue.async { [self] in
            guard inbox.withLock({ $0.generation == generation }) else { return }
            self.generation = generation
            builder.reset()
            error = nil
            lastSubmittedAt = nil
            flush(generation: generation)
        }
    }

    private func replaceInbox(generation: UInt64, accepting: Bool) {
        inbox.withLock { $0 = Inbox(generation: generation, accepting: accepting) }
    }

    func submit(_ bytes: [UInt8], generation: UInt64) {
        let schedule = inbox.withLock { box -> Bool in
            guard box.accepting, box.generation == generation else { return false }
            guard bytes.count <= 4 * 1024 * 1024 else { return false }
            if box.events.count >= 8 || box.bytes + bytes.count > 8 * 1024 * 1024 {
                box.events = [.discontinuity]
                box.bytes = 0
            }
            box.events.append(.accessUnit(bytes, ProcessInfo.processInfo.systemUptime))
            box.bytes += bytes.count
            guard !box.scheduled else { return false }
            box.scheduled = true
            return true
        }
        if schedule { queue.async { [self] in drain(generation: generation) } }
    }

    func recover(generation: UInt64) {
        let schedule = inbox.withLock { box -> Bool in
            guard box.accepting, box.generation == generation else { return false }
            box.events = [.discontinuity]
            box.bytes = 0
            guard !box.scheduled else { return false }
            box.scheduled = true
            return true
        }
        if schedule { queue.async { [self] in drain(generation: generation) } }
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        inbox.withLock { $0.accepting && $0.generation == generation }
    }

    private func drain(generation: UInt64) {
        guard self.generation == generation, isCurrent(generation), !flushing else { return }
        var processed = 0
        while isCurrent(generation), !flushing, processed < 8 {
            let event = inbox.withLock { box -> Event? in
                guard box.generation == generation, !box.events.isEmpty else {
                    if box.generation == generation { box.scheduled = false }
                    return nil
                }
                let next = box.events.removeFirst()
                if case .accessUnit(let bytes, _) = next { box.bytes -= bytes.count }
                return next
            }
            guard let event else { return }
            processed += 1
            switch event {
            case .discontinuity:
                error = nil
                flush(generation: generation)
            case .accessUnit(let bytes, let receivedAt):
                guard ProcessInfo.processInfo.systemUptime - receivedAt <= 0.35 else {
                    flush(generation: generation)
                    continue
                }
                consume(bytes, receivedAt: receivedAt, generation: generation)
            }
        }
        if !flushing, isCurrent(generation) {
            queue.async { [self] in drain(generation: generation) }
        }
    }

    private func consume(_ bytes: [UInt8], receivedAt: TimeInterval, generation: UInt64) {
        if LiveVideo.detect(annexB: bytes) == .avc {
            error = "暂不支持该相机的视频编码"
            return
        }
        do {
            guard let picture = try builder.makePicture(nals: Hevc.nalUnits(bytes)) else { return }
            if picture.requiresDecoderReset || renderer.requiresFlushToResumeDecoding || renderer.status == .failed {
                // Keep this complete AU, including an IRAP, behind the asynchronous flush.
                inbox.withLock { box in
                    guard box.generation == generation else { return }
                    box.events.insert(.accessUnit(bytes, receivedAt), at: 0)
                    box.bytes += bytes.count
                }
                flush(generation: generation)
                return
            }
            guard !awaitingRandomAccess || picture.isRandomAccess else { return }
            guard renderer.isReadyForMoreMediaData else {
                // Skipping one compressed picture breaks later reference pictures.
                if !awaitingRandomAccess { flush(generation: generation) }
                return
            }
            guard isCurrent(generation) else { return }
            renderer.enqueue(picture.sample)
            awaitingRandomAccess = false
            lastSubmittedAt = receivedAt
            error = nil
        } catch {
            // Keep receiving: a later complete parameter-set group can repair bad input.
            if !awaitingRandomAccess { flush(generation: generation) }
        }
    }

    private func flush(generation: UInt64) {
        awaitingRandomAccess = true
        lastSubmittedAt = nil
        flushing = true
        flushRevision &+= 1
        let revision = flushRevision
        renderer.flush(removingDisplayedImage: true) { [weak self] in
            guard let self else { return }
            self.queue.async { [self] in
                guard revision == self.flushRevision, self.generation == generation else { return }
                self.flushing = false
                self.drain(generation: generation)
            }
        }
    }

    func snapshot(_ completion: @escaping @Sendable (Snapshot) -> Void) {
        queue.async { [self] in
            let displayed: Bool
            if #available(iOS 17.4, *) {
                displayed = renderer.displayedPixelBuffer() != nil
            } else {
                // iOS 17.0–17.3 expose rendering status, not displayed-pixel inspection.
                displayed = renderer.status == .rendering
            }
            completion(Snapshot(generation: generation, lastSubmittedAt: lastSubmittedAt,
                                awaitingRandomAccess: awaitingRandomAccess || flushing,
                                hasDisplayedImage: displayed, error: error))
        }
    }
}
