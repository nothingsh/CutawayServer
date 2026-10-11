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

CutawayServer ist ein iOS-SDK, das Sie während der Entwicklung in Ihre App einbetten. Es ermöglicht
[**Cutaway**](https://github.com/nothingsh/Cutaway), einer macOS-App, die View-Hierarchie Ihrer laufenden App zu untersuchen: Cutaway
verbindet sich, und CutawayServer erfasst die angeforderten Layer, Bilder und Attribute und sendet
sie über das [Cutaway-Protokoll](https://github.com/nothingsh/CutawayProtocol) zurück.

Es funktioniert mit Apps, die im Simulator und auf per USB mit dem Mac verbundenen Geräten laufen.

<a id="features"></a>
## Funktionen

**Was Cutaway sieht**

- Der Layer-Baum jedes Fensters, mit Markierung der Root-Views von View-Controllern und der
  Member-Variablen, die die jeweiligen Layer oder Views halten.
- Für jeden Layer ein Bild des Layers allein und eines mit seinen Sublayern, gestreamt und
  abbrechbar.
- Die Attribute jedes Layers und jeder View, mit Markierung der bearbeitbaren; Bearbeitungen in
  Cutaway werden auf die laufende App angewendet.
- Die Auto-Layout-Constraints, die sich auf die jeweilige View beziehen, und ob jeder einzelne
  erfüllt ist.

**Für die Entwicklung gebaut**

- Integration in einer Zeile: `CutawayServer.start()`.
- Standardmäßig aus Release-Builds herauskompiliert.
- Lauscht nur auf der Loopback-Adresse und bedient jeweils einen Client.
- Reines Swift, keine Abhängigkeiten von Drittanbietern.

<a id="requirements"></a>
## Voraussetzungen

- iOS 13 oder neuer (iOS 15 oder neuer beim Bauen mit Xcode 27; siehe den Hinweis unten).
- Xcode 16.3 oder neuer, Swift 6.1 oder neuer.
- Swift Package Manager. Andere Paketmanager werden nicht unterstützt.

> [!NOTE]
> Jedes Modul wird mit einem Deployment-Target von iOS 13 gegen das iOS-SDK typgeprüft, sodass das
> Paket nichts Neueres ohne Verfügbarkeitsprüfung verwendet. Das Build-System von Xcode 27
> unterstützt jedoch keine Deployment-Targets unter iOS 15 und hebt das des Pakets auf 15.0 an;
> ein mit Xcode 27 erstellter Build läuft daher auf iOS 15 und neuer. Das Paket wurde nie unter
> iOS 13 oder 14 ausgeführt.

<a id="installation"></a>
## Installation

Wählen Sie in Xcode **File › Add Package Dependencies…**, geben Sie
`https://github.com/nothingsh/CutawayServer` ein und fügen Sie die Bibliothek `CutawayServer` dem
Target Ihrer App hinzu.

In einer `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.0.0")
]
```

und fügen Sie das Produkt `CutawayServer` den Abhängigkeiten Ihres Targets hinzu.

<a id="quick-start"></a>
## Schnellstart

Rufen Sie `start()` einmal beim Start der App auf.

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

`start()` kann von jedem Thread aus aufgerufen werden; ein erneuter Aufruf hat keine Wirkung. Der
Server beginnt zu lauschen, sobald die App aktiv wird. Führen Sie die App im Simulator oder auf einem
mit Ihrem Mac verbundenen Gerät aus und öffnen Sie dann Cutaway.

<a id="debug-and-release-builds"></a>
## Debug- und Release-Builds

Standardmäßig wird der Server nur in Builds kompiliert, die `DEBUG` definieren. In allen anderen
Builds ist `start()` eine leere Funktion, und das Produkt enthält keinen Code zum Lauschen.

Ob das Paket `DEBUG` sieht, hängt vom Namen der Build-Konfiguration der Host-App ab:

| Name der Host-Konfiguration | `DEBUG` im Paket definiert? |
|---|---|
| `Debug` sowie Namen, die `Debug` oder `Development` enthalten (zum Beispiel `DebugQA`) | Ja |
| `Release`, `Staging`, `QA` und jeder andere Name, auch wenn die Konfiguration von Debug kopiert wurde | Nein |

Um den Server in Konfigurationen der zweiten Art zu verwenden, aktivieren Sie das Paket-Trait
`ReleaseEnabled` (ein Trait ist eine Paketoption von SwiftPM):

- In einem SwiftPM-Host:

  ```swift
  .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.0.0", traits: ["ReleaseEnabled"])
  ```

- In einem Xcode-Projekt: Aktivieren Sie das Trait `ReleaseEnabled` für diese Paketabhängigkeit. Mit
  XcodeGen führen Sie es unter `packages.<name>.traits` auf; `Demo/release-enabled.yml` ist ein
  Beispiel.

> [!WARNING]
> Das Trait gilt für **jede** Konfiguration des Hosts, einschließlich derjenigen, die Sie im App Store
> einreichen. Sobald es aktiviert ist, liegt es beim Host, `start()` in ausgelieferten Builds nicht
> aufzurufen.

Ohne `DEBUG` und ohne das Trait enthält das Produkt von diesem Paket nichts außer dem Einstiegspunkt:
keinen Server, keine `Network`-Symbole und nichts vom Kodierungscode des Protokolls. Das Testskript
prüft dies mit `nm` am Release-Build der Demo-App.

`CutawayWire` und `CutawayFlatBuffers` sind Implementierungsdetails. Ein Host kann sie in einem
Debug-Build importieren, aber nichts darin ist öffentliche API oder durch die Versionsnummer
abgedeckt.

<a id="performance"></a>
## Performance

Das Untersuchen einer App sollte ihr Verhalten nicht verändern. CutawayServer ist darauf ausgelegt:

- **Der Main-Thread bleibt reaktionsfähig.** Nur die Arbeit, die UIKit und Core Animation berühren
  muss, läuft auf dem Main-Thread, ein Layer nach dem anderen, sodass die App zwischen den Layern
  Ereignisse verarbeitet. Komprimierung, Kodierung und Netzwerk laufen auf Hintergrund-Queues.
- **Der Speicher bleibt begrenzt, wenn Cutaway nicht hinterherkommt.** Sobald die noch nicht
  gesendeten Daten zusammen mit den auf Komprimierung wartenden Bildern 32 MiB überschreiten, beginnt
  der Server weder ein neues Bild noch die nächste Anfrage, bis der Client aufgeholt hat. Bei 64
  wartenden Anfragen hört er auf zu lesen.
- **Über eine lange Sitzung sammelt sich nichts an.** Layer und Views werden schwach gehalten, und
  alles, was einer Verbindung gehört, wird freigegeben, wenn sie geschlossen wird.
- **Ungültige Eingaben bringen die App nicht zum Absturz.** Fehlerhafte Daten und extreme Anfragen
  werden mit Fehlern beantwortet.

Die Testsuite erzwingt diese Grenzen bei jedem Lauf. Die gemessenen Werte stammen aus dem iOS
Simulator, Debug-Build:

| Szenario | Grenze | Gemessen |
|---|---|---|
| Ein Baum mit 10.000 Layern: Hierarchie, dann Bilder, Attribute und Constraints jedes Layers — längste einzelne Blockierung des Main-Threads¹ | 150 ms | 65–76 ms |
| Dasselbe, von der Anfrage bis zu den Details des letzten Layers | 30 s | etwa 6 s |
| Ein Client, der nie liest — Speicherwachstum der App, relativ zum Budget von 32 MiB | 1,5 × | 1,07 × |
| 200 Runden aus Hierarchie, Details, Bearbeitungen und Aktualisierungen, während sich die UI ändert — Speicherwachstum nach Runde 10 | 4 MiB | ≤ 0,06 MiB |
| 1.000 gleichzeitig gesendete Anfragen | in Reihenfolge beantwortet; der Speicher wächst nicht linear mit der Anzahl | bestanden |
| Über 100.000 mutierte, gekürzte und zusammengefügte Frames | kein Absturz | bestanden |

¹ Ohne das Rendern eines einzelnen Layers selbst.

<a id="behavior-on-the-device"></a>
## Verhalten auf dem Gerät

**Netzwerk**

- Es lauscht per TCP nur auf der Loopback-Adresse `127.0.0.1`, niemals auf anderen
  Netzwerkschnittstellen.
- Es nimmt den ersten freien Port von 48160 bis 48167. Sind alle belegt, lauscht es nicht und
  versucht es erneut, wenn die App das nächste Mal aktiv wird.
- Schlägt das Lauschen während der Ausführung fehl (zum Beispiel nachdem die App aus der Suspendierung
  zurückkehrt), lauscht es nach 0,5 Sekunden erneut, solange die App aktiv ist, und bevorzugt dabei
  den bisherigen Port. Weitere Fehlschläge verdoppeln das Intervall, bis zu 30 Sekunden.
- Verbindungen verwenden TCP-Keepalive: Eine Gegenstelle, die etwa 25 Sekunden lang nicht antwortet,
  wird getrennt, und der Server kann sofort den nächsten Client annehmen.

**Erfassung**

- Namen von Member-Variablen werden durch Vergleich von Adressen im Speicher des Besitzers ermittelt;
  es wird kein Getter aufgerufen. Referenzen, die von standardmäßigen (sicheren) `unowned`-Properties
  und von Collections wie Arrays gehalten werden, werden nicht gefunden; `weak`, `unowned(unsafe)`,
  `lazy` und Properties generischer Klassen werden gefunden.
- Bilder werden Layer für Layer gerendert. Beim Rendern eines Layers setzt es dessen Opacity
  vorübergehend auf 1 und macht ihn sichtbar, und für das Bild ohne Sublayer blendet es die Sublayer
  vorübergehend aus. All das wird im selben Abschnitt Main-Thread-Code wiederhergestellt, ohne
  Animation und ohne Layout.
- Das Lesen von Attributen löst kein Layout aus. Farben werden in sRGB gesendet, sodass
  Wide-Gamut-Farben abgeschnitten werden; dynamische Farben werden für die aktuelle Darstellung der
  View (hell oder dunkel) aufgelöst.

**Einschränkungen**

- Inhalte, die vom Render-Server des Systems zusammengesetzt werden, sind nicht in den Bildern
  enthalten: Blur-Effekte, Metal- und Video-Layer und Ähnliches.
- Jeweils ein Client; ein zweiter wird abgewiesen, solange der erste verbunden ist.

<a id="roadmap"></a>
## Roadmap

Dies sind die für die Zeit nach 1.0 geplanten Richtungen. Reihenfolge und Umfang können sich ändern.

- **Protokoll 1.0.** Das Cutaway-Protokoll einfrieren, sodass spätere Funktionen es nur noch
  erweitern.
- **Interaktionsanalyse.** Gesture-Recognizer und Target-Action-Paare anzeigen; Gesten aktivieren und
  deaktivieren; Methoden auf Objekten aufrufen.
- **Erweiterungs-API für Host-Apps.** Benutzerdefinierte Attribute, virtuelle Kindknoten und
  Konfiguration wie standardmäßig eingeklappte Klassen, Farbaliasse und von Bildern ausgeschlossene
  Views.
- **Große Hierarchien.** Ein schneller Modus, der nur sichtbare Layer erfasst; aufgeteilte
  Übertragung für sehr große Bilder.
- **Mehr Verbindungen und Plattformen.** WLAN-Verbindungen, authentifiziert und verschlüsselt; tvOS
  und visionOS.
- **SwiftUI.** Eine semantische Hierarchie der SwiftUI-Views neben dem Layer-Baum.

<a id="faq"></a>
## FAQ

**Landet CutawayServer in meinem App-Store-Build?**
Standardmäßig nicht. Sofern Sie das Trait `ReleaseEnabled` nicht aktivieren, enthält ein Build ohne
`DEBUG` nur ein leeres `start()`. Siehe [Debug- und Release-Builds](#debug-and-release-builds).

**Können sich andere Geräte im Netzwerk mit meiner App verbinden?**
Nein. Der Server lauscht nur auf `127.0.0.1`. Auf einem Gerät erreicht der Mac ihn über die
USB-Verbindung.

**Verändert die Inspektion meine App?**
Die Erfassung stellt alles, was sie berührt, wieder her, bevor der Main-Thread weitermacht, und das
Lesen von Attributen löst kein Layout aus. Nur Bearbeitungen, die Sie in Cutaway vornehmen, verändern
die App, zusammen mit dem Layout, das sie auslösen.

**Warum ist eine Blur-, Video- oder Metal-View in den Bildern leer?**
Diese Inhalte werden vom Render-Server des Systems außerhalb des App-Prozesses zusammengesetzt und
können daher nicht aus dem Layer-Baum gerendert werden.

<a id="development"></a>
## Entwicklung

Führen Sie nach dem Klonen einmal `./setup.sh` aus. Es checkt das Protokoll-Submodul aus, prüft, ob
Xcode vorhanden ist, installiert XcodeGen und jq mit Homebrew, falls sie fehlen, installiert die
versionsfixierten Werkzeuge in `.tools/`, richtet die Git-Hooks ein und generiert die
Xcode-Demoprojekte. Ein erneutes Ausführen schadet nicht.

| Aufgabe | Befehl |
|---|---|
| Alle Prüfungen ausführen (benötigt einen iPhone-Simulator) | `scripts/verify.sh` |
| Die Prüfungen ausführen, die keinen Simulator benötigen, wie es die CI tut | `scripts/verify.sh --mac-only` |
| Formatieren | `"$(scripts/get-swiftformat.sh)" .` |
| Linten | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| Einen laufenden Server prüfen | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- Der Pre-Commit-Hook formatiert die gestagten Swift-Dateien, staget das Ergebnis und prüft sie mit
  dem Linter; ein Commit mit Lint-Verstößen wird abgelehnt. Xcode zeigt die Befunde von SwiftLint
  nicht an, daher treten sie im Hook und in `scripts/verify.sh` zutage.
- `cutaway-probe` verbindet sich mit einem laufenden Server, führt den Handshake durch, ruft das Icon,
  die Hierarchie sowie die Bilder und Attribute jedes Layers ab und prüft jeden Frame, den es empfängt.
  Gegen die Demo-App prüft `--expect-demo` zusätzlich bekannte Inhalte, Farben und Attributwerte.
  `--slow-read 200` liest wie ein langsamer Client, um zu bestätigen, dass der Server den Stream unter
  Backpressure vollständig liefert.

<a id="license"></a>
## Lizenz

CutawayServer wird unter der MIT-Lizenz veröffentlicht; siehe [LICENSE](../../LICENSE).
`Sources/CutawayFlatBuffers` ist die Swift-Laufzeit von FlatBuffers unter der Apache License 2.0;
siehe die Datei [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) in diesem Verzeichnis.
