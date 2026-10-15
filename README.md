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
app, inspect the view hierarchy of your running app: Cutaway connects, and CutawayServer captures
the layers, images and attributes it asks for and sends them back over the [Cutaway protocol](https://github.com/nothingsh/CutawayProtocol).

It works with apps running in the Simulator and on devices connected to the Mac over USB.

## Features

**What Cutaway sees**

- The layer tree of every window, with the root views of view controllers and the member
  variables that hold each layer or view marked.
- For each layer, an image of the layer alone and one with its sublayers, streamed and
  cancellable.
- The attributes of each layer and view, with the editable ones marked; edits made in Cutaway are
  applied to the running app.
- The Auto Layout constraints that refer to each view, and whether each one is satisfied.

**Built for development**

- One line to integrate: `CutawayServer.start()`.
- Compiled out of Release builds by default.
- Listens on the loopback address only and serves one client at a time.
- Pure Swift, zero third-party dependencies.

## Requirements

- iOS 13 or later (iOS 15 or later when built with Xcode 27; see the note below).
- Xcode 16.3 or later, Swift 6.1 or later.
- Swift Package Manager. Other package managers are not supported.

> [!NOTE]
> Every module is type-checked against the iOS SDK with an iOS 13 deployment target, so the package
> uses nothing newer without an availability check. Xcode 27's build system, however, does not
> support deployment targets below iOS 15 and raises the package's to 15.0, so a build made with
> Xcode 27 runs on iOS 15 and later. The package has never been run on iOS 13 or 14.

## Installation

In Xcode, choose **File › Add Package Dependencies…**, enter
`https://github.com/nothingsh/CutawayServer`, and add the `CutawayServer` library to your app
target.

In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0")
]
```

and add the product `CutawayServer` to your target's dependencies.

## Quick Start

Call `start()` once when the app launches.

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

`start()` can be called from any thread; calling it again has no effect. The server starts
listening once the app becomes active. Run the app in the Simulator or on a device connected to
your Mac, then open Cutaway.

## Debug and Release Builds

By default the server is compiled only into builds that define `DEBUG`. In every other build
`start()` is an empty function and the product contains no listening code.

Whether the package sees `DEBUG` depends on the name of the host app's build configuration:

| Host configuration name | `DEBUG` defined in the package? |
|---|---|
| `Debug`, and names that contain `Debug` or `Development` (for example `DebugQA`) | Yes |
| `Release`, `Staging`, `QA` and any other name, even if the configuration was copied from Debug | No |

To use the server in configurations of the second kind, enable the package trait
`ReleaseEnabled`:

- In a SwiftPM host:

  ```swift
  .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0", traits: ["ReleaseEnabled"])
  ```

- In an Xcode project: enable the trait `ReleaseEnabled` on this package dependency. With
  XcodeGen, list it under `packages.<name>.traits`; `Demo/release-enabled.yml` is an example.

> [!WARNING]
> The trait applies to **every** configuration of the host, including the one you submit to the
> App Store. Once it is enabled, it is up to the host not to call `start()` in builds it ships.

Without `DEBUG` and without the trait, the product contains nothing of this package but the entry
point: no server, no `Network` symbols, and none of the protocol's encoding code. The test script
checks this on the demo app's Release build with `nm`.

`CutawayWire` and `CutawayFlatBuffers` are implementation details. A host can import them in a
Debug build, but nothing in them is public API or covered by the version number.

## Performance

Inspecting an app should not change how it behaves. CutawayServer is designed around that:

- **The main thread stays responsive.** Only the work that must touch UIKit and Core Animation runs
  on the main thread, one layer at a time, so the app handles events between layers. Compression,
  encoding and networking run on background queues.
- **Memory stays bounded when Cutaway falls behind.** Once the data not yet sent plus the images
  waiting to be compressed exceed 32 MiB, the server starts no new image and no next request until
  the client catches up. With 64 requests waiting, it stops reading.
- **Nothing accumulates over a long session.** Layers and views are held weakly, and everything a
  connection owns is released when it closes.
- **Bad input does not crash the app.** Malformed data and extreme requests are answered with
  errors.

The test suite enforces these limits on every run. The measured values are from the iOS Simulator,
Debug build:

| Scenario | Limit | Measured |
|---|---|---|
| A 10,000-layer tree: hierarchy, then images, attributes and constraints of every layer — longest single main-thread block¹ | 150 ms | 65–76 ms |
| The same, from the request to the last layer's details | 30 s | about 6 s |
| A client that never reads — app memory growth, relative to the 32 MiB budget | 1.5 × | 1.07 × |
| 200 rounds of hierarchy, details, edits and refreshes while the UI changes — memory growth after round 10 | 4 MiB | ≤ 0.06 MiB |
| 1,000 requests sent at once | answered in order; memory does not grow linearly with the count | passes |
| Over 100,000 mutated, truncated and spliced frames | no crash | passes |

¹ Not counting the rendering of a single layer itself.

## Behavior on the Device

**Networking**

- It listens for TCP on the loopback address `127.0.0.1` only, never on other network interfaces.
- It takes the first free port from 48160 to 48167. If all of them are taken it does not listen,
  and tries again the next time the app becomes active.
- If listening fails while running (for example after the app resumes from suspension), it listens
  again after 0.5 seconds while the app is active, preferring the port it had. Further failures
  double the interval, up to 30 seconds.
- Connections use TCP keepalive: a peer that does not answer for about 25 seconds is disconnected,
  and the server can accept the next client right away.

**Capturing**

- Member variable names are found by comparing addresses in the owner's memory; no getter is
  called. References held by default (safe) `unowned` properties and by collections such as arrays
  are not found; `weak`, `unowned(unsafe)`, `lazy` and properties of generic classes are.
- Images are rendered layer by layer. While rendering a layer it temporarily sets the layer's
  opacity to 1 and makes it visible, and for the image without sublayers temporarily hides the
  sublayers. All of this is restored in the same stretch of main-thread code, with no animation
  and no layout.
- Reading attributes does not trigger layout. Colors are sent in sRGB, so wide-gamut colors are
  clipped; dynamic colors are resolved for the view's current appearance (light or dark).

**Limitations**

- Content composited by the system's render server is not in the images: blur effects, Metal and
  video layers, and the like.
- One client at a time; a second one is turned away while the first is connected.

## Roadmap

These are the directions planned after 1.0. Order and scope may change.

- **Interaction analysis.** Show gesture recognizers and target–action pairs; enable and disable
  gestures; call methods on objects.
- **Extension API for host apps.** Custom attributes, virtual child nodes, and configuration such
  as classes collapsed by default, color aliases and views excluded from images.
- **Large hierarchies.** A fast mode that captures only visible layers; chunked transfer for very
  large images.
- **More connections and platforms.** Wi-Fi connections, authenticated and encrypted; tvOS and
  visionOS.
- **SwiftUI.** A semantic hierarchy of SwiftUI views alongside the layer tree.

## FAQ

**Will CutawayServer end up in my App Store build?**
Not by default. Unless you enable the `ReleaseEnabled` trait, a build without `DEBUG` contains only
an empty `start()`. See [Debug and Release Builds](#debug-and-release-builds).

**Can other devices on the network connect to my app?**
No. The server listens on `127.0.0.1` only. On a device, the Mac reaches it through the USB
connection.

**Does inspecting change my app?**
Capturing restores everything it touches before the main thread moves on, and reading attributes
does not trigger layout. Only edits you make in Cutaway change the app, along with the layout they
cause.

**Why is a blur, video or Metal view blank in the images?**
That content is composited by the system's render server, outside the app's process, so it cannot
be rendered from the layer tree.

## Development

After cloning, run `./setup.sh` once. It checks out the protocol submodule, checks for Xcode,
installs XcodeGen and jq with Homebrew if they are missing, installs the pinned tools into
`.tools/`, sets up the git hooks and generates the demo Xcode projects. Running it again is
harmless.

| Task | Command |
|---|---|
| Run every check (needs an iPhone simulator) | `scripts/verify.sh` |
| Run the checks that need no simulator, as CI does | `scripts/verify.sh --mac-only` |
| Format | `"$(scripts/get-swiftformat.sh)" .` |
| Lint | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| Check a running server | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- The pre-commit hook formats the staged Swift files, stages the result and lints them; a commit
  with lint violations is rejected. Xcode does not show SwiftLint's findings, so the hook and
  `scripts/verify.sh` are where they surface.
- `cutaway-probe` connects to a running server, performs the handshake, fetches the icon, the
  hierarchy, and the images and attributes of every layer, and checks every frame it receives.
  Against the demo app, `--expect-demo` also checks known content, colors and attribute values.
  `--slow-read 200` reads like a slow client to confirm that the server completes the stream under
  backpressure.

## License

CutawayServer is released under the MIT license; see [LICENSE](LICENSE).
`Sources/CutawayFlatBuffers` is the FlatBuffers Swift runtime, under the Apache License 2.0; see
the [LICENSE](Sources/CutawayFlatBuffers/LICENSE) file in that directory.
