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

[English](../../README.md) | [简体中文](README.zh-Hans.md) | **繁體中文** | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*本文為譯文；若與[英文 README](../../README.md) 有出入，以英文版為準。*

CutawayServer 是一個在開發期間嵌入你的 App 的 iOS SDK。它讓 macOS App [**Cutaway**](https://github.com/nothingsh/Cutaway) 能夠檢查你正在執行的 App 的介面：Cutaway 發起連線，CutawayServer 擷取它請求的圖層、影像和屬性，並透過 [Cutaway 協定](https://github.com/nothingsh/CutawayProtocol) 傳回。它支援在模擬器中執行的 App，也支援在透過 USB 連接到 Mac 的裝置上執行的 App。

<a id="features"></a>
## 功能

- **一行程式碼整合。** 在啟動時呼叫 `CutawayServer.start()`，UIKit 和 SwiftUI 皆適用。 [Installation](https://nothingsh.github.io/Cutaway/integrate/)
- **Cutaway 顯示的一切。** 圖層樹（標出視圖控制器和成員變數）、每個圖層的影像、可以即時編輯的屬性、Auto Layout 約束，以及對外觀和文字大小的覆寫。 [Guide](https://nothingsh.github.io/Cutaway/guide/getting-started)
- **App 自己的資訊。** 加入屬性、為視圖自行繪製的內容加入虛擬節點、登記顏色名稱，以及讓視圖預設摺疊或不進入影像。 [Customizing what Cutaway shows](https://nothingsh.github.io/Cutaway/integrate/customizing)
- **不進入發佈建置。** 只編譯進定義了 `DEBUG` 的建置，除非你啟用 `ReleaseEnabled` trait。 [Debug and Release builds](https://nothingsh.github.io/Cutaway/integrate/builds)
- **不打擾 App。** 主執行緒保持回應，記憶體有上限，只監聽回送位址。 [Behavior on the device](https://nothingsh.github.io/Cutaway/integrate/on-device)
- **純 Swift，零第三方相依。**

<a id="requirements"></a>
## 需求

- iOS 13 或更新版本；以 Xcode 27 建置的產物需要 iOS 15 或更新版本（[原因](https://nothingsh.github.io/Cutaway/integrate/#requirements)）。
- Xcode 16.3 或更新版本，Swift 6.1 或更新版本。
- Swift Package Manager。不支援其他套件管理器。

<a id="installation"></a>
## 安裝

在 Xcode 中選擇 **File › Add Package Dependencies…**，輸入
`https://github.com/nothingsh/CutawayServer`，把 `CutawayServer` 程式庫加入你的 App target。在 `Package.swift` 中：

```swift
.package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
```

<a id="quick-start"></a>
## 快速開始

在 App 啟動時呼叫一次 `start()`，例如在 `application(_:didFinishLaunchingWithOptions:)` 中或 SwiftUI `App` 的 `init()` 中：

```swift
import CutawayServer

CutawayServer.start()
```

在模擬器中執行 App，或在連接到 Mac 的裝置上執行，然後開啟 Cutaway。[安裝指南](https://nothingsh.github.io/Cutaway/integrate/)提供 UIKit 和 SwiftUI 的程式碼，以及啟動時會發生什麼。

<a id="documentation"></a>
## 文件

其餘內容都在 [Cutaway 網站](https://nothingsh.github.io/Cutaway/)上（英文）：

- [Integrate](https://nothingsh.github.io/Cutaway/integrate/)：安裝、[Debug 與 Release 建置](https://nothingsh.github.io/Cutaway/integrate/builds)、[自訂 Cutaway 顯示的內容](https://nothingsh.github.io/Cutaway/integrate/customizing)、[在裝置上的行為](https://nothingsh.github.io/Cutaway/integrate/on-device)和[限制](https://nothingsh.github.io/Cutaway/integrate/limitations)。
- [Protocol](https://nothingsh.github.io/Cutaway/protocol/)：Cutaway 與 CutawayServer 如何溝通，以及哪些版本可以搭配使用。
- [常見問題與疑難排解](https://nothingsh.github.io/Cutaway/resources/faq)、[隱私與安全](https://nothingsh.github.io/Cutaway/resources/privacy)、[效能](https://nothingsh.github.io/Cutaway/resources/performance)、[版本記錄](https://nothingsh.github.io/Cutaway/resources/releases)、[路線圖](https://nothingsh.github.io/Cutaway/resources/roadmap)。

<a id="development"></a>
## 開發

如何建置和檢查 CutawayServer、修改如何審閱，見 [CONTRIBUTING.md](../../CONTRIBUTING.md)。網站的 [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) 一頁說明三個儲存庫如何配合。

<a id="license"></a>
## 授權

CutawayServer 以 MIT 授權條款發佈；見 [LICENSE](../../LICENSE)。`Sources/CutawayFlatBuffers` 是 FlatBuffers 的 Swift 執行環境，採用 Apache License 2.0；見該目錄中的 [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) 檔案。
