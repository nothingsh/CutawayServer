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

CutawayServer 是一套在開發期間嵌入你的 App 的 iOS SDK。它讓 macOS App [**Cutaway**](https://github.com/nothingsh/Cutaway) 能夠檢視你正在執行的 App 的視圖階層：Cutaway 發起連線，CutawayServer 擷取它所要求的圖層、影像和屬性，並透過 [Cutaway 協定](https://github.com/nothingsh/CutawayProtocol) 傳回。

它支援在模擬器中執行的 App，也支援在透過 USB 連接到 Mac 的裝置上執行的 App。

<a id="features"></a>
## 功能

**Cutaway 能看到什麼**

- 每個視窗的圖層樹，並標出視圖控制器的根視圖，以及持有各個圖層或視圖的成員變數。
- 每個圖層的兩張影像：一張只含該圖層本身，一張包含其子圖層；以串流傳輸，可以取消。
- 每個圖層和視圖的屬性，並標出其中可編輯的屬性；在 Cutaway 中所做的編輯會套用到正在執行的 App。
- 參照每個視圖的 Auto Layout 約束，以及每條約束是否得到滿足。

**為開發而設計**

- 一行程式碼即可整合：`CutawayServer.start()`。
- 預設不會編譯進 Release 建置。
- 只監聽回送位址，一次只服務一個用戶端。
- 純 Swift，零第三方相依套件。

<a id="requirements"></a>
## 需求

- iOS 13 或更新版本（使用 Xcode 27 建置時為 iOS 15 或更新版本；見下方說明）。
- Xcode 16.3 或更新版本，Swift 6.1 或更新版本。
- Swift Package Manager。不支援其他套件管理工具。

> [!NOTE]
> 每個模組都以 iOS 13 為部署目標、針對 iOS SDK 做過型別檢查，因此本套件不會在沒有可用性檢查的情況下使用任何更新的 API。不過，Xcode 27 的建置系統不支援低於 iOS 15 的部署目標，會把本套件的部署目標提高到 15.0，所以用 Xcode 27 建置的產物在 iOS 15 及更新版本上執行。本套件從未在 iOS 13 或 14 上執行過。

<a id="installation"></a>
## 安裝

在 Xcode 中選擇 **File › Add Package Dependencies…**，輸入 `https://github.com/nothingsh/CutawayServer`，然後把 `CutawayServer` 程式庫加入你的 App target。

在 `Package.swift` 中：

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0")
]
```

然後把產品 `CutawayServer` 加入你的 target 的相依項目中。

<a id="quick-start"></a>
## 快速上手

在 App 啟動時呼叫一次 `start()`。

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

`start()` 可以在任何執行緒呼叫；重複呼叫不會有任何作用。App 進入作用中狀態後，伺服器開始監聽。在模擬器中或在連接到你的 Mac 的裝置上執行 App，然後開啟 Cutaway。

<a id="debug-and-release-builds"></a>
## Debug 與 Release 建置

預設情況下，伺服器只會編譯進有定義 `DEBUG` 的建置。在其他所有建置中，`start()` 是一個空函式，產品中不含任何監聽程式碼。

本套件能否看到 `DEBUG`，取決於宿主 App 的建置組態名稱：

| 宿主組態名稱 | 本套件中是否定義了 `DEBUG`？ |
|---|---|
| `Debug`，以及包含 `Debug` 或 `Development` 的名稱（例如 `DebugQA`） | 是 |
| `Release`、`Staging`、`QA` 以及其他任何名稱，即使該組態是從 Debug 複製而來 | 否 |

要在第二類組態中使用伺服器，請啟用本套件的 trait（套件特性）`ReleaseEnabled`：

- 在 SwiftPM 宿主中：

  ```swift
  .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0", traits: ["ReleaseEnabled"])
  ```

- 在 Xcode 專案中：在這個套件相依項目上啟用 trait `ReleaseEnabled`。使用 XcodeGen 時，把它列在 `packages.<name>.traits` 之下；`Demo/release-enabled.yml` 是一個範例。

> [!WARNING]
> trait 會作用於宿主的**所有**組態，包括你提交到 App Store 的那一個。一旦啟用，就要由宿主自行確保不在它發佈的建置中呼叫 `start()`。

既沒有 `DEBUG` 也沒有啟用該 trait 時，產品中除了進入點之外不含本套件的任何內容：沒有伺服器，沒有 `Network` 符號，也沒有協定的任何編碼程式碼。測試腳本會用 `nm` 在示範 App 的 Release 建置上檢查這一點。

`CutawayWire` 和 `CutawayFlatBuffers` 是實作細節。宿主可以在 Debug 建置中匯入它們，但其中的任何內容都不是公開 API，也不受版本號約束。

<a id="performance"></a>
## 效能

檢視一個 App 不應改變它的行為。CutawayServer 圍繞這一點設計：

- **主執行緒保持回應。** 只有必須存取 UIKit 和 Core Animation 的工作才在主執行緒上執行，而且一次只處理一個圖層，因此 App 能在圖層之間處理事件。壓縮、編碼和網路在背景佇列上執行。
- **Cutaway 跟不上時，記憶體保持有界。** 一旦尚未送出的資料加上等待壓縮的影像超過 32 MiB，伺服器就不再開始新的影像，也不再開始下一個請求，直到用戶端跟上為止。當有 64 個請求在等待時，它停止讀取。
- **長時間工作階段中不會累積任何東西。** 圖層和視圖以弱參照持有，連線關閉時，它擁有的一切都會被釋放。
- **錯誤的輸入不會讓 App 當機。** 格式錯誤的資料和極端的請求都會以錯誤回應。

測試套件在每次執行時都會強制檢查這些限制。實測值來自 iOS 模擬器上的 Debug 建置：

| 情境 | 限制 | 實測 |
|---|---|---|
| 一棵 10,000 個圖層的樹：先取階層，再取每個圖層的影像、屬性和約束——主執行緒上最長的單次阻塞¹ | 150 ms | 65–76 ms |
| 同上，從送出請求到最後一個圖層的詳細資訊 | 30 s | 約 6 s |
| 一個從不讀取的用戶端——App 的記憶體增長，相對於 32 MiB 預算 | 1.5 × | 1.07 × |
| 在 UI 變動期間進行 200 輪階層、詳細資訊、編輯和重新整理——第 10 輪之後的記憶體增長 | 4 MiB | ≤ 0.06 MiB |
| 一次送出 1,000 個請求 | 依序回應；記憶體不隨請求數量線性增長 | 通過 |
| 超過 100,000 個經過變異、截斷和拼接的訊框 | 不當機 | 通過 |

¹ 不計單一圖層本身的算繪。

<a id="behavior-on-the-device"></a>
## 裝置上的行為

**網路**

- 只在回送位址 `127.0.0.1` 上監聽 TCP，從不在其他網路介面上監聽。
- 使用 48160 到 48167 中第一個空閒的連接埠。如果全部被佔用，則不監聽，並在 App 下次進入作用中狀態時重試。
- 如果在執行中監聽失敗（例如 App 從暫停狀態恢復後），會在 App 處於作用中狀態時於 0.5 秒後重新監聽，並優先使用原本的連接埠。之後每次失敗，間隔加倍，最長 30 秒。
- 連線使用 TCP keepalive：約 25 秒沒有回應的對端會被中斷連線，伺服器隨即就能接受下一個用戶端。

**擷取**

- 成員變數名稱是透過比對擁有者記憶體中的位址找出的；不會呼叫任何 getter。由預設（安全的）`unowned` 屬性以及陣列等集合持有的參照無法找出；`weak`、`unowned(unsafe)`、`lazy` 以及泛型類別的屬性可以找出。
- 影像逐一圖層算繪。算繪某個圖層時，會暫時把該圖層的不透明度設為 1 並使其可見；算繪不含子圖層的影像時，還會暫時隱藏子圖層。這些改動全都在同一段主執行緒程式碼內還原，不產生動畫，也不觸發佈局。
- 讀取屬性不會觸發佈局。顏色以 sRGB 傳送，因此廣色域顏色會被裁切；動態顏色依視圖目前的外觀（淺色或深色）解析。

**限制**

- 由系統算繪伺服器合成的內容不會出現在影像中：模糊效果、Metal 和影片圖層等。
- 一次只服務一個用戶端；第一個用戶端連線期間，第二個會被拒絕。

<a id="roadmap"></a>
## 路線圖

以下是 1.0 之後規劃的方向。順序和範圍可能會變動。

- **互動分析。** 顯示手勢辨識器和 target–action 配對；啟用和停用手勢；在物件上呼叫方法。
- **供宿主 App 使用的擴充 API。** 自訂屬性、虛擬子節點，以及像是預設收合的類別、顏色別名和從影像中排除的視圖等設定。
- **大型階層。** 只擷取可見圖層的快速模式；對超大影像分塊傳輸。
- **更多連線方式和平台。** 經過驗證和加密的 Wi-Fi 連線；tvOS 和 visionOS。
- **SwiftUI。** 與圖層樹並列的 SwiftUI 視圖語意階層。

<a id="faq"></a>
## 常見問題

**CutawayServer 會進入我的 App Store 建置嗎？**
預設不會。除非你啟用 `ReleaseEnabled` trait，否則沒有 `DEBUG` 的建置只包含一個空的 `start()`。請參閱 [Debug 與 Release 建置](#debug-and-release-builds)。

**網路上的其他裝置能連線到我的 App 嗎？**
不能。伺服器只監聽 `127.0.0.1`。在實機上，Mac 透過 USB 連線存取它。

**檢視會改變我的 App 嗎？**
擷取會在主執行緒繼續往下執行之前還原它動過的一切，讀取屬性也不會觸發佈局。只有你在 Cutaway 中所做的編輯，以及這些編輯引起的佈局，才會改變 App。

**為什麼模糊、影片或 Metal 視圖在影像中是空白的？**
這些內容由系統的算繪伺服器在 App 行程之外合成，因此無法從圖層樹算繪出來。

<a id="development"></a>
## 開發

複製儲存庫後執行一次 `./setup.sh`。它會簽出協定的 submodule、檢查 Xcode、在缺少 XcodeGen 和 jq 時用 Homebrew 安裝它們、把固定版本的工具安裝到 `.tools/`、設定 git hooks，並產生示範用的 Xcode 專案。重複執行也無妨。

| 工作 | 指令 |
|---|---|
| 執行所有檢查（需要 iPhone 模擬器） | `scripts/verify.sh` |
| 像 CI 一樣執行不需要模擬器的檢查 | `scripts/verify.sh --mac-only` |
| 格式化 | `"$(scripts/get-swiftformat.sh)" .` |
| Lint | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| 檢查正在執行的伺服器 | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- pre-commit hook 會格式化已暫存的 Swift 檔案，暫存格式化結果並對它們執行 lint；有 lint 違規的提交會被拒絕。Xcode 不會顯示 SwiftLint 的檢查結果，因此它們只會在這個 hook 和 `scripts/verify.sh` 中出現。
- `cutaway-probe` 連線到正在執行的伺服器，完成交握，取得圖示、階層以及每個圖層的影像和屬性，並檢查收到的每一個訊框。針對示範 App 時，`--expect-demo` 還會檢查已知的內容、顏色和屬性值。`--slow-read 200` 像慢速用戶端那樣讀取，以確認伺服器在背壓下能完成整個串流。

<a id="license"></a>
## 授權

CutawayServer 以 MIT 授權條款發佈；見 [LICENSE](../../LICENSE)。`Sources/CutawayFlatBuffers` 是 FlatBuffers 的 Swift 執行環境，採用 Apache License 2.0；見該目錄中的 [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) 檔案。
