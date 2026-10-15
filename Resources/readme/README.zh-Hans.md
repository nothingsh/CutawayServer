<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-server-dark.svg">
    <img src="cutaway-server-light.svg" alt="CutawayServer — Capture iOS layers, images and attributes." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.1+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+-blue)](#requirements)
[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)](#installation)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](../../LICENSE)
[![verify](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml/badge.svg)](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml)

[English](../../README.md) | **简体中文** | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*本文为译文；如与[英文 README](../../README.md) 有出入，以英文版为准。*

CutawayServer 是一个在开发期间嵌入你的 App 的 iOS SDK。它让 macOS App [**Cutaway**](https://github.com/nothingsh/Cutaway) 能够检查你正在运行的 App 的视图层级：Cutaway 发起连接，CutawayServer 采集它请求的图层、图像和属性，并通过 [Cutaway 协议](https://github.com/nothingsh/CutawayProtocol) 发回。

它支持在模拟器中运行的 App，也支持在通过 USB 连接到 Mac 的设备上运行的 App。

<a id="features"></a>
## 功能

**Cutaway 能看到什么**

- 每个窗口的图层树，并标出视图控制器的根视图，以及持有各个图层或视图的成员变量。
- 每个图层的两张图像：一张只含该图层本身，一张包含其子图层；以流式传输，可以取消。
- 每个图层和视图的属性，并标出其中可编辑的属性；在 Cutaway 中所做的编辑会应用到正在运行的 App。
- 引用每个视图的 Auto Layout 约束，以及每条约束是否得到满足。

**为开发而设计**

- 一行代码即可集成：`CutawayServer.start()`。
- 默认不编译进 Release 构建。
- 只监听回环地址，一次只服务一个客户端。
- 纯 Swift，零第三方依赖。

<a id="requirements"></a>
## 要求

- iOS 13 或更高版本（使用 Xcode 27 构建时为 iOS 15 或更高版本；见下方说明）。
- Xcode 16.3 或更高版本，Swift 6.1 或更高版本。
- Swift Package Manager。不支持其他包管理器。

> [!NOTE]
> 每个模块都以 iOS 13 为部署目标、针对 iOS SDK 做过类型检查，因此本包不会在没有可用性检查的情况下使用任何更新的 API。不过，Xcode 27 的构建系统不支持低于 iOS 15 的部署目标，会把本包的部署目标提升到 15.0，所以用 Xcode 27 构建的产物在 iOS 15 及更高版本上运行。本包从未在 iOS 13 或 14 上运行过。

<a id="installation"></a>
## 安装

在 Xcode 中选择 **File › Add Package Dependencies…**，输入 `https://github.com/nothingsh/CutawayServer`，然后把 `CutawayServer` 库添加到你的 App target。

在 `Package.swift` 中：

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0")
]
```

然后把产品 `CutawayServer` 添加到你的 target 的依赖中。

<a id="quick-start"></a>
## 快速开始

在 App 启动时调用一次 `start()`。

```swift
import CutawayServer

// UIKit
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
) -> Bool {
    CutawayServer.start()
    return true
}

