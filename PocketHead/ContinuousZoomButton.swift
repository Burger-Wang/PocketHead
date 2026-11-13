import SwiftUI
import UIKit

/// Touch-down starts one continuous move; every release/cancel path ends it.
struct ContinuousZoomButton: UIViewRepresentable {
    @Environment(\.isEnabled) private var environmentEnabled
    let increasing: Bool
    let enabled: Bool
    let hint: String
    let onPress: (Bool) -> Void

    func makeUIView(context: Context) -> HoldButton { HoldButton() }

    func updateUIView(_ button: HoldButton, context: Context) {
        button.onPress = onPress
        let iconTag = increasing ? 1 : -1
        if button.tag != iconTag {
            button.tag = iconTag
            button.setImage(UIImage(systemName: increasing ? "plus" : "minus",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)), for: .normal)
            button.tintColor = .white
            button.accessibilityLabel = increasing ? "放大画面" : "缩小画面"
            button.accessibilityIdentifier = increasing ? "camera.zoom.in" : "camera.zoom.out"
        }
        button.accessibilityHint = hint
        let acceptsInput = enabled && environmentEnabled
        button.alpha = acceptsInput ? 1 : 0.4
        if !acceptsInput { button.endZoomPress() }
        if button.isEnabled != acceptsInput { button.isEnabled = acceptsInput }
    }

    static func dismantleUIView(_ button: HoldButton, coordinator: ()) { button.endZoomPress() }

    final class HoldButton: UIButton {
        var onPress: ((Bool) -> Void)?
        private var holding = false
        private var accessibilityPulse: Task<Void, Never>?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isExclusiveTouch = true
            addTarget(self, action: #selector(beginZoomPress), for: .touchDown)
            addTarget(self, action: #selector(endZoomPress), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func beginZoomPress() {
            guard isEnabled, !holding else { return }
            holding = true
            backgroundColor = UIColor.white.withAlphaComponent(0.15)
            onPress?(true)
        }

        @objc func endZoomPress() {
            accessibilityPulse?.cancel()
            accessibilityPulse = nil
            guard holding else { return }
            holding = false
            backgroundColor = .clear
            onPress?(false)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { endZoomPress() }
        }

        override func accessibilityActivate() -> Bool {
            guard isEnabled else { return false }
            beginZoomPress()
            accessibilityPulse?.cancel()
            accessibilityPulse = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                self?.endZoomPress()
            }
            return true
        }
    }
}
