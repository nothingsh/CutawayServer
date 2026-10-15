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

CutawayServer est un SDK iOS que vous intégrez à votre app pendant le développement. Il permet à
[**Cutaway**](https://github.com/nothingsh/Cutaway), une app macOS, d'inspecter la hiérarchie de vues de votre app en cours d'exécution :
Cutaway se connecte, et CutawayServer capture les calques, les images et les attributs qu'il demande,
puis les lui renvoie via le [protocole Cutaway](https://github.com/nothingsh/CutawayProtocol).

Il fonctionne avec les apps exécutées dans le Simulator et sur les appareils connectés au Mac en USB.

<a id="features"></a>
## Fonctionnalités

**Ce que voit Cutaway**

- L'arbre des calques de chaque fenêtre, avec les vues racines des view controllers et les variables
  membres qui détiennent chaque calque ou vue signalées.
- Pour chaque calque, une image du calque seul et une autre avec ses sous-calques, transmises en flux
  et annulables.
- Les attributs de chaque calque et vue, avec les attributs modifiables signalés ; les modifications
  faites dans Cutaway sont appliquées à l'app en cours d'exécution.
- Les contraintes Auto Layout qui font référence à chaque vue, et si chacune est satisfaite.

**Conçu pour le développement**

- Une seule ligne pour l'intégrer : `CutawayServer.start()`.
- Exclu de la compilation des builds Release par défaut.
- N'écoute que sur l'adresse de loopback et ne sert qu'un client à la fois.
- Swift pur, aucune dépendance tierce.

<a id="requirements"></a>
## Prérequis

- iOS 13 ou version ultérieure (iOS 15 ou version ultérieure en compilant avec Xcode 27 ; voir la note
  ci-dessous).
- Xcode 16.3 ou version ultérieure, Swift 6.1 ou version ultérieure.
- Swift Package Manager. Les autres gestionnaires de paquets ne sont pas pris en charge.

> [!NOTE]
> Chaque module est vérifié au typage contre le SDK iOS avec une deployment target iOS 13 ; le
> package n'utilise donc rien de plus récent sans vérification de disponibilité. Le système de build
> de Xcode 27, en revanche, ne prend pas en charge les deployment targets antérieures à iOS 15 et
> relève celle du package à 15.0 ; un build réalisé avec Xcode 27 s'exécute donc sur iOS 15 et
> versions ultérieures. Le package n'a jamais été exécuté sur iOS 13 ni 14.

<a id="installation"></a>
## Installation

Dans Xcode, choisissez **File › Add Package Dependencies…**, saisissez
`https://github.com/nothingsh/CutawayServer`, puis ajoutez la bibliothèque `CutawayServer` à la
target de votre app.

Dans un `Package.swift` :

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0")
]
```

puis ajoutez le produit `CutawayServer` aux dépendances de votre target.

<a id="quick-start"></a>
## Démarrage rapide

Appelez `start()` une fois, au lancement de l'app.

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

`start()` peut être appelée depuis n'importe quel thread ; l'appeler à nouveau n'a aucun effet. Le
serveur commence à écouter dès que l'app devient active. Lancez l'app dans le Simulator ou sur un
appareil connecté à votre Mac, puis ouvrez Cutaway.

<a id="debug-and-release-builds"></a>
## Builds Debug et Release

Par défaut, le serveur n'est compilé que dans les builds qui définissent `DEBUG`. Dans tout autre
build, `start()` est une fonction vide et le produit ne contient aucun code d'écoute.

Le fait que le package voie `DEBUG` ou non dépend du nom de la configuration de build de l'app
hôte :

| Nom de la configuration de l'hôte | `DEBUG` défini dans le package ? |
|---|---|
| `Debug`, et les noms qui contiennent `Debug` ou `Development` (par exemple `DebugQA`) | Oui |
| `Release`, `Staging`, `QA` et tout autre nom, même si la configuration a été copiée depuis Debug | Non |

Pour utiliser le serveur dans les configurations du second type, activez le trait (une option de
package SwiftPM) `ReleaseEnabled` :

- Dans un hôte SwiftPM :

  ```swift
  .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.1.0", traits: ["ReleaseEnabled"])
  ```

- Dans un projet Xcode : activez le trait `ReleaseEnabled` sur cette dépendance de package. Avec
  XcodeGen, indiquez-le sous `packages.<name>.traits` ; `Demo/release-enabled.yml` en donne un
  exemple.

> [!WARNING]
> Le trait s'applique à **toutes** les configurations de l'hôte, y compris celle que vous soumettez à
> l'App Store. Une fois qu'il est activé, il revient à l'hôte de ne pas appeler `start()` dans les
> builds qu'il distribue.

Sans `DEBUG` et sans le trait, le produit ne contient rien de ce package hormis le point d'entrée :
ni serveur, ni symboles `Network`, ni aucun code d'encodage du protocole. Le script de test le
vérifie avec `nm` sur le build Release de l'app de démonstration.

`CutawayWire` et `CutawayFlatBuffers` sont des détails d'implémentation. Un hôte peut les importer
dans un build Debug, mais rien de ce qu'ils contiennent ne relève de l'API publique ni n'est couvert
par le numéro de version.

<a id="performance"></a>
## Performances

Inspecter une app ne devrait pas changer son comportement. CutawayServer est conçu autour de ce
principe :

- **Le thread principal reste réactif.** Seul le travail qui doit toucher à UIKit et à Core Animation
  s'exécute sur le thread principal, un calque à la fois, de sorte que l'app traite les événements
  entre deux calques. La compression, l'encodage et le réseau s'exécutent sur des files d'arrière-plan.
- **La mémoire reste bornée quand Cutaway prend du retard.** Dès que les données pas encore envoyées
  plus les images en attente de compression dépassent 32 MiB, le serveur ne commence ni nouvelle image
  ni requête suivante tant que le client n'a pas rattrapé son retard. Avec 64 requêtes en attente, il
  cesse de lire.
- **Rien ne s'accumule au cours d'une longue session.** Les calques et les vues sont référencés
  faiblement, et tout ce qu'une connexion possède est libéré à sa fermeture.
- **Une entrée incorrecte ne fait pas planter l'app.** Les données malformées et les requêtes extrêmes
  reçoivent des erreurs en réponse.

La suite de tests impose ces limites à chaque exécution. Les valeurs mesurées proviennent de l'iOS
Simulator, en build Debug :

| Scénario | Limite | Mesuré |
|---|---|---|
| Un arbre de 10 000 calques : la hiérarchie, puis les images, les attributs et les contraintes de chaque calque — plus long blocage d'un seul tenant du thread principal¹ | 150 ms | 65–76 ms |
| La même chose, de la requête jusqu'aux détails du dernier calque | 30 s | environ 6 s |
| Un client qui ne lit jamais — croissance de la mémoire de l'app, rapportée au budget de 32 MiB | 1,5 × | 1,07 × |
| 200 tours de hiérarchie, détails, modifications et rafraîchissements pendant que l'UI change — croissance de la mémoire après le tour 10 | 4 MiB | ≤ 0,06 MiB |
| 1 000 requêtes envoyées d'un coup | réponses dans l'ordre ; la mémoire ne croît pas linéairement avec leur nombre | réussi |
| Plus de 100 000 trames mutées, tronquées et raboutées | aucun plantage | réussi |

¹ Sans compter le rendu d'un calque lui-même.

<a id="behavior-on-the-device"></a>
## Comportement sur l'appareil

**Réseau**

- Il écoute en TCP uniquement sur l'adresse de loopback `127.0.0.1`, jamais sur d'autres interfaces
  réseau.
- Il prend le premier port libre entre 48160 et 48167. Si tous sont occupés, il n'écoute pas et
  réessaie la prochaine fois que l'app devient active.
- Si l'écoute échoue en cours d'exécution (par exemple après la reprise de l'app depuis l'état
  suspendu), il se remet à écouter au bout de 0,5 seconde tant que l'app est active, en privilégiant
  le port qu'il avait. Chaque nouvel échec double l'intervalle, jusqu'à 30 secondes.
- Les connexions utilisent le TCP keepalive : un pair qui ne répond pas pendant environ 25 secondes
  est déconnecté, et le serveur peut accepter le client suivant immédiatement.

**Capture**

- Les noms des variables membres sont trouvés en comparant des adresses dans la mémoire du
  propriétaire ; aucun getter n'est appelé. Les références détenues par des propriétés `unowned` par
  défaut (sûres) et par des collections comme les tableaux ne sont pas trouvées ; celles détenues par
  des propriétés `weak`, `unowned(unsafe)`, `lazy` et par des propriétés de classes génériques le
  sont.
- Les images sont rendues calque par calque. Pendant le rendu d'un calque, il fixe temporairement
  l'opacité du calque à 1 et le rend visible, et, pour l'image sans sous-calques, masque
  temporairement les sous-calques. Tout cela est rétabli dans la même portion de code du thread
  principal, sans animation ni layout.
- La lecture des attributs ne déclenche pas de layout. Les couleurs sont envoyées en sRGB, si bien
  que les couleurs à gamut étendu sont écrêtées ; les couleurs dynamiques sont résolues pour
  l'apparence actuelle de la vue (claire ou sombre).

**Limites**

- Le contenu composité par le serveur de rendu du système n'apparaît pas dans les images : effets de
  flou, calques Metal et vidéo, etc.
- Un client à la fois ; un second client est refusé tant que le premier est connecté.

<a id="roadmap"></a>
## Feuille de route

Voici les orientations prévues après la 1.0. L'ordre et le périmètre peuvent changer.

- **Analyse des interactions.** Afficher les gesture recognizers et les paires target–action ; activer
  et désactiver des gestes ; appeler des méthodes sur des objets.
- **API d'extension pour les apps hôtes.** Attributs personnalisés, nœuds enfants virtuels, et
  configuration telle que des classes repliées par défaut, des alias de couleurs et des vues exclues
  des images.
- **Grandes hiérarchies.** Un mode rapide qui ne capture que les calques visibles ; un transfert par
  morceaux pour les très grandes images.
- **Plus de connexions et de plateformes.** Connexions Wi-Fi, authentifiées et chiffrées ; tvOS et
  visionOS.
- **SwiftUI.** Une hiérarchie sémantique des vues SwiftUI à côté de l'arbre des calques.

<a id="faq"></a>
## FAQ

**CutawayServer se retrouvera-t-il dans mon build App Store ?**
Pas par défaut. À moins que vous n'activiez le trait `ReleaseEnabled`, un build sans `DEBUG` ne
contient qu'une fonction `start()` vide. Voir [Builds Debug et Release](#debug-and-release-builds).

**D'autres appareils du réseau peuvent-ils se connecter à mon app ?**
Non. Le serveur n'écoute que sur `127.0.0.1`. Sur un appareil, le Mac l'atteint via la connexion USB.

**L'inspection modifie-t-elle mon app ?**
La capture rétablit tout ce qu'elle touche avant que le thread principal ne passe à autre chose, et la
lecture des attributs ne déclenche pas de layout. Seules les modifications que vous faites dans
Cutaway changent l'app, ainsi que le layout qu'elles provoquent.

**Pourquoi une vue de flou, vidéo ou Metal est-elle vide dans les images ?**
Ce contenu est composité par le serveur de rendu du système, hors du processus de l'app ; il ne peut
donc pas être rendu à partir de l'arbre des calques.

<a id="development"></a>
## Développement

Après le clonage, exécutez `./setup.sh` une fois. Il récupère le sous-module du protocole, vérifie la
présence de Xcode, installe XcodeGen et jq avec Homebrew s'ils manquent, installe les outils aux
versions épinglées dans `.tools/`, configure les hooks git et génère les projets Xcode de
démonstration. Le relancer est sans danger.

| Tâche | Commande |
|---|---|
| Exécuter toutes les vérifications (nécessite un simulateur iPhone) | `scripts/verify.sh` |
| Exécuter les vérifications qui ne nécessitent pas de simulateur, comme le fait la CI | `scripts/verify.sh --mac-only` |
| Formater | `"$(scripts/get-swiftformat.sh)" .` |
| Lint | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| Vérifier un serveur en cours d'exécution | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- Le hook pre-commit formate les fichiers Swift indexés (staged), indexe le résultat et les analyse
  avec le linter ; un commit comportant des violations de lint est refusé. Xcode n'affiche pas les
  résultats de SwiftLint ; c'est donc dans le hook et dans `scripts/verify.sh` qu'ils apparaissent.
- `cutaway-probe` se connecte à un serveur en cours d'exécution, effectue le handshake, récupère
  l'icône, la hiérarchie, ainsi que les images et les attributs de chaque calque, et vérifie chaque
  trame qu'il reçoit. Face à l'app de démonstration, `--expect-demo` vérifie en outre un contenu, des
  couleurs et des valeurs d'attributs connus. `--slow-read 200` lit comme un client lent pour
  confirmer que le serveur mène le flux à son terme sous contre-pression.

<a id="license"></a>
## Licence

CutawayServer est distribué sous licence MIT ; voir [LICENSE](../../LICENSE).
`Sources/CutawayFlatBuffers` est le runtime Swift de FlatBuffers, sous Apache License 2.0 ; voir le
fichier [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) de ce répertoire.
