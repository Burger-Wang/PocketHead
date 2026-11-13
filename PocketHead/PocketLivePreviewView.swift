import AVFoundation
import SwiftUI

/// Reuses one layer across SwiftUI updates; angles and record state never reset it.
struct PocketLivePreviewView: UIViewRepresentable {
    let displayLayer: AVSampleBufferDisplayLayer
    var isActive = true

    func makeUIView(context: Context) -> PreviewHostView {
        PreviewHostView(displayLayer: displayLayer, isActive: isActive)
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        uiView.setActive(isActive)
    }

    static func dismantleUIView(_ uiView: PreviewHostView, coordinator: ()) {
        uiView.setActive(false)
    }

    final class PreviewHostView: UIView {
        private let displayLayer: AVSampleBufferDisplayLayer

        init(displayLayer: AVSampleBufferDisplayLayer, isActive: Bool) {
            self.displayLayer = displayLayer
            super.init(frame: .zero)
            backgroundColor = .black
            isUserInteractionEnabled = false
            setActive(isActive)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func setActive(_ active: Bool) {
            if active {
                if displayLayer.superlayer !== layer {
                    layer.addSublayer(displayLayer)
                    setNeedsLayout()
                }
            } else if displayLayer.superlayer === layer {
                displayLayer.removeFromSuperlayer()
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // A fullscreen host may own the same layer now. An older host's
            // layout/dismantle must never resize or detach that current owner.
            guard displayLayer.superlayer === layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            displayLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
