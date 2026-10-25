import SwiftUI

private enum Palette {
    static let background = Color(red: 0.045, green: 0.061, blue: 0.075)
    static let card = Color(red: 0.088, green: 0.111, blue: 0.128)
    static let border = Color.white.opacity(0.09)
    static let muted = Color(red: 0.60, green: 0.68, blue: 0.70)
    static let accent = Color(red: 0.46, green: 0.92, blue: 0.77)
    static let warning = Color(red: 0.98, green: 0.76, blue: 0.41)
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = HeadTrackingViewModel()

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
                    trackingCard
                    tuningCard
                    demoCard
                    Text("头追使用 AirPods 的头部姿态。模拟云台仅用于验证交互和算法，不会控制实体相机。")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 4)
                }
                .padding(18)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Pocket Head")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .tint(Palette.accent)
        .preferredColorScheme(.dark)
        .onAppear { model.start() }
        .onDisappear { model.suspend() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.start()
            } else {
                model.suspend()
            }
        }
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
            Label("Pocket 4 Pro", systemImage: "camera.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.muted)
            Text(model.cameraModeTitle)
                .font(.headline)
                .foregroundStyle(model.cameraIsSimulated ? Palette.warning : Palette.accent)
            Text(model.cameraModeDetail)
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardStyle()
    }

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(model.tracking ? Palette.accent : Palette.warning)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.tracking ? "头追运行中" : "等待校准")
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                angleTile(title: "云台水平", value: model.cameraPose.panDegrees, systemImage: "rotate.3d")
                angleTile(title: "云台俯仰", value: model.cameraPose.tiltDegrees, systemImage: "camera.viewfinder")
            }

            Button(action: model.calibrate) {
                Label(model.tracking ? "重新校准前方" : "校准前方并开始", systemImage: "scope")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(Palette.background)
            }
            .buttonStyle(.plain)
            .accessibilityHint("保持头部静止，将此刻朝向设为正前方")

            if model.tracking {
                Button {
                    model.stopTracking()
                } label: {
                    Label("停止头追", systemImage: "stop.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.warning)
            }
        }
        .cardStyle()
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
            Text("实心点随头部转动移动；校准后空心点显示云台跟随位置。此圆盘仅显示姿态，不可拖动。")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 15) {
                HeadDirectionDisplay(head: model.displayLook, camera: model.cameraLook)
                    .frame(width: 166, height: 166)
                VStack(alignment: .leading, spacing: 15) {
                    directionMetric("向右", value: model.displayLook.rightDegrees)
                    directionMetric("向上", value: model.displayLook.upDegrees)
                    HStack(spacing: 5) {
                        Circle()
                            .stroke(Palette.warning, lineWidth: 2)
                            .frame(width: 10, height: 10)
                        Text("云台跟随")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    .opacity(model.cameraLook == nil ? 0.45 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .cardStyle()
    }

    private func directionMetric(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Palette.muted)
            Text(String(format: "%+.1f°", value))
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func angleTile(title: String, value: Double, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(Palette.muted)
            Text(String(format: "%+.1f°", value))
                .font(.system(size: 25, weight: .medium, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
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
                                model.preset == preset ? Palette.accent.opacity(0.17) : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(model.preset == preset ? Palette.accent : Palette.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.preset == preset ? Palette.accent : .white)
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
                    .fill(Color.white.opacity(0.035))
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

#Preview {
    ContentView()
}
