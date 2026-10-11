<p align="center">
  <picture><source media="(prefers-color-scheme: dark)" srcset="cutaway-server-dark.svg"><img src="cutaway-server-light.svg" alt="CutawayServer — Capture iOS layers, images and attributes." width="850"></picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.1+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+-blue)](#requirements)
[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)](#installation)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](../../LICENSE)
[![verify](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml/badge.svg)](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | **日本語** | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*これは翻訳です。内容が異なる場合は [英語版の README](../../README.md) が優先されます。*

CutawayServer は、開発中にアプリへ組み込む iOS SDK です。macOS アプリ [**Cutaway**](https://github.com/nothingsh/Cutaway) から、実行中のアプリのビュー階層を調べられるようにします。Cutaway が接続すると、CutawayServer は要求されたレイヤー、画像、属性をキャプチャし、[Cutaway プロトコル](https://github.com/nothingsh/CutawayProtocol)で送り返します。

シミュレータで実行中のアプリと、USB で Mac に接続したデバイス上のアプリで動作します。

<a id="features"></a>
## 機能

**Cutaway で見えるもの**

- すべてのウィンドウのレイヤーツリー。ビューコントローラのルートビューと、各レイヤーやビューを保持しているメンバー変数が示されます。
- 各レイヤーについて、そのレイヤー単体の画像とサブレイヤーを含めた画像。ストリーミングで送られ、キャンセルできます。
- 各レイヤーとビューの属性。編集可能なものが示され、Cutaway で行った編集は実行中のアプリに反映されます。
- 各ビューを参照する Auto Layout 制約と、それぞれが満たされているかどうか。

**開発のための設計**

- 1 行で組み込めます: `CutawayServer.start()`。
- デフォルトでは Release ビルドにはコンパイルされません。
- ループバックアドレスでのみ待ち受け、一度に 1 つのクライアントにのみ応答します。
- 純粋な Swift で、サードパーティへの依存はゼロです。

<a id="requirements"></a>
## 動作要件

- iOS 13 以降（Xcode 27 でビルドする場合は iOS 15 以降。下の注記を参照）。
- Xcode 16.3 以降、Swift 6.1 以降。
- Swift Package Manager。他のパッケージマネージャーには対応していません。

> [!NOTE]
> すべてのモジュールは、デプロイメントターゲットを iOS 13 として iOS SDK に対して型チェックされています。そのため、このパッケージは availability チェックなしにそれより新しいものを使っていません。ただし Xcode 27 のビルドシステムは iOS 15 未満のデプロイメントターゲットをサポートしておらず、パッケージのデプロイメントターゲットを 15.0 に引き上げます。このため、Xcode 27 でビルドしたものはiOS 15 以降で動作します。このパッケージは iOS 13 や 14 で実行されたことが一度もありません。

<a id="installation"></a>
## インストール

Xcode で **File › Add Package Dependencies…** を選び、`https://github.com/nothingsh/CutawayServer` を入力して、`CutawayServer` ライブラリをアプリのターゲットに追加します。

`Package.swift` では次のように書き、

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.0.0")
]
```

ターゲットの依存関係にプロダクト `CutawayServer` を追加します。

<a id="quick-start"></a>
## クイックスタート

アプリの起動時に `start()` を 1 回呼び出します。

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

`start()` はどのスレッドからでも呼び出せます。もう一度呼び出しても何も起きません。サーバーはアプリがアクティブになった時点で待ち受けを開始します。アプリをシミュレータ、または Mac に接続したデバイスで実行し、Cutaway を開いてください。

<a id="debug-and-release-builds"></a>
## Debug ビルドと Release ビルド

デフォルトでは、サーバーは `DEBUG` を定義しているビルドにのみコンパイルされます。それ以外のすべてのビルドでは `start()` は空の関数で、プロダクトには待ち受けのコードが含まれません。

パッケージから `DEBUG` が見えるかどうかは、ホストアプリのビルド構成の名前によって決まります。

| ホストの構成名 | パッケージで `DEBUG` が定義されるか |
|---|---|
| `Debug`、および `Debug` または `Development` を含む名前（例: `DebugQA`） | はい |
| `Release`、`Staging`、`QA` などそれ以外のすべての名前（構成を Debug からコピーした場合も含む） | いいえ |

2 番目の種類の構成でサーバーを使うには、パッケージの trait（パッケージが提供するオプション機能のスイッチ）`ReleaseEnabled` を有効にします。

- SwiftPM のホストの場合:

  ```swift
  .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.0.0", traits: ["ReleaseEnabled"])
  ```

- Xcode プロジェクトの場合: このパッケージ依存関係で trait `ReleaseEnabled` を有効にします。XcodeGen を使う場合は `packages.<name>.traits` に記載します。`Demo/release-enabled.yml` が例です。

> [!WARNING]
> trait はホストの**すべての**構成に適用されます。App Store に提出する構成も例外ではありません。有効にした後は、出荷するビルドで `start()` を呼ばないようにするのはホスト側の責任です。

`DEBUG` も trait もない場合、プロダクトに含まれるこのパッケージのものはエントリーポイントだけです。サーバーも、`Network` のシンボルも、プロトコルのエンコードコードも含まれません。テストスクリプトは、デモアプリの Release ビルドに対して `nm` でこれを確認します。

`CutawayWire` と `CutawayFlatBuffers` は実装の詳細です。ホストは Debug ビルドでこれらを import できますが、その中のどれも公開 API ではなく、バージョン番号の保証対象でもありません。

<a id="performance"></a>
## パフォーマンス

アプリを調べることで、アプリの振る舞いが変わってはなりません。CutawayServer はこの考えに基づいて設計されています。

- **メインスレッドの応答性を保ちます。** UIKit と Core Animation に触れる必要がある処理だけがメインスレッドで、1 レイヤーずつ実行されるため、アプリはレイヤーとレイヤーの合間にイベントを処理できます。圧縮、エンコード、ネットワーク処理はバックグラウンドキューで実行されます。
- **Cutaway の受信が追いつかなくても、メモリ使用量には上限があります。** 未送信のデータと圧縮待ちの画像の合計が 32 MiB を超えると、サーバーはクライアントが追いつくまで新しい画像も次のリクエストも開始しません。待機中のリクエストが 64 件になると、読み取りを停止します。
- **長いセッションでも何も蓄積しません。** レイヤーとビューは弱参照で保持され、接続が所有するものはすべて、接続が閉じたときに解放されます。
- **不正な入力でアプリがクラッシュすることはありません。** 不正な形式のデータや極端なリクエストにはエラーで応答します。

テストスイートは実行のたびにこれらの上限を検証します。計測値は iOS Simulator、Debug ビルドでのものです。

| シナリオ | 上限 | 計測値 |
|---|---|---|
| 10,000 レイヤーのツリー: 階層を取得し、続いてすべてのレイヤーの画像、属性、制約を取得 — メインスレッドを一度に占有する最長時間¹ | 150 ms | 65–76 ms |
| 同じ処理の、リクエストから最後のレイヤーの詳細まで | 30 s | 約 6 s |
| まったく読み取らないクライアント — アプリのメモリ増加量（32 MiB の予算に対する比） | 1.5 × | 1.07 × |
| UI が変化する中での、階層、詳細、編集、リフレッシュの 200 ラウンド — 10 ラウンド目以降のメモリ増加量 | 4 MiB | ≤ 0.06 MiB |
| 一度に送信された 1,000 件のリクエスト | 順番どおりに応答される。メモリは件数に比例して増えない | 合格 |
| 100,000 を超える、変異・切り詰め・継ぎ合わせを加えたフレーム | クラッシュしない | 合格 |

¹ 単一レイヤーそのもののレンダリングは含みません。

<a id="behavior-on-the-device"></a>
## デバイス上での動作

**ネットワーク**

- TCP の待ち受けはループバックアドレス `127.0.0.1` でのみ行い、他のネットワークインターフェースで待ち受けることはありません。
- 48160 から 48167 のうち、最初に空いているポートを使います。すべて使用中の場合は待ち受けず、次にアプリがアクティブになったときに再試行します。
- 実行中に待ち受けが失敗した場合（たとえばアプリがサスペンドから復帰した後）、アプリがアクティブであれば 0.5 秒後に、それまで使っていたポートを優先して再び待ち受けます。さらに失敗するたびに間隔は 2 倍になり、最大 30 秒になります。
- 接続には TCP keepalive を使います。約 25 秒応答しない相手は切断され、サーバーはすぐに次のクライアントを受け入れられます。

**キャプチャ**

- メンバー変数名は、所有者のメモリ内のアドレスを比較して特定します。getter は呼び出しません。デフォルトの（安全な）`unowned` プロパティや、配列などのコレクションが保持する参照は検出されません。`weak`、`unowned(unsafe)`、`lazy`、ジェネリッククラスのプロパティは検出されます。
- 画像はレイヤーごとにレンダリングされます。レイヤーのレンダリング中は、そのレイヤーの opacity を一時的に 1 にして表示状態にし、サブレイヤーなしの画像では一時的にサブレイヤーを非表示にします。これらはすべて、メインスレッドの同じひと続きのコードの中で、アニメーションもレイアウトも伴わずに元に戻されます。
- 属性の読み取りではレイアウトは発生しません。色は sRGB で送られるため、広色域の色はクリップされます。ダイナミックカラーはビューの現在の外観（ライトまたはダーク）に合わせて解決されます。

**制限事項**

- システムのレンダーサーバーが合成するコンテンツは画像に含まれません。ブラー効果、Metal や動画のレイヤーなどです。
- 一度に 1 クライアントのみです。最初のクライアントが接続している間、2 つ目のクライアントは拒否されます。

<a id="roadmap"></a>
## ロードマップ

1.0 以降に予定している方向性です。順序と範囲は変わる可能性があります。

- **プロトコル 1.0。** Cutaway プロトコルを凍結し、以後の機能はプロトコルへの追加だけで実現します。
- **インタラクションの分析。** ジェスチャーレコグナイザーと target–action の組を表示し、ジェスチャーを有効化・無効化し、オブジェクトのメソッドを呼び出します。
- **ホストアプリ向けの拡張 API。** カスタム属性、仮想の子ノード、そしてデフォルトで折りたたむクラス、色のエイリアス、画像から除外するビューなどの設定。
- **大規模な階層。** 可視レイヤーだけをキャプチャする高速モード。非常に大きな画像の分割転送。
- **より多くの接続方法とプラットフォーム。** 認証と暗号化を備えた Wi-Fi 接続。tvOS と visionOS。
- **SwiftUI。** レイヤーツリーと並べて、SwiftUI ビューの意味的な階層を表示します。

<a id="faq"></a>
## FAQ

**CutawayServer は App Store 向けのビルドに入ってしまいますか？**
デフォルトでは入りません。`ReleaseEnabled` trait を有効にしない限り、`DEBUG` のないビルドに含まれるのは空の `start()` だけです。[Debug ビルドと Release ビルド](#debug-and-release-builds)を参照してください。

**ネットワーク上の他のデバイスから自分のアプリに接続できますか？**
いいえ。サーバーは `127.0.0.1` でのみ待ち受けます。デバイスの場合、Mac は USB 接続を通じてサーバーに到達します。

**調べることでアプリは変わりますか？**
キャプチャは、触れたものをすべて、メインスレッドが次へ進む前に元に戻します。また、属性の読み取りではレイアウトは発生しません。アプリを変えるのは、Cutaway で行った編集と、それによって生じるレイアウトだけです。

**ブラー、動画、Metal のビューが画像で空白になるのはなぜですか？**
そのコンテンツはアプリのプロセスの外にあるシステムのレンダーサーバーで合成されるため、レイヤーツリーからはレンダリングできません。

<a id="development"></a>
## 開発

クローンした後、`./setup.sh` を 1 回実行してください。プロトコルのサブモジュールをチェックアウトし、Xcode の有無を確認し、XcodeGen と jq がなければ Homebrew でインストールし、バージョンを固定したツールを `.tools/` にインストールし、git フックを設定し、デモの Xcode プロジェクトを生成します。再度実行しても害はありません。

| 作業 | コマンド |
|---|---|
| すべてのチェックを実行（iPhone シミュレータが必要） | `scripts/verify.sh` |
| シミュレータを必要としないチェックを CI と同じように実行 | `scripts/verify.sh --mac-only` |
| フォーマット | `"$(scripts/get-swiftformat.sh)" .` |
| Lint | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| 実行中のサーバーを確認 | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- pre-commit フックは、ステージされた Swift ファイルをフォーマットし、その結果をステージして lint します。lint 違反のあるコミットは拒否されます。Xcode は SwiftLint の指摘を表示しないため、指摘が現れるのはこのフックと `scripts/verify.sh` です。
- `cutaway-probe` は実行中のサーバーに接続してハンドシェイクを行い、アイコン、階層、すべてのレイヤーの画像と属性を取得し、受信したすべてのフレームを検査します。デモアプリに対しては、`--expect-demo` で既知の内容、色、属性値も確認します。`--slow-read 200` は遅いクライアントのように読み取り、バックプレッシャーの下でもサーバーがストリームを最後まで送り切ることを確認します。

<a id="license"></a>
## ライセンス

CutawayServer は MIT ライセンスで公開されています。[LICENSE](../../LICENSE) を参照してください。`Sources/CutawayFlatBuffers` は FlatBuffers の Swift ランタイムで、Apache License 2.0 の下で提供されています。同じディレクトリにある [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) ファイルを参照してください。
