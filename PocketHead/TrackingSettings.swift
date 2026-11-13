import SwiftUI

extension ContentView {
    var tuningCard: some View {
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
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: FollowPresetButtonHeightKey.self, value: geometry.size.height)
                }
            }

            settingSlider("灵敏度", value: $model.sensitivity, range: 0.5...2, display: String(format: "%.2f×", model.sensitivity))
            settingSlider("死区", value: $model.deadZoneDegrees, range: 0...5, display: String(format: "%.1f°", model.deadZoneDegrees))
            settingSlider("平滑时间", value: $model.smoothingSeconds, range: 0...0.35, display: String(format: "%.2f s", model.smoothingSeconds))
            settingSlider("最大跟随速度", value: $model.maximumSpeed, range: 20...150, display: String(format: "%.0f°/s", model.maximumSpeed))
        }
        .cardStyle()
    }

    func settingSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
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

    var demoCard: some View {
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
    }}
