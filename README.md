# Pocket Head

面向 **DJI Osmo Pocket 4 Pro** 的 iOS 头追应用。使用 AirPods 头部姿态控制固定底座上的云台水平和俯仰；不处理车载、自行车或底座自身转动。

## 当前进度

这是第一阶段可运行工程。界面会清楚显示「模拟云台」，**目前不会向实体 Pocket 4 Pro 发送指令**。

| 功能 | 状态 |
| --- | --- |
| `CMHeadphoneMotionManager` 读取 AirPods 头部姿态 | 已实现；待兼容 AirPods 真机验证 |
| 前方校准；校准时检查姿态时效、头部静止和云台姿态 | 已实现 |
| 头部朝向映射到云台水平与俯仰；灵敏度、死区、平滑、限速 | 已实现 |
| 快速、标准、轻柔预设 | 已实现 |
| 模拟头部与模拟云台，供模拟器和无相机环境验证 | 已实现 |
| 手动云台摇杆、方向微调、松手归零与头追接管 | 已实现；当前驱动模拟云台 |
| 头部或云台姿态中断、AirPods 连接代际变化、切后台时停止头追 | 已实现 |
| Pocket 4 Pro 发现、连接、姿态回读与真实云台控制 | 待接入 |
| 云台回中、180° 旋转、录像控制 | 待真实相机链路验证后接入 |

## 运行与配置

1. 用 Xcode 打开 `PocketHead.xcodeproj`，选择 `PocketHead` scheme。
2. 模拟器可直接运行，默认启用「模拟头部动作」。可先拖动「手动云台摇杆」验证方向与松手停止；点击「校准前方并开始」后，再拖动模拟头部角度。头追期间触碰摇杆会接管云台，重新校准才能恢复头追。
3. 真机运行时，在 target 的 **Signing & Capabilities** 选择自己的 Apple Development Team；如包名冲突，修改 Bundle Identifier。iPhone 需开启开发者模式，并连接支持头部跟踪的 AirPods。首次使用需允许运动与健身权限。参见 Apple 的[真机运行说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)与[耳机运动数据说明](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager)。
4. 核心算法测试运行 `swift test`。模拟器编译可运行：

   ```sh
   xcodebuild -project PocketHead.xcodeproj -scheme PocketHead \
     -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
     CODE_SIGNING_ALLOWED=NO build
   ```

目前无 API Key 或第三方构建工具要求。实体 4 Pro 联调时还需要一台可连接的相机；若使用系统 API 加入相机 Wi-Fi，需按 Apple 文档启用 [Hotspot Configuration 能力](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.hotspotconfiguration)。

### Mac 上的 AirPods 与 iOS 预览

当前工程是 iOS App，Xcode 预览与模拟器没有把连接在 Mac 上的 AirPods 姿态转发进 App 的桥接，所以它们使用「模拟头部动作」。要验证实际 AirPods 姿态，请将 AirPods 连接到 iPhone，在真机运行 App，并关闭「模拟头部动作」。Apple 的 [`CMHeadphoneMotionManager` 文档](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager)也适用于 macOS；若要直接读取 Mac 所连 AirPods，需要另外构建 macOS 目标。Apple 提醒[模拟器不提供所有实体设备特性](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)。

## 技术路径

1. AirPods 姿态由 Core Motion 产生，样本带系统运行时间戳。App 在主线程保存最新一帧，并以约 25 Hz 读取，避免积压旧指令。
2. 校准时保存头部四元数和云台角度。之后用相对四元数旋转面部正前方 `+Y` 向量，再由 `atan2` 得到向右、向上的角度。这可以避免在已转头状态下抬头时，欧拉角差值带来的水平漂移。
3. 目标角度在校准云台姿态上叠加头部位移，并依次应用死区、灵敏度、平滑、最大角速度和云台角度边界。
4. 头部样本超过 200 ms 不再输出目标，校准用的云台姿态必须在 300 ms 内。App 切入后台会停止头追。真实相机接入后，断线、人工接管和视频状态也必须成为停机条件。

云台边界在模拟器里暂用 OpenPocketCine 报告的 4 Pro 参考值（水平 `-48°…225°`、俯仰 `-44°…70°`）。**实体相机要以连接时读到并验证的能力为准**。平滑时间和 25 Hz 更新频率是本 App 的设置，不代表实测端到端延迟。

### 与 OpenPocketCine / OpenCine 的关系

方案参考了 [OpenPocketCine 的头追设计](https://github.com/erik-sutton95/OpenPocketCine/blob/18137a5527951be510fc803cba2360fbcc23155d/docs/head-tracking.md) 和 [OpenCine 的 DJI 模块](https://github.com/erik-sutton95/OpenCine/tree/4a3d9b63b438450249ecd40a634328d0f8087f96/Sources/OpenCineDJIApple)。本工程的数学和 UI 代码单独编写，目前没有复制或链接其源码。

下一步的 4 Pro 适配应优先复用 OpenCine 的 `OpenCineDJI` / `OpenCineDJIApple` 模块：

- `DjiAppleConnectionRun`：发现、BLE 配对与 Wi-Fi 接入。
- `DjiAppleGimbalControl.freshWaypoint`：取得用于校准的实时云台姿态。
- `beginNativeHeadTrack` / `updateNativeHeadTrack` / `endNativeHeadTrack`：使用有代际标识的原生目标流发送与停止头追。
- 实体控制前补齐 OpenCine 要求的相机状态、视频新鲜度、手动摇杆接管及断线保护。

OpenPocketCine 文档明确区分了小幅原生命令探测与持续头追体验验证。真实 4 Pro 接入后，要先做小角度、低速、随时可停的台架测试，再测阶跃和往复转头的响应、过冲、抖动、停机时间，以及视频帧率和控制 ACK；不要把模拟器运行视为硬件验证。
