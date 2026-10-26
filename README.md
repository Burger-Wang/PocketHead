# Pocket动态追踪

面向 **DJI Osmo Pocket 4 Pro** 的 iOS 头追应用。使用 AirPods 头部姿态控制固定底座上的云台水平和俯仰；不处理车载、自行车或底座自身转动。

## 当前进度

真机版现已提供手动加入相机 Wi-Fi、返回应用后自动建立实体云台连接的试验路径：只有相机控制握手成功并收到新鲜云台姿态，才能校准和发送原生角度目标。**实体 Pocket 4 Pro 上的实际效果仍待台架验证**；模拟器默认使用模拟云台。

| 功能 | 状态 |
| --- | --- |
| `CMHeadphoneMotionManager` 读取 AirPods 头部姿态 | 已实现；头部姿态数据已验证，更多型号兼容性待测 |
| 前方校准；校准时检查姿态时效、头部静止和云台姿态 | 已实现 |
| 头部朝向映射到云台水平与俯仰；灵敏度、死区、平滑、限速 | 已实现 |
| 快速、标准、轻柔预设 | 已实现 |
| 模拟头部与模拟云台，供模拟器和无相机环境验证 | 已实现 |
| 头追方向圆盘：显示头部方向与云台跟随位置 | 已实现；圆盘只读 |
| 头部或云台姿态中断、AirPods 连接代际变化、切后台时停止头追 | 已实现 |
| 手动加入相机 Wi-Fi 后，应用启动或回到前台时静默检查并自动建立控制连接；云台姿态回读、原生角度目标与停止命令 | 已接入；等待实体 4 Pro 验证 |
| 直接握手失败后的 Pocket 4 Pro 蓝牙发现与配对 | 已接入试验路径；待实体相机验证 |
| 自动加入相机 Wi-Fi、完整机型与会话归属验证 | 尚未接入 |
| 云台回中、180° 旋转、录像控制 | 待真实相机链路验证后接入 |

## 运行与配置

1. 用 Xcode 打开 `PocketHead.xcodeproj`，选择 `PocketHead` scheme。
2. 模拟器可直接运行，默认启用「模拟头部动作」。拖动模拟头部角度滑块，可在只读方向圆盘预览头部方向；点击「校准前方并开始」后，圆盘还会显示模拟云台的跟随位置。
3. 真机运行时，在 target 的 **Signing & Capabilities** 选择自己的 Apple Development Team；如包名冲突，修改 Bundle Identifier。iPhone 需开启开发者模式，并连接支持头部跟踪的 AirPods。首次使用需允许运动与健身权限。参见 Apple 的[真机运行说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)与[耳机运动数据说明](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager)。
4. 在 Pocket 4 Pro 上开启无线连接，用 **iPhone 系统设置**手动加入相机 Wi-Fi。返回 App 后，应用会检查一次相机 Wi-Fi 通路：检测到则自动连接，未检测到则保持当前界面；也可点击 Pocket 4 Pro 状态卡右上角的「连接」手动重试。首次连接要允许本地网络访问。如果直接控制握手失败，App 会扫描 Pocket 蓝牙并尝试配对；若相机屏幕提示授权，请在相机上确认。连接中可点「断开」取消；连接成功后该按钮也可断开相机。错误会在顶部悬浮提示中显示 5 秒，也可点 × 提前关闭。看到「实体云台已连接」并有实时水平/俯仰读数后，保持相机固定、头部正前方，再点击校准。先做约 5° 的小幅转头测试，随时可点「停止头追」。相机 Wi-Fi 只有已加入并取得 `192.168.2.x` 地址还不够，App 必须收到协议握手和云台姿态。
5. 核心算法测试运行 `swift test`。模拟器编译可运行：

   ```sh
   xcodebuild -project PocketHead.xcodeproj -scheme PocketHead \
     -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
     CODE_SIGNING_ALLOWED=NO build
   ```

目前无 API Key 要求。工程链接了仓库内固定版本的 OpenCine DJI 源码。**Release** 配置保留 [Hotspot Configuration 能力](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.hotspotconfiguration)；当前个人开发团队无法签发此权限，**Debug** 不携带它。当前 App 不调用自动加入热点的 API；先在系统设置手动入网，应用启动或回到前台时检测到相机 Wi-Fi 通路便自动连接。

