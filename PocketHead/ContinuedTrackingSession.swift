import BackgroundTasks
import Foundation
import UIKit

/// Keeps a user-started head-tracking session eligible to run after the app is
/// backgrounded. The camera and motion stream still belong to the app model.
@available(iOS 26.0, *)
@MainActor
final class ContinuedTrackingSession {
    static let shared = ContinuedTrackingSession()

    private let identifier = "\(Bundle.main.bundleIdentifier ?? "cn.burgerwang.pockethead").headTracking"
    private var registered = false
    private var requestedIdentifier: String?
    private var runningTask: BGContinuedProcessingTask?
    private var submissionTask: Task<Void, Never>?
    private var launchWatchdog: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var transitionTask: UIBackgroundTaskIdentifier = .invalid
    private var startedAt: TimeInterval = 0
    private var endingUnsuccessfully = false
    private var onExpired: (() -> Void)?
    private var onFailed: ((String) -> Void)?

    var isReserved: Bool { requestedIdentifier != nil }
    var startFailureMessage: String {
        "后台任务注册失败，请重新安装最新版本后重试。"
    }

    private init() {}

    func register() {
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: .main
        ) { [weak self] task in
            Task { @MainActor [weak self] in
                self?.receive(task)
            }
        }
        let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers")
        NSLog("Pocket Head background task registration %@: %@; permitted: %@",
              registered ? "succeeded" : "failed", identifier, String(describing: permitted))
    }

    func begin(onExpired: @escaping () -> Void, onFailed: @escaping (String) -> Void) -> Bool {
        if isReserved {
            self.onExpired = onExpired
            self.onFailed = onFailed
            return true
        }
        guard registered else { return false }

        let identifier = self.identifier
        requestedIdentifier = identifier
        self.onExpired = onExpired
        self.onFailed = onFailed
        startedAt = ProcessInfo.processInfo.systemUptime

        // Covers the short gap between submitting a request and its launch handler.
        transitionTask = UIApplication.shared.beginBackgroundTask(withName: "启动头追会话") { [weak self] in
            Task { @MainActor [weak self] in
                self?.failIfStillPending(identifier: identifier, reason: "后台头追任务未能启动。")
            }
        }
        // This short transition allowance is helpful, but the continued task
        // itself is the authority for background execution.
        launchWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.failIfStillPending(identifier: identifier, reason: "后台头追任务启动超时。")
        }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "追踪中",
            subtitle: ""
        )
        request.strategy = .fail
        submissionTask = Task { [weak self] in
            do {
                if #available(iOS 27.0, *) {
                    try await BGTaskScheduler.shared.submitTaskRequest(request)
                } else {
                    try BGTaskScheduler.shared.submit(request)
                }
                guard self?.requestedIdentifier == identifier else {
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
                    return
                }
            } catch {
                self?.fail(identifier: identifier, reason: "无法启动后台头追：\(error.localizedDescription)")
            }
        }
        return true
    }

    func end(success: Bool) {
        guard let identifier = requestedIdentifier else { return }
        requestedIdentifier = nil
        onExpired = nil
        onFailed = nil
        submissionTask?.cancel()
        submissionTask = nil
        launchWatchdog?.cancel()
        launchWatchdog = nil
        progressTask?.cancel()
        progressTask = nil
        endTransitionTask()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        if let runningTask {
            self.runningTask = nil
            runningTask.expirationHandler = nil
            runningTask.setTaskCompleted(success: success && !endingUnsuccessfully)
        }
        endingUnsuccessfully = false
    }

    private func receive(_ incoming: BGTask) {
        guard let task = incoming as? BGContinuedProcessingTask,
              task.identifier == requestedIdentifier, runningTask == nil else {
            incoming.setTaskCompleted(success: false)
            return
        }
        runningTask = task
        launchWatchdog?.cancel()
        launchWatchdog = nil
        endTransitionTask()
        task.expirationHandler = { [weak self, weak task] in
            Task { @MainActor [weak self, weak task] in
                guard let self, let task else { return }
                self.expire(task)
            }
        }

        // Report progress without repeatedly updating the system Live Activity's
        // text. Frequent title updates can keep its expanded presentation visible.
        task.progress.totalUnitCount = Int64.max
        task.progress.completedUnitCount = 1
        progressTask = Task { [weak self, weak task] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self, let task,
                      self.runningTask === task else { return }
                let seconds = Int64(max(1, ProcessInfo.processInfo.systemUptime - self.startedAt))
                task.progress.completedUnitCount = seconds
            }
        }
    }

    private func expire(_ task: BGContinuedProcessingTask) {
        guard runningTask === task else { return }
        endingUnsuccessfully = true
        let callback = onExpired
        // Stop native targets and close the camera before releasing runtime.
        callback?()
        end(success: false)
    }

    private func failIfStillPending(identifier: String, reason: String) {
        guard requestedIdentifier == identifier, runningTask == nil else { return }
        fail(identifier: identifier, reason: reason)
    }

    private func fail(identifier: String, reason: String) {
        guard requestedIdentifier == identifier else { return }
        endingUnsuccessfully = true
        let callback = onFailed
        callback?(reason)
        end(success: false)
    }

    private func endTransitionTask() {
        guard transitionTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(transitionTask)
        transitionTask = .invalid
    }
}
