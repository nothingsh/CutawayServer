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

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | **Español** | [Français](README.fr.md) | [Deutsch](README.de.md)

*Esto es una traducción; si difiere del [README en inglés](../../README.md), prevalece el README en inglés.*

CutawayServer es un SDK de iOS que integras en tu app durante el desarrollo. Permite que [**Cutaway**](https://github.com/nothingsh/Cutaway),
una app de macOS, inspeccione la jerarquía de vistas de tu app en ejecución: Cutaway se conecta, y
CutawayServer captura las capas, las imágenes y los atributos que solicita y se los devuelve mediante
el [protocolo de Cutaway](https://github.com/nothingsh/CutawayProtocol).

Funciona con apps que se ejecutan en el Simulator y en dispositivos conectados al Mac por USB.

<a id="features"></a>
## Características

**Lo que ve Cutaway**

- El árbol de capas de cada ventana, con marcas en las vistas raíz de los view controllers y en las
  variables miembro que contienen cada capa o vista.
- Para cada capa, una imagen de la capa sola y otra con sus subcapas, transmitidas en streaming y
  cancelables.
- Los atributos de cada capa y vista, con los editables marcados; las ediciones hechas en Cutaway se
  aplican a la app en ejecución.
- Las restricciones de Auto Layout que hacen referencia a cada vista, y si cada una se cumple.

**Pensado para el desarrollo**

- Una sola línea para integrarlo: `CutawayServer.start()`.
- Excluido de la compilación en los builds Release por defecto.
- Escucha solo en la dirección de loopback y atiende a un cliente a la vez.
- Swift puro, sin dependencias de terceros.

<a id="requirements"></a>
## Requisitos

- iOS 13 o posterior (iOS 15 o posterior si se compila con Xcode 27; véase la nota más abajo).
- Xcode 16.3 o posterior, Swift 6.1 o posterior.
- Swift Package Manager. No se admiten otros gestores de paquetes.

> [!NOTE]
> Cada módulo se comprueba en tipos contra el SDK de iOS con un deployment target de iOS 13, de modo
> que el paquete no usa nada más reciente sin una comprobación de disponibilidad. Sin embargo, el
> sistema de build de Xcode 27 no admite deployment targets anteriores a iOS 15 y eleva el del paquete
> a 15.0, por lo que un build hecho con Xcode 27 se ejecuta en iOS 15 y posteriores. El paquete nunca
> se ha ejecutado en iOS 13 ni 14.

<a id="installation"></a>
## Instalación

En Xcode, elige **File › Add Package Dependencies…**, introduce
`https://github.com/nothingsh/CutawayServer` y añade la biblioteca `CutawayServer` al target de tu
app.

En un `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0")
]
```

y añade el producto `CutawayServer` a las dependencias de tu target.

<a id="quick-start"></a>
## Inicio rápido

Llama a `start()` una vez cuando se inicie la app.

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

`start()` se puede llamar desde cualquier hilo; llamarlo de nuevo no tiene ningún efecto. El servidor
empieza a escuchar en cuanto la app pasa a estar activa. Ejecuta la app en el Simulator o en un
dispositivo conectado a tu Mac y luego abre Cutaway.

<a id="debug-and-release-builds"></a>
## Builds Debug y Release

Por defecto, el servidor solo se compila en los builds que definen `DEBUG`. En cualquier otro build,
`start()` es una función vacía y el producto no contiene código de escucha.

Que el paquete vea `DEBUG` depende del nombre de la configuración de build de la app anfitriona:

| Nombre de la configuración del anfitrión | ¿`DEBUG` definido en el paquete? |
|---|---|
| `Debug`, y los nombres que contienen `Debug` o `Development` (por ejemplo, `DebugQA`) | Sí |
| `Release`, `Staging`, `QA` y cualquier otro nombre, aunque la configuración se haya copiado de Debug | No |

Para usar el servidor en configuraciones del segundo tipo, activa el trait (una opción de paquete de
SwiftPM) `ReleaseEnabled`:

- En un anfitrión SwiftPM:

  ```swift
  .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0", traits: ["ReleaseEnabled"])
  ```

- En un proyecto de Xcode: activa el trait `ReleaseEnabled` en esta dependencia de paquete. Con
  XcodeGen, inclúyelo en `packages.<name>.traits`; `Demo/release-enabled.yml` es un ejemplo.

> [!WARNING]
> El trait se aplica a **todas** las configuraciones del anfitrión, incluida la que envías a la App
> Store. Una vez activado, es responsabilidad del anfitrión no llamar a `start()` en los builds que
> distribuye.

Sin `DEBUG` y sin el trait, el producto no contiene nada de este paquete salvo el punto de entrada: ni
servidor, ni símbolos de `Network`, ni nada del código de codificación del protocolo. El script de
pruebas lo comprueba con `nm` en el build Release de la app de demostración.

`CutawayWire` y `CutawayFlatBuffers` son detalles de implementación. Un anfitrión puede importarlos en
un build Debug, pero nada de lo que contienen es API pública ni está cubierto por el número de
versión.

<a id="performance"></a>
## Rendimiento

Inspeccionar una app no debería cambiar su comportamiento. CutawayServer está diseñado en torno a esa
idea:

- **El hilo principal sigue respondiendo.** Solo el trabajo que tiene que tocar UIKit y Core Animation
  se ejecuta en el hilo principal, una capa cada vez, de modo que la app atiende eventos entre una capa
  y la siguiente. La compresión, la codificación y la red se ejecutan en colas en segundo plano.
- **La memoria se mantiene acotada cuando Cutaway se queda atrás.** En cuanto los datos aún no
  enviados más las imágenes pendientes de comprimir superan 32 MiB, el servidor no empieza ninguna
  imagen nueva ni la siguiente solicitud hasta que el cliente se pone al día. Con 64 solicitudes en
  espera, deja de leer.
- **Nada se acumula en una sesión larga.** Las capas y las vistas se retienen de forma débil, y todo lo
  que pertenece a una conexión se libera cuando esta se cierra.
- **Una entrada incorrecta no hace fallar la app.** Los datos malformados y las solicitudes extremas se
  responden con errores.

La batería de pruebas hace cumplir estos límites en cada ejecución. Los valores medidos proceden del
iOS Simulator, con un build Debug:

| Escenario | Límite | Medido |
|---|---|---|
| Un árbol de 10.000 capas: la jerarquía y, después, las imágenes, los atributos y las restricciones de cada capa — el bloque continuo más largo en el hilo principal¹ | 150 ms | 65–76 ms |
| Lo mismo, desde la solicitud hasta los detalles de la última capa | 30 s | unos 6 s |
| Un cliente que nunca lee — crecimiento de la memoria de la app, en relación con el presupuesto de 32 MiB | 1,5 × | 1,07 × |
| 200 rondas de jerarquía, detalles, ediciones y actualizaciones mientras la UI cambia — crecimiento de la memoria después de la ronda 10 | 4 MiB | ≤ 0,06 MiB |
| 1.000 solicitudes enviadas a la vez | se responden en orden; la memoria no crece linealmente con la cantidad | superada |
| Más de 100.000 tramas mutadas, truncadas y empalmadas | sin fallos | superada |

¹ Sin contar el renderizado de una sola capa en sí.

<a id="behavior-on-the-device"></a>
## Comportamiento en el dispositivo

**Red**

- Escucha por TCP solo en la dirección de loopback `127.0.0.1`, nunca en otras interfaces de red.
- Toma el primer puerto libre entre 48160 y 48167. Si todos están ocupados, no escucha, y lo vuelve a
  intentar la próxima vez que la app pasa a estar activa.
- Si la escucha falla durante la ejecución (por ejemplo, después de que la app se reanude tras haber
  estado suspendida), vuelve a escuchar al cabo de 0,5 segundos mientras la app esté activa, dando
  preferencia al puerto que tenía. Los fallos posteriores duplican el intervalo, hasta 30 segundos.
- Las conexiones usan TCP keepalive: un par que no responde durante unos 25 segundos se desconecta, y
  el servidor puede aceptar al siguiente cliente de inmediato.

**Captura**

- Los nombres de las variables miembro se encuentran comparando direcciones en la memoria del
  propietario; no se llama a ningún getter. No se encuentran las referencias que retienen las
  propiedades `unowned` por defecto (seguras) ni las colecciones como los arrays; sí se encuentran las
  `weak`, `unowned(unsafe)`, `lazy` y las propiedades de clases genéricas.
- Las imágenes se renderizan capa por capa. Mientras renderiza una capa, fija temporalmente su
  opacidad en 1 y la hace visible, y para la imagen sin subcapas oculta temporalmente las subcapas.
  Todo esto se restaura en el mismo tramo de código del hilo principal, sin animación y sin layout.
- Leer atributos no desencadena layout. Los colores se envían en sRGB, por lo que los colores de gama
  amplia se recortan; los colores dinámicos se resuelven según la apariencia actual de la vista (clara
  u oscura).

**Limitaciones**

- El contenido que compone el render server del sistema no aparece en las imágenes: efectos de
  desenfoque, capas de Metal y de vídeo, y similares.
- Un cliente a la vez; un segundo cliente se rechaza mientras el primero está conectado.

<a id="roadmap"></a>
## Hoja de ruta

Estas son las direcciones previstas después de la 1.0. El orden y el alcance pueden cambiar.

- **Análisis de interacción.** Mostrar los gesture recognizers y los pares target–action; activar y
  desactivar gestos; llamar a métodos de objetos.
- **API de extensión para apps anfitrionas.** Atributos personalizados, nodos hijos virtuales y
  configuración como clases contraídas por defecto, alias de colores y vistas excluidas de las
  imágenes.
- **Jerarquías grandes.** Un modo rápido que captura solo las capas visibles; transferencia por
  fragmentos para imágenes muy grandes.
- **Más conexiones y plataformas.** Conexiones por Wi-Fi, autenticadas y cifradas; tvOS y visionOS.
- **SwiftUI.** Una jerarquía semántica de las vistas de SwiftUI junto al árbol de capas.

<a id="faq"></a>
## Preguntas frecuentes

**¿Acabará CutawayServer en mi build para la App Store?**
No por defecto. A menos que actives el trait `ReleaseEnabled`, un build sin `DEBUG` solo contiene un
`start()` vacío. Consulta [Builds Debug y Release](#debug-and-release-builds).

**¿Pueden conectarse a mi app otros dispositivos de la red?**
No. El servidor escucha solo en `127.0.0.1`. En un dispositivo, el Mac llega a él a través de la
conexión USB.

**¿La inspección cambia mi app?**
La captura restaura todo lo que toca antes de que el hilo principal continúe, y leer atributos no
desencadena layout. Solo las ediciones que haces en Cutaway cambian la app, junto con el layout que
provocan.

**¿Por qué una vista de desenfoque, de vídeo o de Metal aparece vacía en las imágenes?**
Ese contenido lo compone el render server del sistema, fuera del proceso de la app, así que no se
puede renderizar a partir del árbol de capas.

<a id="development"></a>
## Desarrollo

Después de clonar, ejecuta `./setup.sh` una vez. Descarga el submódulo del protocolo, comprueba que
Xcode esté instalado, instala XcodeGen y jq con Homebrew si faltan, instala las herramientas con
versión fijada en `.tools/`, configura los git hooks y genera los proyectos de Xcode de demostración.
Volver a ejecutarlo no causa ningún daño.

| Tarea | Comando |
|---|---|
| Ejecutar todas las comprobaciones (requiere un simulador de iPhone) | `scripts/verify.sh` |
| Ejecutar las comprobaciones que no requieren simulador, como hace la CI | `scripts/verify.sh --mac-only` |
| Formatear | `"$(scripts/get-swiftformat.sh)" .` |
| Lint | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| Comprobar un servidor en ejecución | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- El hook de pre-commit formatea los archivos Swift preparados (staged), prepara el resultado y les
  pasa el linter; un commit con infracciones de lint se rechaza. Xcode no muestra los hallazgos de
  SwiftLint, así que es en el hook y en `scripts/verify.sh` donde aparecen.
- `cutaway-probe` se conecta a un servidor en ejecución, realiza el handshake, obtiene el icono, la
  jerarquía y las imágenes y los atributos de cada capa, y comprueba cada trama que recibe. Contra la
  app de demostración, `--expect-demo` comprueba además contenido, colores y valores de atributos
  conocidos. `--slow-read 200` lee como un cliente lento para confirmar que el servidor completa el
  flujo bajo contrapresión.

<a id="license"></a>
## Licencia

CutawayServer se publica bajo la licencia MIT; consulta [LICENSE](../../LICENSE).
`Sources/CutawayFlatBuffers` es el runtime de Swift de FlatBuffers, bajo la Apache License 2.0;
consulta el archivo [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) de ese directorio.