若提示「手机尚未取得相机 Wi-Fi 地址」，检查是否连的是 Pocket 热点而非其他 Wi-Fi。若显示蓝牙搜索或配对，请保持相机无线连接开启，并在相机屏幕确认授权；若给出指定 SSID，去 iPhone 设置手动加入它后回到 App 重试。若提示「等待云台反馈」，握手已成功但暂未收到可用于安全校准的新鲜姿态；持续 5 秒会转为可读的失败提示。

### Mac 上的 AirPods 与 iOS 预览

当前工程是 iOS App，Xcode 预览与模拟器没有把连接在 Mac 上的 AirPods 姿态转发进 App 的桥接，所以它们使用「模拟头部动作」。要验证实际 AirPods 姿态，请将 AirPods 连接到 iPhone，在真机运行 App，并关闭「模拟头部动作」。Apple 的 [`CMHeadphoneMotionManager` 文档](https://developer.apple.com/documentation/coremotion/cmheadphonemotionmanager)也适用于 macOS；若要直接读取 Mac 所连 AirPods，需要另外构建 macOS 目标。Apple 提醒[模拟器不提供所有实体设备特性](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)。

## 技术路径

1. AirPods 姿态由 Core Motion 产生，样本带系统运行时间戳。App 在主线程保存最新一帧，并以约 25 Hz 读取，避免积压旧指令。
2. 校准时保存头部四元数和云台角度。之后用相对四元数旋转面部正前方 `+Y` 向量，再由 `atan2` 得到向右、向上的角度。这可以避免在已转头状态下抬头时，欧拉角差值带来的水平漂移。
3. 目标角度在校准云台姿态上叠加头部位移，并依次应用死区、灵敏度、平滑、最大角速度和云台角度边界。
4. 头部样本超过 200 ms 不再输出目标，校准用的云台姿态必须在 300 ms 内。App 切入后台会停止头追并关闭控制链路；Wi-Fi、控制链路或云台姿态中断也会停止原生目标流。人工接管和视频状态尚未接入停机条件。

云台边界目前沿用 OpenPocketCine 报告的 4 Pro 参考值（水平 `-48°…225°`、俯仰 `-44°…70°`），还未从实体相机读取能力。实际控制需先验证机型与可达范围。平滑时间和 25 Hz 更新频率是本 App 的设置，不代表实测端到端延迟。

### 与 OpenPocketCine / OpenCine 的关系

方案参考了 [OpenPocketCine 的头追设计](https://github.com/erik-sutton95/OpenPocketCine/blob/main/docs/head-tracking.md)。`Vendor/OpenCinePocket` 包含 [OpenCine](https://github.com/erik-sutton95/OpenCine) 修订 `1be846d664da0020ef67f039a34f207c0b047404` 的六个 DJI 相关模块及依赖，保留 Apache 2.0 许可与通知。App 目前直接使用 `DjiAppleDatalink` 完成手动 Wi-Fi 下的握手、云台姿态回读和有代际标识的原生目标流；头追数学与 UI 仍由本工程实现。

后续 4 Pro 适配应继续复用 OpenCine 的模块：

- `DjiAppleConnectionRun`：直接握手失败后尝试 BLE 配对和读取相机 Wi-Fi 信息；个人开发团队仍由系统设置手动加入 Wi-Fi。继续验证 BLE 身份与当前 Wi-Fi 会话的对应关系。
- 对照 `DjiAppleGimbalControl` 的云台模式、速度准备与恢复，以及人工接管、视频状态和断线保护。
- 在实体 4 Pro 上验证原生俯仰坐标符号、可达范围、命令节奏与回读时延。

OpenPocketCine 文档明确区分了小幅原生命令探测与持续头追体验验证。真实 4 Pro 接入后，要先做小角度、低速、随时可停的台架测试，再测阶跃和往复转头的响应、过冲、抖动、停机时间，以及视频帧率和控制 ACK；不要把模拟器运行视为硬件验证。
