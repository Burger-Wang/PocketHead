import SwiftUI

extension ContentView {
    var trackingControls: some View {
        HStack(spacing: model.showsRecordingControl ? 8 : 12) {
            Button(action: model.calibrate) {
                trackingControlLabel(model.tracking ? (model.showsRecordingControl ? "重新校准" : "重新校准前方") : "校准前方并开始", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.35 : 0.8)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 15)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Palette.onAccent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tracking.calibrate")
            .accessibilityLabel(model.tracking ? "重新校准前方" : "校准前方并开始")
            .accessibilityHint("保持头部静止，将此刻朝向设为正前方")

            if model.tracking {
                Button(action: model.stopTracking) {
                    trackingControlLabel("停止头追", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.35 : 0.8)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 15)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Palette.warning.opacity(0.6), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.warning)
                .accessibilityIdentifier("tracking.stop")
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            }

            if model.showsRecordingControl {
                recordingButton
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    func trackingControlLabel(_ title: String, systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title)
        } else {
            Label(title, systemImage: systemImage)
        }
    }

    var recordingButton: some View {
        Button(action: model.toggleRecording) {
            HStack(spacing: 6) {
                if model.isChangingRecording {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Palette.recordingActive)
                } else if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: model.cameraRecordingIndicator == .recording ? "stop.circle" : "record.circle")
                }
                Text(model.recordingButtonTitle)
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.35 : 0.8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 15)
            .background(Palette.recordingActive.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Palette.recordingActive.opacity(0.6), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.recordingActive)
        .disabled(!model.canToggleRecording)
        .opacity(model.canToggleRecording || model.isChangingRecording ? 1 : 0.5)
        .accessibilityIdentifier("camera.recordingControl")
        .accessibilityLabel(model.recordingButtonTitle)
        .accessibilityHint("控制 Pocket 视频录制，头追保持当前状态")
    }

}
