import SwiftUI
import UIKit

struct TouchGuardView: UIViewRepresentable {
    @ObservedObject var controller: TouchGuardController

    func makeUIView(context: Context) -> TouchGuardSurface {
        TouchGuardSurface(controller: controller)
    }

    func updateUIView(_ view: TouchGuardSurface, context: Context) {
        view.render(state: controller.state)
    }

    static func dismantleUIView(_ view: TouchGuardSurface, coordinator: ()) {
        view.controller?.exit()
    }
}

/// One touch owner for the whole screen, including the visible unlock control.
/// UIKit gives us cancellation and every finger without competing recognizers.
@MainActor
final class TouchGuardSurface: UIView {
    weak var controller: TouchGuardController?

    private struct Contact {
        let id: Int
        let origin: CGPoint
    }

    private let titleLabel = UILabel()
    private let unlockControl = TouchGuardUnlockControl()
    private let unlockLabel = UILabel()
    private var contacts: [ObjectIdentifier: Contact] = [:]
    private var nextContactID = 0
    private var hadWindow = false
    private var wasUnlocking = false
    private static let maximumHoldMovement: CGFloat = 20

    init(controller: TouchGuardController) {
        self.controller = controller
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        accessibilityViewIsModal = true
        accessibilityIdentifier = "touchGuard.overlay"
        configureLayout()
        unlockControl.onActivation = { [weak controller] in
            controller?.accessibilityActivated()
        }
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let screen = window?.windowScene?.screen {
            hadWindow = true
            controller?.attach(to: screen)
            UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
        } else if hadWindow {
            controller?.exit()
        }
    }

    // All touches stay here until their sequence ends, including after the
    // hold threshold. None can land on a newly exposed app control.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        bounds.contains(point) ? self : nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            nextContactID &+= 1
            let point = touch.location(in: self)
            let contact = Contact(id: nextContactID, origin: point)
            contacts[ObjectIdentifier(touch)] = contact
            controller?.touchBegan(id: contact.id, canUnlock: unlockFrame.contains(point))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { updateLocation(of: touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: true)
    }

    func render(state: TouchGuardState) {
        unlockControl.setHold(startedAt: state.holdStartedAt, completed: state.isUnlocking)
        unlockControl.backgroundColor = UIColor.white.withAlphaComponent(
            state.holdStartedAt != nil || state.isUnlocking ? 0.14 : 0.07
        )
        unlockLabel.text = state.isUnlocking ? "已取消防误触" : "取消防误触"
        unlockControl.accessibilityValue = state.isUnlocking ? "已取消"
            : state.isDimmed ? "屏幕已调暗，需连续长按1.5秒" : "需连续长按1.5秒"
        if state.isUnlocking, !wasUnlocking {
            UIAccessibility.post(notification: .announcement, argument: "防误触已取消，松开即可返回。")
        }
        wasUnlocking = state.isUnlocking
    }

    private var unlockFrame: CGRect { unlockControl.convert(unlockControl.bounds, to: self) }

    private func updateLocation(of touch: UITouch) {
        guard let contact = contacts[ObjectIdentifier(touch)] else { return }
        let point = touch.location(in: self)
        let distance = hypot(point.x - contact.origin.x, point.y - contact.origin.y)
        controller?.touchMoved(
            id: contact.id,
            canUnlock: unlockFrame.contains(point) && distance <= Self.maximumHoldMovement
        )
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        for touch in touches {
            if !cancelled { updateLocation(of: touch) }
            guard let contact = contacts.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            controller?.touchEnded(id: contact.id, cancelled: cancelled)
        }
    }

