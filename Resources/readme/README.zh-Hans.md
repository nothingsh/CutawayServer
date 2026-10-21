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

CutawayServer 是一个在开发期间嵌入你的 App 的 iOS SDK。它让 macOS App [**Cutaway**](https://github.com/nothingsh/Cutaway) 能够检查你正在运行的 App 的界面：Cutaway 发起连接，CutawayServer 采集它请求的图层、图像和属性，并通过 [Cutaway 协议](https://github.com/nothingsh/CutawayProtocol) 发回。它支持在模拟器中运行的 App，也支持在通过 USB 连接到 Mac 的设备上运行的 App。

<a id="features"></a>
## 功能

- **一行代码集成。** 在启动时调用 `CutawayServer.start()`，UIKit 和 SwiftUI 都适用。 [安装](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/)
- **Cutaway 显示的一切。** 图层树（标出视图控制器和成员变量）、每个图层的图像、可以实时编辑的属性、Auto Layout 约束，以及对外观和文字大小的改写。 [指南](https://nothingsh.github.io/Cutaway/zh-Hans/guide/getting-started)
- **App 自己的信息。** 添加属性、为视图自己绘制的内容添加虚拟节点、登记颜色名，以及让视图默认折叠或不进入图像。 [定制 Cutaway 显示的内容](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/customizing)
- **不进入发布构建。** 只编译进定义了 `DEBUG` 的构建，除非你启用 `ReleaseEnabled` trait。 [Debug 与 Release 构建](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/builds)
- **不打扰 App。** 主线程保持响应，内存有上限，只监听回环地址。 [在设备上的行为](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/on-device)
- **纯 Swift，零第三方依赖。**

<a id="requirements"></a>
## 要求

- iOS 13 或更高版本；用 Xcode 27 构建的产物需要 iOS 15 或更高版本（[原因](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/#requirements)）。
- Xcode 16.3 或更高版本，Swift 6.1 或更高版本。
- Swift Package Manager。不支持其他包管理器。

<a id="installation"></a>
## 安装

在 Xcode 中选择 **File › Add Package Dependencies…**，输入
`https://github.com/nothingsh/CutawayServer`，把 `CutawayServer` 库添加到你的 App target。在 `Package.swift` 中：

```swift
.package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
```

<a id="quick-start"></a>
## 快速开始

在 App 启动时调用一次 `start()`，例如在 `application(_:didFinishLaunchingWithOptions:)` 中或 SwiftUI `App` 的 `init()` 中：

```swift
import CutawayServer

CutawayServer.start()
```

在模拟器中运行 App，或在连接到 Mac 的设备上运行，然后打开 Cutaway。[安装指南](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/)给出了 UIKit 和 SwiftUI 的代码，以及启动时发生什么。

<a id="documentation"></a>
## 文档

其余内容都在 [Cutaway 网站](https://nothingsh.github.io/Cutaway/zh-Hans/)上：

- [集成](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/)：安装、[Debug 与 Release 构建](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/builds)、[定制 Cutaway 显示的内容](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/customizing)、[在设备上的行为](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/on-device)和[限制](https://nothingsh.github.io/Cutaway/zh-Hans/integrate/limitations)。
- [协议](https://nothingsh.github.io/Cutaway/zh-Hans/protocol/)：Cutaway 与 CutawayServer 如何通信，以及哪些版本可以搭配使用。
- [常见问题与故障排除](https://nothingsh.github.io/Cutaway/zh-Hans/resources/faq)、[隐私与安全](https://nothingsh.github.io/Cutaway/zh-Hans/resources/privacy)、[性能](https://nothingsh.github.io/Cutaway/zh-Hans/resources/performance)、[版本记录](https://nothingsh.github.io/Cutaway/zh-Hans/resources/releases)、[路线图](https://nothingsh.github.io/Cutaway/zh-Hans/resources/roadmap)。

<a id="development"></a>
## 开发

如何构建和检查 CutawayServer、修改如何审阅，见 [CONTRIBUTING.md](../../CONTRIBUTING.md)。网站的[参与贡献](https://nothingsh.github.io/Cutaway/zh-Hans/resources/contributing)一页说明三个仓库如何配合。

<a id="license"></a>
## 许可证

CutawayServer 以 MIT 许可证发布；见 [LICENSE](../../LICENSE)。`Sources/CutawayFlatBuffers` 是 FlatBuffers 的 Swift 运行时，采用 Apache License 2.0；见该目录中的 [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) 文件。
