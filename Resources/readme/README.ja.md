<p align="center">
  <picture><source media="(prefers-color-scheme: dark)" srcset="cutaway-server-dark.svg"><img src="cutaway-server-light.svg" alt="CutawayServer — Capture iOS layers, images and attributes." width="850"></picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.1+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+-blue)](#要件)
[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)](#インストール)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](../../LICENSE)
[![verify](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml/badge.svg)](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | **日本語** | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*これは翻訳です。内容が異なる場合は [英語版の README](../../README.md) が優先されます。*

CutawayServer は、開発中のアプリに組み込む iOS SDK です。macOS アプリ [**Cutaway**](https://github.com/nothingsh/Cutaway) が実行中のアプリのインターフェイスを調べられるようにします。Cutaway が接続すると、CutawayServer は要求されたレイヤー、画像、属性を取得し、[Cutaway プロトコル](https://github.com/nothingsh/CutawayProtocol)で送り返します。シミュレータで動くアプリにも、USB で Mac に接続したデバイスで動くアプリにも対応しています。

<a id="features"></a>
## 機能

- **1 行で組み込み。** 起動時に `CutawayServer.start()` を呼ぶだけ。UIKit でも SwiftUI でも使えます。 [Installation](https://nothingsh.github.io/Cutaway/integrate/)
- **Cutaway が表示するすべて。** ビューコントローラとメンバー変数を示したレイヤーツリー、各レイヤーの画像、その場で編集できる属性、Auto Layout の制約、外観と文字サイズの上書き。 [Guide](https://nothingsh.github.io/Cutaway/guide/getting-started)
- **アプリ独自の情報。** 属性の追加、ビューが自分で描く内容の仮想ノード、カラー名の登録、デフォルトで折りたたむビューや画像から除外するビュー。 [Customizing what Cutaway shows](https://nothingsh.github.io/Cutaway/integrate/customizing)
- **リリースビルドには入りません。** `DEBUG` を定義したビルドにだけコンパイルされます（`ReleaseEnabled` トレイトを有効にした場合を除く）。 [Debug and Release builds](https://nothingsh.github.io/Cutaway/integrate/builds)
- **アプリの邪魔をしません。** メインスレッドは応答を保ち、メモリには上限があり、ループバックアドレスだけで待ち受けます。 [Behavior on the device](https://nothingsh.github.io/Cutaway/integrate/on-device)
- **純粋な Swift、サードパーティ依存なし。**

<a id="requirements"></a>
## 要件

- iOS 13 以降。Xcode 27 でビルドしたものは iOS 15 以降で動作します（[理由](https://nothingsh.github.io/Cutaway/integrate/#requirements)）。
- Xcode 16.3 以降、Swift 6.1 以降。
- Swift Package Manager。ほかのパッケージマネージャには対応していません。

<a id="installation"></a>
## インストール

Xcode で **File › Add Package Dependencies…** を選び、
`https://github.com/nothingsh/CutawayServer` を入力して、`CutawayServer` ライブラリをアプリのターゲットに追加します。`Package.swift` では：

```swift
.package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
```

<a id="quick-start"></a>
## クイックスタート

アプリの起動時に `start()` を一度呼びます。たとえば `application(_:didFinishLaunchingWithOptions:)` や SwiftUI の `App` の `init()` で：

```swift
import CutawayServer

CutawayServer.start()
```

シミュレータ、または Mac に接続したデバイスでアプリを実行し、Cutaway を開きます。[インストールガイド](https://nothingsh.github.io/Cutaway/integrate/)に、UIKit と SwiftUI のコードと起動時に起きることが書かれています。

<a id="documentation"></a>
## ドキュメント

そのほかの内容はすべて [Cutaway のウェブサイト](https://nothingsh.github.io/Cutaway/)（英語）にあります：

- [Integrate](https://nothingsh.github.io/Cutaway/integrate/)：インストール、[Debug と Release のビルド](https://nothingsh.github.io/Cutaway/integrate/builds)、[Cutaway に表示する内容のカスタマイズ](https://nothingsh.github.io/Cutaway/integrate/customizing)、[デバイス上での動作](https://nothingsh.github.io/Cutaway/integrate/on-device)、[制限事項](https://nothingsh.github.io/Cutaway/integrate/limitations)。
- [Protocol](https://nothingsh.github.io/Cutaway/protocol/)：Cutaway と CutawayServer の通信方法と、組み合わせて使えるバージョン。
- [よくある質問とトラブルシューティング](https://nothingsh.github.io/Cutaway/resources/faq)、[プライバシーとセキュリティ](https://nothingsh.github.io/Cutaway/resources/privacy)、[パフォーマンス](https://nothingsh.github.io/Cutaway/resources/performance)、[リリースノート](https://nothingsh.github.io/Cutaway/resources/releases)、[ロードマップ](https://nothingsh.github.io/Cutaway/resources/roadmap)。

<a id="development"></a>
## 開発

CutawayServer のビルドとチェックの方法、変更のレビューの進め方は [CONTRIBUTING.md](../../CONTRIBUTING.md) にあります。ウェブサイトの [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) ページでは、3 つのリポジトリの関係を説明しています。

<a id="license"></a>
## ライセンス

CutawayServer は MIT ライセンスで公開されています。[LICENSE](../../LICENSE) を参照してください。`Sources/CutawayFlatBuffers` は FlatBuffers の Swift ランタイムで、Apache License 2.0 の下で提供されています。同じディレクトリにある [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) ファイルを参照してください。
