import SwiftUI

private enum Palette {
    static let background = adaptive(light: 0xF4F7F8, dark: 0x0B1013)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x161C21)
    static let border = adaptive(light: 0xDCE5E7, dark: 0x2B3034)
    static let muted = adaptive(light: 0x52636B, dark: 0x99ADB3)
    static let accent = adaptive(light: 0x087A62, dark: 0x75EBC4)
    static let warning = adaptive(light: 0xA35E00, dark: 0xFAC269)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x0B1013)
    static let controlFill = adaptive(light: 0xF0F4F4, dark: 0x20262A)
    static let dialFill = adaptive(light: 0xF1F6F5, dark: 0x20272B)
    static let shadow = adaptive(light: 0xD9E2E4, dark: 0x000000)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let value = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct ContentView: View {
    @ObservedObject var model: HeadTrackingViewModel
    @ScaledMetric(relativeTo: .body) private var metricRowHeight: CGFloat = 49
    @ScaledMetric(relativeTo: .body) private var metricFooterHeight: CGFloat = 44

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introduction
                    HStack(alignment: .top, spacing: 12) {
                        sensorCard
                        cameraCard
                    }
                    directionCard
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
            }
            .overlay(alignment: .top) {
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
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Pocket动态追踪")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Palette.accent)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: "viewfinder")
                    .foregroundStyle(Palette.accent)
                Text("让镜头跟随视线")
                    .font(.title2.weight(.semibold))
            }
            Text("面向前方，点击校准。随后左右转头控制水平，抬头低头控制俯仰。")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 3)
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

    private var trackingControls: some View {
        HStack(spacing: 12) {
            Button(action: model.calibrate) {
                Label(model.tracking ? "重新校准前方" : "校准前方并开始", systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Palette.onAccent)
            }
            .buttonStyle(.plain)
            .accessibilityHint("保持头部静止，将此刻朝向设为正前方")

            if model.tracking {
                Button(action: model.stopTracking) {
                    Label("停止头追", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Palette.warning.opacity(0.6), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.warning)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.tracking)
    }

    private var directionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("头追方向")
                    .font(.headline)
                Spacer()
                Text(model.tracking ? "实时跟随" : model.demoHead ? "模拟姿态预览" : "等待校准")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.tracking ? Palette.accent : Palette.muted)
            }
            Text("实心点随头部转动移动；校准后空心点显示云台跟随位置。")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 15) {
                HeadDirectionDisplay(head: model.displayLook, camera: model.cameraLook)
                    .frame(width: 166, height: 166)
                GeometryReader { geometry in
                    let columnWidth = max(0, (geometry.size.width - 8) / 2)
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 12) {
                            directionMetric("向右", value: model.displayLook.rightDegrees)
                                .frame(height: metricRowHeight, alignment: .topLeading)
                            directionMetric("向上", value: model.displayLook.upDegrees)
                                .frame(height: metricRowHeight, alignment: .topLeading)
                            HStack(spacing: 5) {
                                Circle()
                                    .stroke(Palette.warning, lineWidth: 2)
                                    .frame(width: 10, height: 10)
                                Text("云台跟随")
                                    .font(.caption)
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .opacity(model.cameraLook == nil ? 0.45 : 1)
                            .frame(height: metricFooterHeight, alignment: .leading)
                        }
                        .frame(width: columnWidth, alignment: .leading)
                        VStack(alignment: .leading, spacing: 12) {
                            directionMetric("云台水平", value: model.cameraPoseAvailable ? model.cameraPose.panDegrees : nil, color: Palette.warning)
                                .frame(height: metricRowHeight, alignment: .topLeading)
                            directionMetric("云台俯仰", value: model.cameraPoseAvailable ? model.cameraPose.tiltDegrees : nil, color: Palette.warning)
                                .frame(height: metricRowHeight, alignment: .topLeading)
                            Button(action: model.recenterCamera) {
                                Text("云台回中")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .frame(height: metricFooterHeight)
                            .buttonStyle(.plain)
                            .foregroundStyle(model.canRecenterCamera ? Palette.accent : Palette.muted)
                            .disabled(!model.canRecenterCamera)
                        }
                        .frame(width: columnWidth, alignment: .leading)
                    }
                }
                .frame(height: metricRowHeight * 2 + metricFooterHeight + 24)
            }
        }
        .cardStyle()
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

    private var tuningCard: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("跟随手感")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(FollowPreset.allCases, id: \.self) { preset in
                    Button {
                        model.applyPreset(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                model.preset == preset ? Palette.accent.opacity(0.17) : Palette.controlFill,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(model.preset == preset ? Palette.accent : Palette.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.preset == preset ? Palette.accent : .primary)
                }
            }

            settingSlider("灵敏度", value: $model.sensitivity, range: 0.5...2, display: String(format: "%.2f×", model.sensitivity))
            settingSlider("死区", value: $model.deadZoneDegrees, range: 0...5, display: String(format: "%.1f°", model.deadZoneDegrees))
            settingSlider("平滑时间", value: $model.smoothingSeconds, range: 0...0.35, display: String(format: "%.2f s", model.smoothingSeconds))
            settingSlider("最大跟随速度", value: $model.maximumSpeed, range: 20...150, display: String(format: "%.0f°/s", model.maximumSpeed))
        }
        .cardStyle()
    }

    private func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(display)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.accent)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }

    private var demoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("模拟云台", isOn: $model.demoCamera)
                .font(.headline)
            Toggle(isOn: $model.demoHead) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("模拟头部动作")
                        .font(.headline)
                    Text("无需 AirPods，也能检查校准与跟随参数。")
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            if model.demoHead {
                settingSlider("左右转头", value: $model.demoYawDegrees, range: -120...120, display: String(format: "%+.0f°", model.demoYawDegrees))
                settingSlider("抬头 / 低头", value: $model.demoPitchDegrees, range: -50...50, display: String(format: "%+.0f°", model.demoPitchDegrees))
            }
        }
        .cardStyle()
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
        .accessibilityHint("仅显示头部方向和云台跟随位置")
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

private struct SensorCard: View {
    @ObservedObject var sensor: HeadphoneMotionService
    let demoHead: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("头部输入", systemImage: "airpodspro")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            Text(demoHead ? "模拟头部姿态" : sensor.status.title)
                .font(.headline)
                .foregroundStyle(demoHead || sensor.status == .streaming ? Palette.accent : Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardStyle()
    }

    private var detail: String {
        if demoHead { return "使用滑块提供测试姿态" }
        return switch sensor.status {
        case .unavailable: "请连接兼容 AirPods"
        case .ready: "等待第一帧姿态"
        case .streaming: "实时读取中"
        case .failed(let message): message
        }
    }
}

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 19))
            .overlay {
                RoundedRectangle(cornerRadius: 19)
                    .stroke(Palette.border, lineWidth: 1)
            }
    }
}

private extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

#Preview("浅色") {
    ContentView(model: HeadTrackingViewModel())
        .preferredColorScheme(.light)
}

#Preview("深色") {
    ContentView(model: HeadTrackingViewModel())
        .preferredColorScheme(.dark)
}
