import Foundation
import OpenCineDJI
import OpenCineDJIApple
import OpenCineMotion

// The facade owns session generation and transport; this module cannot create
// an independent command lifetime.
extension Pocket4ProGimbal {
    var zoomMaximum: Double {
        previewModel?.activeZoomStops(resolution: cameraStatus.videoResolution,
                                      shootingMode: cameraStatus.shootingMode).last ?? 1
    }

    var zoomFactor: Double? {
        guard zoomState.hasFreshReport(at: ProcessInfo.processInfo.systemUptime),
              let factor = zoomState.reportedFactor else { return nil }
        return factor
    }

    var zoomTarget: Double? { zoomState.targetFactor }
    var zoomUnavailableReason: String? {
        if let reason = zoomModeUnavailableReason { return reason }
        return zoomState.hasFreshReport(at: ProcessInfo.processInfo.systemUptime) ? nil : "等待相机变焦反馈"
    }

    var zoomModeUnavailableReason: String? {
        guard phase == .connected, link?.isFlowHealthy == true else { return "相机未连接" }
        guard cameraStatus.colorMode != nil, cameraStatus.videoResolution != nil,
              cameraStatus.shootingMode >= 0 else { return "等待相机变焦状态" }
        if cameraStatus.inPlayback { return "回放时无法变焦" }
        if cameraStatus.colorMode == .dLog2 { return "D-Log2 模式不支持变焦" }
        if zoomMaximum <= 1 { return "当前拍摄模式不支持变焦" }
        return nil
    }

    @discardableResult
    func requestZoom(_ factor: Double) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        guard zoomUnavailableReason == nil,
              zoomState.request(factor, maximum: zoomMaximum, at: now) else { return false }
        startZoomTask()
        return true
    }

    @discardableResult
    func beginContinuousZoom(increasing: Bool) -> Bool {
        guard zoomUnavailableReason == nil,
              zoomState.beginContinuous(increasing: increasing, maximum: zoomMaximum,
                                        at: ProcessInfo.processInfo.systemUptime) else { return false }
        startZoomTask()
        return true
    }

    func stopContinuousZoom() {
        guard zoomState.isContinuouslyAdjusting else { return }
        cancelZoom()
    }

    func startZoomTask() {
        // One owner for presets and holds; release never queues another target.
        zoomTask?.cancel()
        zoomSequences.removeAll()
        lastZoomLens = nil
        let attempt = generation
        zoomTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == attempt, self.zoomState.isAdjusting else { return }
                self.advanceZoom(at: ProcessInfo.processInfo.systemUptime)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        notifyZoomChange()
    }

    func advanceZoom(at now: TimeInterval) {
        zoomSequences = zoomSequences.filter { now - $0.value <= 2 }
        guard let event = zoomState.advance(at: now, maximum: zoomMaximum,
                                          allowed: zoomModeUnavailableReason == nil) else { return }
        switch event {
        case .set(let factor):
            let lens = CamFov.lensPosition(for: factor)
            if lens != lastZoomLens {
                guard let driver = link else { return }
                let admission = DJICommandAdmission(owner: driver.commandOwner, isCurrent: { true })
                guard case .queued(let sequence) = driver.send(Commands.setZoomLens(lens), admission: admission) else {
                    failZoom("变焦指令发送失败，请检查相机连接。")
                    return
                }
                lastZoomLens = lens
                zoomSequences[sequence] = now
                preview.noteZoomSet(at: now)
            }
        case .feedbackLost:
            failZoom("相机变焦反馈已中断，请稍后重试。")
        case .unavailable:
            failZoom("相机拍摄模式已变化，变焦已停止。")
        case .unconfirmed:
            failZoom("相机未确认目标倍率，请检查相机模式后重试。")
        }
        notifyZoomChange()
    }

    func cancelZoom() {
        zoomTask?.cancel()
        zoomTask = nil
        zoomState.cancel()
        zoomSequences.removeAll()
        lastZoomLens = nil
        notifyZoomChange()
    }

    func failZoom(_ message: String) {
        cancelZoom()
        onZoomFailure?(message)
    }

    func notifyZoomChange() {
        let factor = zoomFactor
        let maximum = zoomMaximum
        let presentation = ZoomPresentation(factor: factor.map { ($0 * 10).rounded() / 10 }, target: zoomTarget,
                                            maximum: maximum, reason: zoomUnavailableReason,
                                            atLowerLimit: (factor ?? 1) <= 1.001,
                                            atUpperLimit: (factor ?? maximum) >= maximum - 0.001)
        guard presentation != lastZoomPresentation else { return }
        lastZoomPresentation = presentation
        onZoomChange?()
    }

}
