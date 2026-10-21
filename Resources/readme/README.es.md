<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-server-dark.svg">
    <img src="cutaway-server-light.svg" alt="CutawayServer — Capture iOS layers, images and attributes." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.1+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+-blue)](#requisitos)
[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)](#instalación)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](../../LICENSE)
[![verify](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml/badge.svg)](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **Español** | [Français](README.fr.md) | [Deutsch](README.de.md)

*Esto es una traducción; si difiere del [README en inglés](../../README.md), prevalece el README en inglés.*

CutawayServer es un SDK de iOS que integras en tu app durante el desarrollo. Permite que [**Cutaway**](https://github.com/nothingsh/Cutaway), una app de macOS, inspeccione la interfaz de tu app en ejecución: Cutaway se conecta, y CutawayServer captura las capas, imágenes y atributos que pide y los envía de vuelta mediante el [protocolo de Cutaway](https://github.com/nothingsh/CutawayProtocol). Funciona con apps que se ejecutan en el Simulador y en dispositivos conectados al Mac por USB.

<a id="features"></a>
## Características

- **Una línea para integrarlo.** Llama a `CutawayServer.start()` al arrancar, en UIKit o en SwiftUI. [Installation](https://nothingsh.github.io/Cutaway/integrate/)
- **Todo lo que muestra Cutaway.** El árbol de capas con los view controllers y las variables miembro marcados, una imagen de cada capa, atributos que se editan en vivo, restricciones de Auto Layout y la modificación de la apariencia y el tamaño del texto. [Guide](https://nothingsh.github.io/Cutaway/guide/getting-started)
- **Los detalles propios de tu app.** Añade atributos, nodos virtuales para lo que una vista dibuja por sí misma, nombres de colores, y vistas contraídas por defecto o excluidas de las imágenes. [Customizing what Cutaway shows](https://nothingsh.github.io/Cutaway/integrate/customizing)
- **Fuera de tus builds de release.** Se compila solo en los builds que definen `DEBUG`, salvo que actives el trait `ReleaseEnabled`. [Debug and Release builds](https://nothingsh.github.io/Cutaway/integrate/builds)
- **No estorba.** El hilo principal sigue respondiendo, la memoria está acotada y solo escucha en la dirección de loopback. [Behavior on the device](https://nothingsh.github.io/Cutaway/integrate/on-device)
- **Swift puro, sin dependencias de terceros.**

<a id="requirements"></a>
## Requisitos

- iOS 13 o posterior; un build hecho con Xcode 27 funciona en iOS 15 o posterior ([por qué](https://nothingsh.github.io/Cutaway/integrate/#requirements)).
- Xcode 16.3 o posterior, Swift 6.1 o posterior.
- Swift Package Manager. No se admiten otros gestores de paquetes.

<a id="installation"></a>
## Instalación

En Xcode, elige **File › Add Package Dependencies…**, introduce
`https://github.com/nothingsh/CutawayServer` y añade la biblioteca `CutawayServer` al target de tu app. En un `Package.swift`:

```swift
.package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
```

<a id="quick-start"></a>
## Inicio rápido

Llama a `start()` una vez al arrancar la app, por ejemplo en
`application(_:didFinishLaunchingWithOptions:)` o en el `init()` del `App` de SwiftUI:

```swift
import CutawayServer

CutawayServer.start()
```

Ejecuta la app en el Simulador o en un dispositivo conectado a tu Mac y abre Cutaway. La
[guía de instalación](https://nothingsh.github.io/Cutaway/integrate/) tiene el código para UIKit y SwiftUI y explica qué ocurre al arrancar.

<a id="documentation"></a>
## Documentación

Todo lo demás está en el [sitio web de Cutaway](https://nothingsh.github.io/Cutaway/) (en inglés):

- [Integrate](https://nothingsh.github.io/Cutaway/integrate/): instalación, [builds de Debug y Release](https://nothingsh.github.io/Cutaway/integrate/builds), [personalizar lo que muestra Cutaway](https://nothingsh.github.io/Cutaway/integrate/customizing), [comportamiento en el dispositivo](https://nothingsh.github.io/Cutaway/integrate/on-device) y [limitaciones](https://nothingsh.github.io/Cutaway/integrate/limitations).
- [Protocol](https://nothingsh.github.io/Cutaway/protocol/): cómo se comunican Cutaway y CutawayServer, y qué versiones funcionan juntas.
- [Preguntas frecuentes y solución de problemas](https://nothingsh.github.io/Cutaway/resources/faq), [Privacidad y seguridad](https://nothingsh.github.io/Cutaway/resources/privacy), [Rendimiento](https://nothingsh.github.io/Cutaway/resources/performance), [Notas de la versión](https://nothingsh.github.io/Cutaway/resources/releases), [Hoja de ruta](https://nothingsh.github.io/Cutaway/resources/roadmap).

<a id="development"></a>
## Desarrollo

Cómo compilar y comprobar CutawayServer, y cómo se revisan los cambios, está en
[CONTRIBUTING.md](../../CONTRIBUTING.md). La página [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) explica
cómo encajan los tres repositorios.

<a id="license"></a>
## Licencia

CutawayServer se publica bajo la licencia MIT; consulta [LICENSE](../../LICENSE).
`Sources/CutawayFlatBuffers` es el runtime de Swift de FlatBuffers, bajo la Apache License 2.0;
consulta el archivo [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) de ese directorio.
