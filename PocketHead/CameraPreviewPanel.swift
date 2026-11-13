import SwiftUI

extension ContentView {
    var cameraPreviewFrame: some View {
        Color.black
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                cameraPreviewContent(isActive: !isCameraPreviewFullscreen)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if model.showsZoomControls { cameraZoomControls.padding(8) }
            }
            .overlay(alignment: .topTrailing) {
                previewFullscreenButton(isClosing: false)
                    .padding(8)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("相机画面")
            .accessibilityValue(cameraPreviewMessage)
            .accessibilityIdentifier("camera.preview.viewport")
    }

    var fullscreenCameraPreview: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            cameraPreviewContent(isActive: true)
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if model.showsZoomControls {
                cameraZoomControls.padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
        .overlay(alignment: .top) {
            errorToast.padding(.top, 60)
        }
        .overlay(alignment: .topTrailing) {
            previewFullscreenButton(isClosing: true)
                .padding(.top, 8)
                .padding(.trailing, 18)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("全屏相机画面")
        .accessibilityValue(cameraPreviewMessage)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { isCameraPreviewFullscreen = false }
        .accessibilityIdentifier("camera.preview.fullscreen")
    }

    var cameraZoomControls: some View {
        ZStack {
            HStack {
                VStack(spacing: 4) {
                    ForEach([1, 3, 9], id: \.self) { stop in
                        let factor = Double(stop)
                        let available = model.canControlZoom && factor <= model.cameraZoomMaximum
                        let selected = abs((model.cameraZoomTarget ?? model.cameraZoomFactor ?? 0) - factor) < 0.06
                        Button { model.setCameraZoom(factor) } label: {
                            Text("\(stop)×")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(selected ? 0.8 : 0.55), in: Circle())
                                .overlay {
                                    if selected { Circle().stroke(Palette.cameraAccent.opacity(0.85), lineWidth: 1) }
                                }
                                .contentShape(Circle())
                        }
                        .foregroundStyle(selected ? Palette.cameraAccent : .white)
                        .disabled(!available)
                        .opacity(available ? 1 : 0.4)
                        .accessibilityLabel("\(stop) 倍变焦")
                        .accessibilityHint(factor > model.cameraZoomMaximum
                            ? "超出当前拍摄模式的倍率上限" : model.cameraZoomUnavailableReason ?? "平滑切换倍率")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("camera.zoom.preset.\(stop)")
                    }
                }
                Spacer(minLength: 0)
            }
            VStack {
                Spacer(minLength: 0)
                if let reason = model.cameraZoomUnavailableReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.65), in: Capsule())
                }
                HStack(spacing: 0) {
                    zoomHoldButton(increasing: false)
                    Text(model.cameraZoomFactor.map { String(format: "%.1f×", $0) } ?? "—×")
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .frame(width: 54)
                        .foregroundStyle(.white)
                        .accessibilityLabel("当前倍率")
                        .accessibilityValue(model.cameraZoomFactor.map { String(format: "%.1f×", $0) } ?? "未知")
                        .accessibilityIdentifier("camera.zoom.factor")
                    zoomHoldButton(increasing: true)
                }
                .background(.black.opacity(0.65), in: Capsule())
                .fixedSize()
            }
        }
        .buttonStyle(.plain)
    }

    func zoomHoldButton(increasing: Bool) -> some View {
        let reported = model.cameraZoomFactor ?? 1
        let available = model.canControlZoom
            && (increasing ? reported < model.cameraZoomMaximum - 0.001 : reported > 1.001)
        return ContinuousZoomButton(increasing: increasing, enabled: available,
                                    hint: model.cameraZoomUnavailableReason ?? "按住连续变焦，松开停止") { pressing in
            if pressing { model.beginCameraZoom(increasing: increasing) }
            else { model.endCameraZoom() }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
        .disabled(!available)
    }

    func previewFullscreenButton(isClosing: Bool) -> some View {
        Button {
            isCameraPreviewFullscreen = !isClosing
        } label: {
            Image(systemName: isClosing ? "xmark" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
                .background(.black.opacity(0.65), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isClosing ? "关闭全屏" : "全屏显示")
        .accessibilityIdentifier(isClosing ? "camera.preview.fullscreen.close" : "camera.preview.fullscreen.open")
    }

    func cameraPreviewContent(isActive: Bool) -> some View {
        ZStack {
            PocketLivePreviewView(displayLayer: cameraPreview.displayLayer, isActive: isActive)
                .accessibilityHidden(true)
            if model.demoCamera || cameraPreview.phase != .live {
                Color.black
                VStack(spacing: 10) {
                    if !dynamicTypeSize.isAccessibilitySize {
                        if !reduceMotion && !model.demoCamera
                            && (model.cameraIsConnecting || cameraPreview.phase == .waitingForPicture) {
                            ProgressView().tint(.white.opacity(0.75))
                        } else {
                            Image(systemName: "video.slash")
                                .font(.system(size: 28, weight: .regular))
                                .accessibilityHidden(true)
                        }
                    }
                    Text(cameraPreviewMessage)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    if !model.demoCamera && (cameraPreview.phase == .stalled || cameraPreview.phase == .failed) {
                        Button("重试画面", action: cameraPreview.retry)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(.white.opacity(0.15), in: Capsule())
                            .foregroundStyle(.white)
                            .disabled(!cameraPreview.canRetry)
                            .opacity(cameraPreview.canRetry ? 1 : 0.5)
                            .accessibilityIdentifier("camera.preview.retry")
                    }
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(18)
            }
        }
    }

    var cameraPreviewMessage: String {
        if model.demoCamera { return "模拟模式下暂无相机画面" }
        switch cameraPreview.phase {
        case .disconnected: return model.cameraIsConnecting ? "正在连接 Pocket" : "连接 Pocket 后查看画面"
        case .waitingForPicture: return "正在等待 Pocket 画面"
        case .live: return "Pocket 实时画面"
        case .stalled: return "画面中断，正在等待关键帧"
        case .failed: return cameraPreview.failureMessage ?? "暂未收到画面，请重试"
        }
    }

}
