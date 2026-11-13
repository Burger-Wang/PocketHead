import SwiftUI

struct ContentView: View {
    @ObservedObject var model: HeadTrackingViewModel
    @ObservedObject var touchGuard: TouchGuardController
    @ObservedObject var cameraPreview: PocketLivePreviewController
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @State var followPresetButtonHeight: CGFloat = 38
    @State var isCameraPreviewFullscreen = false

    init(model: HeadTrackingViewModel) {
        self.model = model
        touchGuard = model.touchGuard
        cameraPreview = model.cameraPreview
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 12) {
                        sensorCard
                        cameraCard
                    }
                    cameraPreviewFrame
                    TrackingDirectionCard(model: model, display: model.directionDisplay,
                                          followPresetButtonHeight: followPresetButtonHeight)
                    trackingControls
                    tuningCard
                    demoCard
                    Text(model.demoCamera
                         ? "当前使用模拟云台，不会控制实体相机。"
                         : "")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 4)
                }
                .padding(18)
                .animation(trackingLayoutAnimation, value: model.tracking)
                .accessibilityHidden(touchGuard.isPresented || isCameraPreviewFullscreen)
            }
            .overlay(alignment: .top) {
                errorToast.accessibilityHidden(touchGuard.isPresented || isCameraPreviewFullscreen)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Pocket动态追踪")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onPreferenceChange(FollowPresetButtonHeightKey.self) { height in
            if height > 0, abs(height - followPresetButtonHeight) > 0.01 {
                followPresetButtonHeight = height
            }
        }
        .tint(Palette.accent)
        .disabled(touchGuard.isPresented || isCameraPreviewFullscreen)
        .allowsHitTesting(!touchGuard.isPresented && !isCameraPreviewFullscreen)
        .accessibilityHidden(touchGuard.isPresented || isCameraPreviewFullscreen)
        .overlay {
            if isCameraPreviewFullscreen {
                fullscreenCameraPreview
                    .transition(.opacity)
            }
        }
        .statusBarHidden(isCameraPreviewFullscreen)
        .background {
            PreviewOrientationBridge(fullscreen: isCameraPreviewFullscreen,
                                     orientation: cameraPreview.pictureOrientation,
                                     onFailure: model.previewOrientationFailed)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onChange(of: isCameraPreviewFullscreen) { _, _ in model.endCameraZoom() }
        .onChange(of: cameraPreview.pictureOrientation) { _, _ in
            if isCameraPreviewFullscreen { model.endCameraZoom() }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isCameraPreviewFullscreen)
        .overlay {
            if touchGuard.isPresented {
                TouchGuardView(controller: touchGuard)
                    .ignoresSafeArea()
            }
        }
        .defersSystemGestures(on: touchGuard.isPresented ? .all : [])
        .onDisappear { model.suspend() }
    }

    @ViewBuilder var errorToast: some View {
        if let message = model.errorToast {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Palette.warning)
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 14)
            .padding(.trailing, 58)
            .padding(.vertical, 11)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Palette.warning.opacity(0.55), lineWidth: 1)
            }
            .overlay(alignment: .trailing) {
                Button(action: model.dismissErrorToast) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭错误提示")
                .padding(.trailing, 6)
            }
            .shadow(color: Palette.shadow.opacity(0.25), radius: 12, y: 4)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    private var sensorCard: some View {
        SensorCard(sensor: model.sensor, demoHead: model.demoHead)
    }

    private var cameraCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 0) {
                Label("Pocket 4 Pro", systemImage: "camera.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: model.demoCamera ? 0 : 38)
            }
            Text(model.cameraModeTitle)
                .font(.headline)
                .foregroundStyle(model.cameraIsConnected ? Palette.accent : Palette.warning)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(model.cameraModeDetail)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardStyle()
        .overlay(alignment: .topTrailing) {
            if !model.demoCamera {
                Button(model.cameraIsConnected || model.cameraIsConnecting ? "断开" : "连接") {
                    if model.cameraIsConnected || model.cameraIsConnecting {
                        model.disconnectCamera()
                    } else {
                        model.connectCamera()
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.cameraIsConnected || model.cameraIsConnecting ? Palette.warning : Palette.accent)
                .buttonStyle(.plain)
                .frame(width: 44, height: 30)
                .contentShape(Rectangle())
                .padding(.top, 11)
                .padding(.trailing, 10)
            }
        }
    }

    private var trackingLayoutAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.25)
    }


}

#Preview("浅色") {
    ContentView(model: HeadTrackingViewModel())
        .preferredColorScheme(.light)
}

#Preview("深色") {
    ContentView(model: HeadTrackingViewModel())
        .preferredColorScheme(.dark)
}
