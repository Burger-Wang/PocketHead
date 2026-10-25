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
                    HStack(spacing: 12) {
                        sensorCard
                        cameraCard
                    }
                    manualCard
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
            .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
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
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .cardStyle()
    }

    private var trackingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(model.tracking || model.manualActive ? Palette.accent : Palette.warning)
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.manualActive ? "手动控制中" : model.tracking ? "头追运行中" : "等待校准")
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                angleTile(title: "头部向右", value: model.look.rightDegrees, systemImage: "arrow.left.and.right")
                angleTile(title: "头部向上", value: model.look.upDegrees, systemImage: "arrow.up.and.down")
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

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("手动云台摇杆")
                    .font(.headline)
                Spacer()
                Text(model.manualActive ? "控制中" : "松手即停")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.manualActive ? Palette.accent : Palette.muted)
            }
            Text("按住圆盘拖动：向右转镜头，向上抬镜头。操作摇杆会立即退出头追。")
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                ManualJoystickPad(stick: model.manualStick) { x, y in
                    model.moveManualStick(x: x, y: y)
                } onRelease: {
                    model.releaseManualControl()
                }
                Spacer()
            }

            Text(String(format: "水平 %+.0f%%  ·  俯仰 %+.0f%%", model.manualStick.x * 100, model.manualStick.y * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                directionButton("向左微调", symbol: "arrow.left", x: -1, y: 0)
                directionButton("向上微调", symbol: "arrow.up", x: 0, y: 1)
                directionButton("向下微调", symbol: "arrow.down", x: 0, y: -1)
                directionButton("向右微调", symbol: "arrow.right", x: 1, y: 0)
            }

            settingSlider(
                "摇杆速度",
                value: $model.manualSensitivity,
                range: 0.2...1,
                display: String(format: "%.0f%%", model.manualSensitivity * 100)
            )
        }
        .cardStyle()
    }

    private func directionButton(_ title: String, symbol: String, x: Double, y: Double) -> some View {
        Button {
            model.nudgeManual(x: x, y: y)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(Palette.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("点按后短暂移动云台并自动停止")
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

private struct ManualJoystickPad: View {
    let stick: ManualStick
    let onMove: (Double, Double) -> Void
    let onRelease: () -> Void
    @GestureState private var touching = false

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let reach = side / 2 - 31

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.035))
                    .overlay {
                        Circle().stroke(Palette.border, lineWidth: 1)
                    }
                Circle()
                    .stroke(Palette.accent.opacity(0.32), lineWidth: 1)
                    .padding(27)
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 1, height: side - 30)
                Rectangle()
                    .fill(Palette.border)
                    .frame(width: side - 30, height: 1)
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "circle.grid.cross")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Palette.background)
                    }
                    .shadow(color: Palette.accent.opacity(0.2), radius: 10)
                    .offset(x: stick.x * reach, y: -stick.y * reach)
            }
            .frame(width: side, height: side)
            .contentShape(Circle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { value in
                        let center = side / 2
                        onMove(
                            Double((value.location.x - center) / reach),
                            Double((center - value.location.y) / reach)
                        )
                    }
                    .onEnded { _ in onRelease() }
            )
        }
        .frame(width: 192, height: 192)
        .onChange(of: touching) { wasTouching, isTouching in
            if wasTouching && !isTouching { onRelease() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("手动云台摇杆")
        .accessibilityValue(String(format: "水平 %+.0f%%，俯仰 %+.0f%%", stick.x * 100, stick.y * 100))
        .accessibilityHint("按住并拖动，松手停止；也可以使用下方方向按钮微调")
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
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
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
