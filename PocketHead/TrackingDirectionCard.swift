import SwiftUI

struct TrackingDirectionCard: View {
    @ObservedObject var model: HeadTrackingViewModel
    @ObservedObject var display: DirectionDisplayModel
    let followPresetButtonHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var metricRowHeight: CGFloat = 49
    @ScaledMetric(relativeTo: .body) private var metricFooterHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Text("头追方向")
                        .font(.headline)
                    recordingIndicator
                }
                Spacer()
                Text(model.tracking ? "实时跟随" : model.demoHead ? "模拟姿态预览" : "等待校准")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.tracking ? Palette.accent : Palette.muted)
            }
            Text("实心点随头部转动移动；校准后空心点显示云台相对方向。")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 15) {
                HeadDirectionDisplay(head: display.snapshot.head, camera: display.snapshot.cameraLook)
                    .frame(width: 166, height: 166)
                GeometryReader { geometry in
                    let columnWidth = max(0, (geometry.size.width - 8) / 2)
                    VStack(spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 12) {
                                directionMetric("向右", value: display.snapshot.head.rightDegrees)
                                    .frame(height: metricRowHeight, alignment: .topLeading)
                                directionMetric("向上", value: display.snapshot.head.upDegrees)
                                    .frame(height: metricRowHeight, alignment: .topLeading)
                                cameraControlButton("镜头翻转", enabled: model.canFlipCamera, action: model.flipCamera)
                            }
                            .frame(width: columnWidth, alignment: .leading)
                            VStack(alignment: .leading, spacing: 12) {
                                directionMetric("云台水平", value: display.snapshot.cameraPose?.panDegrees, color: Palette.warning)
                                    .frame(height: metricRowHeight, alignment: .topLeading)
                                directionMetric("云台俯仰", value: display.snapshot.cameraPose?.tiltDegrees, color: Palette.warning)
                                    .frame(height: metricRowHeight, alignment: .topLeading)
                                cameraControlButton("云台回中", enabled: model.canRecenterCamera, action: model.recenterCamera)
                            }
                            .frame(width: columnWidth, alignment: .leading)
                        }
                        if model.tracking {
                            touchGuardButton
                                .transition(.opacity)
                        }
                    }
                }
                .frame(height: metricRowHeight * 2 + metricFooterHeight + 24
                       + (model.tracking ? followPresetButtonHeight + 8 : 0))
                .clipped()
            }
        }
        .cardStyle()
    }

    private var recordingIndicator: some View {
        let state = model.cameraRecordingIndicator
        return Group {
            if state == .recording && !reduceMotion {
                Circle()
                    .stroke(Palette.recordingActive, lineWidth: 2)
                    .phaseAnimator([false, true]) { content, expanded in
                        content
                            .opacity(expanded ? 1 : 0.35)
                            .scaleEffect(expanded ? 1.06 : 0.94)
                    } animation: { _ in
                        .easeInOut(duration: 0.9)
                    }
            } else {
                Circle()
                    .stroke(recordingIndicatorColor(state), lineWidth: 2)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("camera.recordingIndicator")
        .accessibilityLabel("相机录制状态")
        .accessibilityValue(recordingIndicatorValue(state))
    }

    private func recordingIndicatorColor(_ state: CameraRecordingIndicator) -> Color {
        switch state {
        case .disconnected, .unknown: Palette.recordingInactive
        case .idle: Palette.recordingIdle
        case .recording: Palette.recordingActive
        }
    }

    private func recordingIndicatorValue(_ state: CameraRecordingIndicator) -> String {
        switch state {
        case .disconnected: "相机未连接"
        case .unknown: "已连接，等待录制状态"
        case .idle: "已连接，未录制"
        case .recording: "正在录制"
        }
    }

    private func cameraControlButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .frame(height: metricFooterHeight)
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Palette.accent : Palette.muted)
        .disabled(!enabled)
    }

    private func directionMetric(_ title: String, value: Double?, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value.map { String(format: "%+.1f°", $0) } ?? "—")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(value == nil ? Palette.muted : color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var touchGuardButton: some View {
        Button {
            if model.tracking { model.touchGuard.enter() }
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Text("防误触")
                } else {
                    Label("防误触", systemImage: "hand.raised")
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity)
            .frame(height: followPresetButtonHeight)
            .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Palette.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accent)
        .accessibilityHint("遮挡页面操作并保持屏幕常亮，长按一点五秒可退出")
        .accessibilityIdentifier("touchGuard.enter")
    }

}

private struct HeadDirectionDisplay: View {
    let head: LookAngles
    let camera: LookAngles?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let reach = side / 2 - 23
            let headOffset = markerOffset(for: head, reach: reach)

            ZStack {
                Circle()
                    .fill(Palette.dialFill)
                    .overlay {
                        Circle().stroke(Palette.border, lineWidth: 1)
                    }
                Circle()
                    .stroke(Palette.accent.opacity(0.25), lineWidth: 1)
                    .padding(32)
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 1, height: side - 18)
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: side - 18, height: 1)
                Path { path in
                    path.move(to: CGPoint(x: side / 2, y: side / 2))
                    path.addLine(to: CGPoint(x: side / 2 + headOffset.width, y: side / 2 + headOffset.height))
                }
                .stroke(Palette.accent.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                if let camera {
                    Circle()
                        .stroke(Palette.warning, lineWidth: 3)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Palette.card))
                        .offset(markerOffset(for: camera, reach: reach))
                }
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 23, height: 23)
                    .overlay {
                        Circle()
                            .stroke(Palette.background, lineWidth: 3)
                    }
                    .shadow(color: Palette.accent.opacity(0.35), radius: 10)
                    .offset(headOffset)
            }
            .frame(width: side, height: side)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("头追方向显示")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("仅显示头部方向和云台相对方向")
    }

    private var accessibilityValue: String {
        let headValue = String(format: "头部向右 %+.1f 度，向上 %+.1f 度", head.rightDegrees, head.upDegrees)
        guard let camera else { return headValue }
        return headValue + String(format: "；云台相对校准方向向右 %+.1f 度，向上 %+.1f 度", camera.rightDegrees, camera.upDegrees)
    }

    private func markerOffset(for look: LookAngles, reach: CGFloat) -> CGSize {
        let right = max(-1, min(1, look.rightDegrees / 90))
        let up = max(-1, min(1, look.upDegrees / 45))
        let scale = max(1, hypot(right, up))
        return CGSize(width: CGFloat(right / scale) * reach, height: -CGFloat(up / scale) * reach)
    }
}
