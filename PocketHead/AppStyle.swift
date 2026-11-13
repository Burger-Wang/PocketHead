import SwiftUI

enum Palette {
    static let background = adaptive(light: 0xF4F7F8, dark: 0x0B1013)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x161C21)
    static let border = adaptive(light: 0xDCE5E7, dark: 0x2B3034)
    static let muted = adaptive(light: 0x52636B, dark: 0x99ADB3)
    static let accent = adaptive(light: 0x087A62, dark: 0x75EBC4)
    static let warning = adaptive(light: 0xA35E00, dark: 0xFAC269)
    static let recordingInactive = adaptive(light: 0x837034, dark: 0x8A783E)
    static let recordingIdle = adaptive(light: 0xE5A800, dark: 0xFFD43B)
    static let recordingActive = adaptive(light: 0xD92D37, dark: 0xFF5964)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x0B1013)
    static let controlFill = adaptive(light: 0xF0F4F4, dark: 0x20262A)
    static let dialFill = adaptive(light: 0xF1F6F5, dark: 0x20272B)
    static let shadow = adaptive(light: 0xD9E2E4, dark: 0x000000)
    static let cameraAccent = Color(red: 0.46, green: 0.92, blue: 0.77)

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

struct SensorCard: View {
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

struct FollowPresetButtonHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
