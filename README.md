<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="Resources/readme/cutaway-server-dark.svg">
    <img src="Resources/readme/cutaway-server-light.svg" alt="CutawayServer — Capture iOS layers, images and attributes." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.1+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+-blue)](#requirements)
[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)](#installation)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](LICENSE)
[![verify](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml/badge.svg)](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml)

**English** | [简体中文](Resources/readme/README.zh-Hans.md) | [繁體中文](Resources/readme/README.zh-Hant.md) | [日本語](Resources/readme/README.ja.md) | [한국어](Resources/readme/README.ko.md) | [Español](Resources/readme/README.es.md) | [Français](Resources/readme/README.fr.md) | [Deutsch](Resources/readme/README.de.md)

CutawayServer is an iOS SDK you embed in your app during development. It lets [**Cutaway**](https://github.com/nothingsh/Cutaway), a macOS
app, inspect the interface of your running app: Cutaway connects, and CutawayServer captures the
layers, images and attributes it asks for and sends them back over the
[Cutaway protocol](https://github.com/nothingsh/CutawayProtocol). It works with apps running in the
Simulator and on devices connected to the Mac over USB.

## Features

- **One line to integrate.** Call `CutawayServer.start()` at launch, in UIKit or SwiftUI. [Installation](https://nothingsh.github.io/Cutaway/integrate/)
- **Everything Cutaway shows.** The layer tree with view controllers and member variables marked, an image of every layer, attributes that can be edited live, Auto Layout constraints, and overrides of appearance and text size. [Guide](https://nothingsh.github.io/Cutaway/guide/getting-started)
- **Your app's own details.** Add attributes, virtual nodes for what a view draws itself, color names, views collapsed by default or excluded from images. [Customizing what Cutaway shows](https://nothingsh.github.io/Cutaway/integrate/customizing)
- **Out of your release builds.** Compiled only into builds that define `DEBUG`, unless you enable the `ReleaseEnabled` trait. [Debug and Release builds](https://nothingsh.github.io/Cutaway/integrate/builds)
- **Stays out of the way.** The main thread stays responsive, memory stays bounded, and it listens on the loopback address only. [Behavior on the device](https://nothingsh.github.io/Cutaway/integrate/on-device)
- **Pure Swift, zero third-party dependencies.**

## Requirements

- iOS 13 or later; a build made with Xcode 27 runs on iOS 15 and later ([why](https://nothingsh.github.io/Cutaway/integrate/#requirements)).
- Xcode 16.3 or later, Swift 6.1 or later.
- Swift Package Manager. Other package managers are not supported.

## Installation

In Xcode, choose **File › Add Package Dependencies…**, enter
`https://github.com/nothingsh/CutawayServer`, and add the `CutawayServer` library to your app
target. In a `Package.swift`:

```swift
.package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
```

## Quick Start

Call `start()` once when the app launches, for example in
`application(_:didFinishLaunchingWithOptions:)` or in your SwiftUI `App`'s `init()`:

```swift
import CutawayServer

CutawayServer.start()
```

Run the app in the Simulator or on a device connected to your Mac, then open Cutaway. The
[installation guide](https://nothingsh.github.io/Cutaway/integrate/) has the code for UIKit and SwiftUI and what happens at launch.

## Documentation

Everything else is on the [Cutaway website](https://nothingsh.github.io/Cutaway/):

- [Integrate](https://nothingsh.github.io/Cutaway/integrate/): installation, [Debug and Release builds](https://nothingsh.github.io/Cutaway/integrate/builds), [customizing what Cutaway shows](https://nothingsh.github.io/Cutaway/integrate/customizing), [behavior on the device](https://nothingsh.github.io/Cutaway/integrate/on-device) and [limitations](https://nothingsh.github.io/Cutaway/integrate/limitations).
- [Protocol](https://nothingsh.github.io/Cutaway/protocol/): how Cutaway and CutawayServer talk, and which versions work together.
- [FAQ and troubleshooting](https://nothingsh.github.io/Cutaway/resources/faq), [Privacy and security](https://nothingsh.github.io/Cutaway/resources/privacy), [Performance](https://nothingsh.github.io/Cutaway/resources/performance), [Release notes](https://nothingsh.github.io/Cutaway/resources/releases), [Roadmap](https://nothingsh.github.io/Cutaway/resources/roadmap).

## Development

How to build and check CutawayServer, and how changes are reviewed, is in
[CONTRIBUTING.md](CONTRIBUTING.md). The [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) page explains
how the three repositories fit together.

## License

CutawayServer is released under the MIT license; see [LICENSE](LICENSE).
`Sources/CutawayFlatBuffers` is the FlatBuffers Swift runtime, under the Apache License 2.0; see
the [LICENSE](Sources/CutawayFlatBuffers/LICENSE) file in that directory.
