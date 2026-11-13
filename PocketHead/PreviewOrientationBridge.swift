import SwiftUI
import UIKit

@MainActor
final class PreviewOrientationDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

/// Rotates the actual window scene. The existing view and datalink stay mounted.
struct PreviewOrientationBridge: UIViewRepresentable {
    let fullscreen: Bool
    let orientation: PreviewGeometry.Orientation?
    let onFailure: () -> Void

    func makeUIView(context: Context) -> HostView { HostView() }

    func updateUIView(_ view: HostView, context: Context) {
        view.configure(landscape: fullscreen && orientation == .landscape, onFailure: onFailure)
    }

    static func dismantleUIView(_ view: HostView, coordinator: ()) { view.restorePortrait() }

    final class HostView: UIView {
        private var landscape = false
        private var appliedMask: UIInterfaceOrientationMask?
        private weak var scene: UIWindowScene?
        private var onFailure: (() -> Void)?

        func configure(landscape: Bool, onFailure: @escaping () -> Void) {
            self.landscape = landscape
            self.onFailure = onFailure
            schedule()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { scene = window.windowScene; schedule() }
        }

        private func schedule() {
            // SwiftUI may be updating layout; apply the latest policy next turn.
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func restorePortrait() {
            landscape = false
            apply()
        }

        private func apply() {
            guard let scene else { return }
            let mask: UIInterfaceOrientationMask = landscape ? .landscape : .portrait
            guard appliedMask != mask else { return }
            appliedMask = mask
            PreviewOrientationDelegate.supportedOrientations = mask
            scene.windows.forEach { window in
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                window.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            let current = scene.interfaceOrientation
            if landscape ? current.isLandscape : current == .portrait { return }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] _ in
                Task { @MainActor [weak self] in self?.onFailure?() }
            }
        }
    }
}