// SwiftUI
@main
struct MyApp: App {
    init() {
        CutawayServer.start()
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

`start()` 可以在任意线程调用；重复调用不会产生任何效果。App 进入活跃状态后，服务器开始监听。在模拟器中或在连接到你的 Mac 的设备上运行 App，然后打开 Cutaway。

<a id="debug-and-release-builds"></a>
## Debug 与 Release 构建

默认情况下，服务器只会编译进定义了 `DEBUG` 的构建。在其他所有构建中，`start()` 是一个空函数，产品中不包含任何监听代码。

本包能否看到 `DEBUG`，取决于宿主 App 的构建配置名称：

| 宿主配置名称 | 本包中是否定义了 `DEBUG`？ |
|---|---|
| `Debug`，以及包含 `Debug` 或 `Development` 的名称（例如 `DebugQA`） | 是 |
| `Release`、`Staging`、`QA` 以及其他任何名称，即使该配置是从 Debug 复制而来 | 否 |

要在第二类配置中使用服务器，请启用本包的 trait（包特性）`ReleaseEnabled`：

- 在 SwiftPM 宿主中：

  ```swift
  .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0", traits: ["ReleaseEnabled"])
  ```

- 在 Xcode 项目中：在这个包依赖上启用 trait `ReleaseEnabled`。使用 XcodeGen 时，把它列在 `packages.<name>.traits` 下；`Demo/release-enabled.yml` 是一个示例。

> [!WARNING]
> trait 作用于宿主的**所有**配置，包括你提交到 App Store 的那个配置。一旦启用，就要由宿主自己确保不在它发布的构建中调用 `start()`。

既没有 `DEBUG` 也没有启用该 trait 时，产品中除了入口点之外不包含本包的任何内容：没有服务器，没有 `Network` 符号，也没有协议的任何编码代码。测试脚本会用 `nm` 在演示 App 的 Release 构建上检查这一点。

`CutawayWire` 和 `CutawayFlatBuffers` 是实现细节。宿主可以在 Debug 构建中导入它们，但其中的任何内容都不是公开 API，也不受版本号约束。

<a id="performance"></a>
## 性能

检查一个 App 不应改变它的行为。CutawayServer 围绕这一点设计：

- **主线程保持响应。** 只有必须访问 UIKit 和 Core Animation 的工作才在主线程上运行，而且一次只处理一个图层，因此 App 能在图层之间处理事件。压缩、编码和网络在后台队列上运行。
- **Cutaway 跟不上时，内存保持有界。** 一旦尚未发送的数据加上等待压缩的图像超过 32 MiB，服务器就不再开始新的图像，也不再开始下一个请求，直到客户端跟上为止。当有 64 个请求在等待时，它停止读取。
- **长时间会话中不会累积任何东西。** 图层和视图以弱引用持有，连接关闭时，它拥有的一切都会被释放。
- **错误的输入不会让 App 崩溃。** 格式错误的数据和极端的请求都会以错误作答。

测试套件在每次运行时都会强制检查这些限制。实测值来自 iOS 模拟器上的 Debug 构建：

| 场景 | 限制 | 实测 |
|---|---|---|
| 一棵 10,000 个图层的树：先取层级，再取每个图层的图像、属性和约束——主线程上最长的单次阻塞¹ | 150 ms | 65–76 ms |
| 同上，从发出请求到最后一个图层的详情 | 30 s | 约 6 s |
| 一个从不读取的客户端——App 的内存增长，相对于 32 MiB 预算 | 1.5 × | 1.07 × |
| 在 UI 变化期间进行 200 轮层级、详情、编辑和刷新——第 10 轮之后的内存增长 | 4 MiB | ≤ 0.06 MiB |
| 一次性发送 1,000 个请求 | 按顺序应答；内存不随请求数量线性增长 | 通过 |
| 超过 100,000 个经过变异、截断和拼接的帧 | 不崩溃 | 通过 |

¹ 不计单个图层本身的渲染。

<a id="behavior-on-the-device"></a>
## 设备上的行为

**网络**

- 只在回环地址 `127.0.0.1` 上监听 TCP，从不在其他网络接口上监听。
- 使用 48160 到 48167 中第一个空闲的端口。如果全部被占用，则不监听，并在 App 下次进入活跃状态时重试。
- 如果在运行中监听失败（例如 App 从挂起状态恢复后），会在 App 处于活跃状态时于 0.5 秒后重新监听，并优先使用原来的端口。之后每次失败，间隔翻倍，最长 30 秒。
- 连接使用 TCP keepalive：约 25 秒没有应答的对端会被断开，服务器随即就能接受下一个客户端。

**采集**

- 成员变量名是通过比较所有者内存中的地址找到的；不会调用任何 getter。由默认（安全的）`unowned` 属性以及数组等集合持有的引用无法找到；`weak`、`unowned(unsafe)`、`lazy` 以及泛型类的属性可以找到。
- 图像逐个图层渲染。渲染某个图层时，会临时把该图层的不透明度设为 1 并使其可见；渲染不含子图层的图像时，还会临时隐藏子图层。所有这些改动都在同一段主线程代码内恢复，不产生动画，也不触发布局。
- 读取属性不会触发布局。颜色以 sRGB 发送，因此广色域颜色会被裁剪；动态颜色按视图当前的外观（浅色或深色）解析。

**限制**

- 由系统渲染服务器合成的内容不会出现在图像中：模糊效果、Metal 和视频图层等。
- 一次只服务一个客户端；第一个客户端连接期间，第二个会被拒绝。

<a id="roadmap"></a>
## 路线图

以下是 1.0 之后计划的方向。顺序和范围可能会变。

- **交互分析。** 显示手势识别器和 target–action 对；启用和停用手势；在对象上调用方法。
- **面向宿主 App 的扩展 API。** 自定义属性、虚拟子节点，以及诸如默认折叠的类、颜色别名和从图像中排除的视图等配置。
- **大型层级。** 只采集可见图层的快速模式；对超大图像分块传输。
- **更多连接方式和平台。** 经过认证和加密的 Wi-Fi 连接；tvOS 和 visionOS。
- **SwiftUI。** 与图层树并列的 SwiftUI 视图语义层级。

<a id="faq"></a>
## 常见问题

**CutawayServer 会进入我的 App Store 构建吗？**
默认不会。除非你启用 `ReleaseEnabled` trait，否则没有 `DEBUG` 的构建只包含一个空的 `start()`。参见 [Debug 与 Release 构建](#debug-and-release-builds)。

**网络上的其他设备能连接到我的 App 吗？**
不能。服务器只监听 `127.0.0.1`。在真机上，Mac 通过 USB 连接访问它。

**检查会改变我的 App 吗？**
采集会在主线程继续往下执行之前恢复它改动过的一切，读取属性也不会触发布局。只有你在 Cutaway 中所做的编辑，以及这些编辑引起的布局，才会改变 App。

**为什么模糊、视频或 Metal 视图在图像中是空白的？**
这些内容由系统的渲染服务器在 App 进程之外合成，因此无法从图层树渲染出来。

<a id="development"></a>
## 开发

克隆后运行一次 `./setup.sh`。它会检出协议的 submodule、检查 Xcode、在缺少 XcodeGen 和 jq 时用 Homebrew 安装它们、把锁定版本的工具安装到 `.tools/`、设置 git hooks，并生成演示用的 Xcode 项目。重复运行也无妨。

| 任务 | 命令 |
|---|---|
| 运行全部检查（需要 iPhone 模拟器） | `scripts/verify.sh` |
| 像 CI 一样运行不需要模拟器的检查 | `scripts/verify.sh --mac-only` |
| 格式化 | `"$(scripts/get-swiftformat.sh)" .` |
| Lint | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| 检查正在运行的服务器 | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- pre-commit hook 会格式化已暂存的 Swift 文件，暂存格式化结果并对它们执行 lint；存在 lint 违规的提交会被拒绝。Xcode 不显示 SwiftLint 的检查结果，因此它们只会在这个 hook 和 `scripts/verify.sh` 中出现。
- `cutaway-probe` 连接到正在运行的服务器，完成握手，获取图标、层级以及每个图层的图像和属性，并检查收到的每一帧。针对演示 App 时，`--expect-demo` 还会检查已知的内容、颜色和属性值。`--slow-read 200` 像慢速客户端那样读取，以确认服务器在背压下能完成整个流。

<a id="license"></a>
## 许可证

CutawayServer 以 MIT 许可证发布；见 [LICENSE](../../LICENSE)。`Sources/CutawayFlatBuffers` 是 FlatBuffers 的 Swift 运行时，采用 Apache License 2.0；见该目录中的 [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) 文件。