    private func configureLayout() {
        let icon = UIImageView(image: UIImage(systemName: "hand.raised.fill"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.8)
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false
        icon.heightAnchor.constraint(equalToConstant: 40).isActive = true

        configure(titleLabel, text: "防误触已开启", style: .title2, color: .white)
        configure(unlockLabel, text: "取消防误触", style: .headline, color: .white)
        unlockLabel.isAccessibilityElement = false

        unlockControl.isAccessibilityElement = true
        unlockControl.accessibilityTraits = .button
        unlockControl.accessibilityLabel = "取消防误触"
        unlockControl.accessibilityHint = "双击并按住一点五秒取消，提前松开会重置进度。"
        unlockControl.accessibilityIdentifier = "touchGuard.unlock"
        unlockLabel.translatesAutoresizingMaskIntoConstraints = false
        unlockControl.addSubview(unlockLabel)
        let preferredButtonWidth = unlockControl.widthAnchor.constraint(equalToConstant: 168)
        preferredButtonWidth.priority = .defaultLow
        NSLayoutConstraint.activate([
            unlockLabel.leadingAnchor.constraint(equalTo: unlockControl.leadingAnchor, constant: 24),
            unlockLabel.trailingAnchor.constraint(equalTo: unlockControl.trailingAnchor, constant: -24),
            unlockLabel.topAnchor.constraint(equalTo: unlockControl.topAnchor, constant: 16),
            unlockLabel.bottomAnchor.constraint(equalTo: unlockControl.bottomAnchor, constant: -16),
            unlockControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
            unlockControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 168),
            preferredButtonWidth
        ])

        let footnote = UILabel()
        configure(footnote, text: "轻触任意位置恢复亮度", style: .footnote, color: .lightGray)
        let content = UIStackView(arrangedSubviews: [icon, titleLabel, unlockControl, footnote])
        content.axis = .vertical
        content.alignment = .center
        content.spacing = 24
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        let preferredWidth = content.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, constant: -48)
        preferredWidth.priority = .defaultHigh
        let centeredButton = unlockControl.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        centeredButton.priority = .defaultHigh
        NSLayoutConstraint.activate([
            content.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
            centeredButton,
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor),
            unlockControl.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor),
            footnote.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor),
            content.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
            content.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 16),
            content.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -16),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            preferredWidth
        ])
        accessibilityElements = [titleLabel, unlockControl, footnote]
    }

    private func configure(_ label: UILabel, text: String, style: UIFont.TextStyle, color: UIColor) {
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        label.textAlignment = .center
    }
}

@MainActor
private final class TouchGuardUnlockControl: UIView {
    var onActivation: (() -> Void)?
    private let border = CAShapeLayer()
    private let progressBorder = CAShapeLayer()
    private static let cornerRadius: CGFloat = 18
    private static let holdAnimationKey = "holdProgress"
    private var displayedHoldStart: TimeInterval?
    private var displayedCompletion = false
    private var borderBounds = CGRect.null

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = Self.cornerRadius
        for outline in [border, progressBorder] {
            outline.fillColor = UIColor.clear.cgColor
            layer.addSublayer(outline)
        }
        border.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        border.lineWidth = 1
        progressBorder.strokeColor = UIColor(red: 117 / 255, green: 235 / 255, blue: 196 / 255, alpha: 1).cgColor
        progressBorder.lineWidth = 2.5
        progressBorder.lineCap = .round
        progressBorder.strokeEnd = 0
        progressBorder.isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 3, bounds.height > 3, bounds != borderBounds else { return }
        borderBounds = bounds
        // Start at the top centre and trace the button clockwise.
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let radius = min(Self.cornerRadius - 1.5, rect.height / 2, rect.width / 2)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius, startAngle: -.pi / 2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(withCenter: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                    radius: radius, startAngle: 0, endAngle: .pi / 2, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                    radius: radius, startAngle: .pi / 2, endAngle: .pi, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(withCenter: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                    radius: radius, startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.close()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for outline in [border, progressBorder] {
            outline.frame = bounds
            outline.path = path.cgPath
        }
        CATransaction.commit()
    }

    func setHold(startedAt: TimeInterval?, completed: Bool) {
        guard startedAt != displayedHoldStart || completed != displayedCompletion else { return }
        displayedHoldStart = startedAt
        displayedCompletion = completed
        progressBorder.removeAnimation(forKey: Self.holdAnimationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressBorder.strokeEnd = completed ? 1 : 0
        progressBorder.isHidden = startedAt == nil && !completed
        if !completed, let startedAt {
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
            let remaining = max(0, TouchGuardState.unlockDuration - elapsed)
            progressBorder.strokeEnd = 1
            if remaining > 0 {
                // Run on the compositor, without a per-frame SwiftUI update.
                // Align to the touch clock so rendering delay doesn't extend it.
                let animation = CABasicAnimation(keyPath: "strokeEnd")
                animation.fromValue = min(1, elapsed / TouchGuardState.unlockDuration)
                animation.toValue = 1
                animation.duration = remaining
                animation.beginTime = progressBorder.convertTime(CACurrentMediaTime(), from: nil)
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                progressBorder.add(animation, forKey: Self.holdAnimationKey)
            }
        }
        CATransaction.commit()
    }

    override func accessibilityActivate() -> Bool {
        onActivation?()
        return true
    }
}
