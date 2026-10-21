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

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Français](README.fr.md) | **Deutsch**

*Dies ist eine Übersetzung; weicht sie vom [englischen README](../../README.md) ab, ist das englische README maßgeblich.*

CutawayServer ist ein iOS-SDK, das du während der Entwicklung in deine App einbettest. Es ermöglicht [**Cutaway**](https://github.com/nothingsh/Cutaway), einer macOS-App, die Oberfläche deiner laufenden App zu untersuchen: Cutaway verbindet sich, und CutawayServer erfasst die angefragten Layer, Bilder und Attribute und sendet sie über das [Cutaway-Protokoll](https://github.com/nothingsh/CutawayProtocol) zurück. Es funktioniert mit Apps im Simulator und auf Geräten, die per USB mit dem Mac verbunden sind.

<a id="features"></a>
## Funktionen

- **Eine Zeile zur Integration.** Rufe beim Start `CutawayServer.start()` auf, in UIKit oder SwiftUI. [Installation](https://nothingsh.github.io/Cutaway/integrate/)
- **Alles, was Cutaway zeigt.** Der Layer-Baum mit markierten View Controllern und Membervariablen, ein Bild jedes Layers, live bearbeitbare Attribute, Auto-Layout-Constraints sowie das Überschreiben von Erscheinungsbild und Textgröße. [Guide](https://nothingsh.github.io/Cutaway/guide/getting-started)
- **Die eigenen Details deiner App.** Füge Attribute hinzu, virtuelle Knoten für das, was eine View selbst zeichnet, Farbnamen sowie Views, die standardmäßig eingeklappt oder von Bildern ausgeschlossen sind. [Customizing what Cutaway shows](https://nothingsh.github.io/Cutaway/integrate/customizing)
- **Nicht in deinen Release-Builds.** Nur in Builds kompiliert, die `DEBUG` definieren, es sei denn, du aktivierst den Trait `ReleaseEnabled`. [Debug and Release builds](https://nothingsh.github.io/Cutaway/integrate/builds)
- **Bleibt im Hintergrund.** Der Hauptthread bleibt reaktionsfähig, der Speicher bleibt begrenzt, und es lauscht nur auf der Loopback-Adresse. [Behavior on the device](https://nothingsh.github.io/Cutaway/integrate/on-device)
- **Reines Swift, keine Abhängigkeiten von Drittanbietern.**

<a id="requirements"></a>
## Voraussetzungen

- iOS 13 oder neuer; ein mit Xcode 27 erstellter Build läuft ab iOS 15 ([warum](https://nothingsh.github.io/Cutaway/integrate/#requirements)).
- Xcode 16.3 oder neuer, Swift 6.1 oder neuer.
- Swift Package Manager. Andere Paketmanager werden nicht unterstützt.

<a id="installation"></a>
## Installation

Wähle in Xcode **File › Add Package Dependencies…**, gib
`https://github.com/nothingsh/CutawayServer` ein und füge die Bibliothek `CutawayServer` zum Target deiner App hinzu. In einer `Package.swift`:

```swift
.package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
```

<a id="quick-start"></a>
## Schnellstart

Rufe `start()` einmal beim Start der App auf, zum Beispiel in
`application(_:didFinishLaunchingWithOptions:)` oder im `init()` deiner SwiftUI-`App`:

```swift
import CutawayServer

CutawayServer.start()
```

Starte die App im Simulator oder auf einem mit deinem Mac verbundenen Gerät und öffne dann Cutaway. Die
[Installationsanleitung](https://nothingsh.github.io/Cutaway/integrate/) enthält den Code für UIKit und SwiftUI und beschreibt, was beim Start passiert.

<a id="documentation"></a>
## Dokumentation

Alles Weitere steht auf der [Cutaway-Website](https://nothingsh.github.io/Cutaway/) (auf Englisch):

- [Integrate](https://nothingsh.github.io/Cutaway/integrate/): Installation, [Debug- und Release-Builds](https://nothingsh.github.io/Cutaway/integrate/builds), [anpassen, was Cutaway zeigt](https://nothingsh.github.io/Cutaway/integrate/customizing), [Verhalten auf dem Gerät](https://nothingsh.github.io/Cutaway/integrate/on-device) und [Einschränkungen](https://nothingsh.github.io/Cutaway/integrate/limitations).
- [Protocol](https://nothingsh.github.io/Cutaway/protocol/): wie Cutaway und CutawayServer kommunizieren und welche Versionen zusammenpassen.
- [FAQ und Fehlerbehebung](https://nothingsh.github.io/Cutaway/resources/faq), [Datenschutz und Sicherheit](https://nothingsh.github.io/Cutaway/resources/privacy), [Leistung](https://nothingsh.github.io/Cutaway/resources/performance), [Versionshinweise](https://nothingsh.github.io/Cutaway/resources/releases), [Roadmap](https://nothingsh.github.io/Cutaway/resources/roadmap).

<a id="development"></a>
## Entwicklung

Wie du CutawayServer baust und prüfst und wie Änderungen geprüft werden, steht in
[CONTRIBUTING.md](../../CONTRIBUTING.md). Die Seite [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) erklärt,
wie die drei Repositorys zusammenhängen.

<a id="license"></a>
## Lizenz

CutawayServer wird unter der MIT-Lizenz veröffentlicht; siehe [LICENSE](../../LICENSE).
`Sources/CutawayFlatBuffers` ist die Swift-Laufzeit von FlatBuffers unter der Apache License 2.0;
siehe die Datei [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) in diesem Verzeichnis.
