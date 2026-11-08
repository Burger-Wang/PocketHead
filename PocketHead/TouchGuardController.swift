import Combine
import UIKit

@MainActor
final class TouchGuardController: ObservableObject {
    @Published private(set) var state = TouchGuardState()

    private weak var screen: UIScreen?
    private var savedBrightness: CGFloat?
    private var savedIdleTimer: Bool?
    private var updateTask: Task<Void, Never>?
    private var dimmingTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var dimmingRevision: UInt64 = 0
    private var sceneIsActive = true

    var isPresented: Bool { state.isActive }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func enter() {
        guard !state.isActive, sceneIsActive else { return }
        state.enter(at: now)
        synchronize()
    }

    func attach(to screen: UIScreen) {
        if self.screen !== screen { restoreBrightness() }
        self.screen = screen
        synchronize()
    }

    func exit() {
        guard state.isActive || savedBrightness != nil || savedIdleTimer != nil else {
            screen = nil
            return
        }
        state.exit()
        synchronize()
        screen = nil
    }

    func setSceneActive(_ active: Bool) {
        guard sceneIsActive != active else { return }
        sceneIsActive = active
        state.cancelTouches(at: now)
        synchronize()
    }

    func touchBegan(id: Int, canUnlock: Bool) {
        guard sceneIsActive else { return }
        state.touchBegan(id: id, canUnlock: canUnlock, at: now)
        synchronize()
    }

    func touchMoved(id: Int, canUnlock: Bool) {
        var updatedState = state
        updatedState.touchMoved(id: id, canUnlock: canUnlock)
        guard updatedState != state else { return }
        state = updatedState
        synchronize()
    }

    func touchEnded(id: Int, cancelled: Bool) {
        state.touchEnded(id: id, cancelled: cancelled, at: now)
        synchronize()
    }

    func accessibilityActivated() {
        // A VoiceOver double tap may brighten the screen, never bypass the hold.
        state.cancelTouches(at: now)
        synchronize()
        UIAccessibility.post(notification: .announcement, argument: "请双击并按住一点五秒，取消防误触。")
    }

    private func synchronize() {
        updateTask?.cancel()
        updateTask = nil
        revision &+= 1

        guard state.isActive, !state.isUnlocking, sceneIsActive else {
            restoreDisplay()
            return
        }
        guard let screen else { return }
        if savedIdleTimer == nil {
            savedIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        if state.isDimmed {
            if savedBrightness == nil {
                let brightness = screen.brightness
                savedBrightness = brightness
                beginDimming(on: screen, from: brightness)
            }
        } else {
            restoreBrightness()
        }

        guard let deadline = state.nextDeadline else { return }
        let delay = max(0, deadline - now)
        let scheduledRevision = revision
        updateTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) }
            catch { return }
            guard let self, self.revision == scheduledRevision, !Task.isCancelled else { return }
            self.state.advance(at: self.now)
            self.synchronize()
        }
    }

    private func restoreBrightness() {
        dimmingRevision &+= 1
        dimmingTask?.cancel()
        dimmingTask = nil
        if let savedBrightness { screen?.brightness = savedBrightness }
        savedBrightness = nil
    }

    private func beginDimming(on screen: UIScreen, from initialBrightness: CGFloat) {
        guard initialBrightness > 0.05 else { return }
        let startedAt = now
        let scheduledRevision = dimmingRevision
        dimmingTask = Task { [weak self, weak screen] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1.0 / 60)) }
                catch { return }
                guard let self, let screen, self.dimmingRevision == scheduledRevision,
                      self.screen === screen, self.sceneIsActive, self.state.isActive,
                      self.state.isDimmed, !self.state.isUnlocking else { return }
                let elapsed = self.now - startedAt
                screen.brightness = CGFloat(TouchGuardState.brightnessDuringDimming(
                    from: Double(initialBrightness), elapsed: elapsed
                ))
                if elapsed >= TouchGuardState.dimmingDuration {
                    self.dimmingTask = nil
                    return
                }
            }
        }
    }

    private func restoreDisplay() {
        restoreBrightness()
        if let savedIdleTimer { UIApplication.shared.isIdleTimerDisabled = savedIdleTimer }
        savedIdleTimer = nil
    }
}
