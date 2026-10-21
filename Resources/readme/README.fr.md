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

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Español](README.es.md) | **Français** | [Deutsch](README.de.md)

*Ceci est une traduction ; en cas de divergence avec le [README anglais](../../README.md), le README anglais fait foi.*

CutawayServer est un SDK iOS que vous intégrez à votre app pendant le développement. Il permet à [**Cutaway**](https://github.com/nothingsh/Cutaway), une app macOS, d’inspecter l’interface de votre app en cours d’exécution : Cutaway se connecte, et CutawayServer capture les calques, les images et les attributs demandés, puis les renvoie via le [protocole Cutaway](https://github.com/nothingsh/CutawayProtocol). Il fonctionne avec les apps exécutées dans le Simulateur et sur les appareils reliés au Mac en USB.

<a id="features"></a>
## Fonctionnalités

- **Une ligne pour l’intégrer.** Appelez `CutawayServer.start()` au lancement, en UIKit comme en SwiftUI. [Installation](https://nothingsh.github.io/Cutaway/integrate/)
- **Tout ce que Cutaway affiche.** L’arbre des calques avec les contrôleurs de vue et les variables membres signalés, une image de chaque calque, des attributs modifiables en direct, les contraintes Auto Layout, et le remplacement de l’apparence et de la taille du texte. [Guide](https://nothingsh.github.io/Cutaway/guide/getting-started)
- **Les informations propres à votre app.** Ajoutez des attributs, des nœuds virtuels pour ce qu’une vue dessine elle-même, des noms de couleurs, et des vues repliées par défaut ou exclues des images. [Customizing what Cutaway shows](https://nothingsh.github.io/Cutaway/integrate/customizing)
- **Absent de vos builds de release.** Compilé uniquement dans les builds qui définissent `DEBUG`, sauf si vous activez le trait `ReleaseEnabled`. [Debug and Release builds](https://nothingsh.github.io/Cutaway/integrate/builds)
- **Discret.** Le thread principal reste réactif, la mémoire reste bornée, et il n’écoute que sur l’adresse de bouclage. [Behavior on the device](https://nothingsh.github.io/Cutaway/integrate/on-device)
- **Swift pur, aucune dépendance tierce.**

<a id="requirements"></a>
## Prérequis

- iOS 13 ou ultérieur ; un build réalisé avec Xcode 27 fonctionne sur iOS 15 ou ultérieur ([pourquoi](https://nothingsh.github.io/Cutaway/integrate/#requirements)).
- Xcode 16.3 ou ultérieur, Swift 6.1 ou ultérieur.
- Swift Package Manager. Les autres gestionnaires de paquets ne sont pas pris en charge.

<a id="installation"></a>
## Installation

Dans Xcode, choisissez **File › Add Package Dependencies…**, saisissez
`https://github.com/nothingsh/CutawayServer` et ajoutez la bibliothèque `CutawayServer` à la cible de votre app. Dans un `Package.swift` :

```swift
.package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
```

<a id="quick-start"></a>
## Démarrage rapide

Appelez `start()` une fois au lancement de l’app, par exemple dans
`application(_:didFinishLaunchingWithOptions:)` ou dans l’`init()` de votre `App` SwiftUI :

```swift
import CutawayServer

CutawayServer.start()
```

Lancez l’app dans le Simulateur ou sur un appareil relié à votre Mac, puis ouvrez Cutaway. Le
[guide d’installation](https://nothingsh.github.io/Cutaway/integrate/) donne le code pour UIKit et SwiftUI et décrit ce qui se passe au lancement.

<a id="documentation"></a>
## Documentation

Tout le reste se trouve sur le [site de Cutaway](https://nothingsh.github.io/Cutaway/) (en anglais) :

- [Integrate](https://nothingsh.github.io/Cutaway/integrate/) : installation, [builds Debug et Release](https://nothingsh.github.io/Cutaway/integrate/builds), [personnaliser ce qu’affiche Cutaway](https://nothingsh.github.io/Cutaway/integrate/customizing), [comportement sur l’appareil](https://nothingsh.github.io/Cutaway/integrate/on-device) et [limites](https://nothingsh.github.io/Cutaway/integrate/limitations).
- [Protocol](https://nothingsh.github.io/Cutaway/protocol/) : comment Cutaway et CutawayServer communiquent, et quelles versions fonctionnent ensemble.
- [FAQ et dépannage](https://nothingsh.github.io/Cutaway/resources/faq), [Confidentialité et sécurité](https://nothingsh.github.io/Cutaway/resources/privacy), [Performances](https://nothingsh.github.io/Cutaway/resources/performance), [Notes de version](https://nothingsh.github.io/Cutaway/resources/releases), [Feuille de route](https://nothingsh.github.io/Cutaway/resources/roadmap).

<a id="development"></a>
## Développement

La façon de compiler et de vérifier CutawayServer, et la manière dont les modifications sont relues,
sont décrites dans [CONTRIBUTING.md](../../CONTRIBUTING.md). La page [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing)
explique comment les trois dépôts s’articulent.

<a id="license"></a>
## Licence

CutawayServer est distribué sous licence MIT ; voir [LICENSE](../../LICENSE).
`Sources/CutawayFlatBuffers` est le runtime Swift de FlatBuffers, sous Apache License 2.0 ; voir le
fichier [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) de ce répertoire.
