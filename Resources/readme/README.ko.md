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

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | **한국어** | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*이 문서는 번역본입니다. 내용이 다를 경우 [영어 README](../../README.md)가 우선합니다.*

CutawayServer는 개발 중에 앱에 포함하는 iOS SDK입니다. macOS 앱인 [**Cutaway**](https://github.com/nothingsh/Cutaway)가 실행 중인 앱의 뷰 계층을 검사할 수 있게 해 줍니다. Cutaway가 연결하면 CutawayServer는 요청받은 레이어, 이미지, 속성을 캡처하여 [Cutaway 프로토콜](https://github.com/nothingsh/CutawayProtocol)로 돌려보냅니다.

시뮬레이터에서 실행 중인 앱과 USB로 Mac에 연결된 기기에서 실행 중인 앱에서 동작합니다.

<a id="features"></a>
## 기능

**Cutaway에서 볼 수 있는 것**

- 모든 윈도우의 레이어 트리. 뷰 컨트롤러의 루트 뷰와, 각 레이어나 뷰를 보유한 멤버 변수가 표시됩니다.
- 각 레이어에 대해 레이어 단독의 이미지와 서브레이어를 포함한 이미지. 스트리밍으로 전송되며 취소할 수 있습니다.
- 각 레이어와 뷰의 속성. 편집 가능한 속성이 표시되며, Cutaway에서 한 편집은 실행 중인 앱에 적용됩니다.
- 각 뷰를 참조하는 Auto Layout 제약 조건과, 각 제약 조건이 충족되는지 여부.

**개발을 위한 설계**

- 한 줄로 통합: `CutawayServer.start()`.
- 기본적으로 Release 빌드에는 컴파일되지 않습니다.
- 루프백 주소에서만 수신 대기하며, 한 번에 하나의 클라이언트만 처리합니다.
- 순수 Swift이며, 서드파티 의존성이 전혀 없습니다.

<a id="requirements"></a>
## 요구 사항

- iOS 13 이상 (Xcode 27로 빌드할 때는 iOS 15 이상. 아래 참고 사항 참조).
- Xcode 16.3 이상, Swift 6.1 이상.
- Swift Package Manager. 다른 패키지 매니저는 지원하지 않습니다.

> [!NOTE]
> 모든 모듈은 배포 대상을 iOS 13으로 하여 iOS SDK에 대해 타입 검사를 거치므로, 이 패키지는 availability 검사 없이 그보다 새로운 것을 사용하지 않습니다. 그러나 Xcode 27의 빌드 시스템은 iOS 15 미만의 배포 대상을 지원하지 않으며 패키지의 배포 대상을 15.0으로 올리므로, Xcode 27로 만든 빌드는 iOS 15 이상에서 실행됩니다. 이 패키지는 iOS 13이나 14에서 실행된 적이 한 번도 없습니다.

<a id="installation"></a>
## 설치

Xcode에서 **File › Add Package Dependencies…**를 선택하고 `https://github.com/nothingsh/CutawayServer`를 입력한 뒤, `CutawayServer` 라이브러리를 앱 타깃에 추가합니다.

`Package.swift`에서는 다음과 같이 작성하고,

```swift
dependencies: [
    .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.0.0")
]
```

타깃의 의존성에 프로덕트 `CutawayServer`를 추가합니다.

<a id="quick-start"></a>
## 빠른 시작

앱이 시작될 때 `start()`를 한 번 호출합니다.

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

`start()`는 어느 스레드에서든 호출할 수 있으며, 다시 호출해도 아무 효과가 없습니다. 서버는 앱이 활성화되면 수신 대기를 시작합니다. 시뮬레이터나 Mac에 연결된 기기에서 앱을 실행한 다음 Cutaway를 여세요.

<a id="debug-and-release-builds"></a>
## Debug 빌드와 Release 빌드

기본적으로 서버는 `DEBUG`를 정의하는 빌드에만 컴파일됩니다. 그 밖의 모든 빌드에서 `start()`는 빈 함수이며, 프로덕트에는 수신 대기 코드가 들어 있지 않습니다.

패키지에서 `DEBUG`가 보이는지는 호스트 앱의 빌드 구성 이름에 따라 달라집니다.

| 호스트 구성 이름 | 패키지에 `DEBUG`가 정의되는가? |
|---|---|
| `Debug`, 그리고 `Debug` 또는 `Development`가 포함된 이름 (예: `DebugQA`) | 예 |
| `Release`, `Staging`, `QA` 및 그 밖의 모든 이름 (구성을 Debug에서 복사했더라도) | 아니요 |

두 번째 종류의 구성에서 서버를 사용하려면 패키지 trait(패키지가 제공하는 선택적 기능 스위치) `ReleaseEnabled`를 활성화합니다.

- SwiftPM 호스트에서는:

  ```swift
  .package(url: "https://github.com/nothingsh/CutawayServer", from: "1.0.0", traits: ["ReleaseEnabled"])
  ```

- Xcode 프로젝트에서는: 이 패키지 의존성에서 trait `ReleaseEnabled`를 활성화합니다. XcodeGen을 사용한다면 `packages.<name>.traits` 아래에 나열합니다. `Demo/release-enabled.yml`이 예시입니다.

> [!WARNING]
> trait는 App Store에 제출하는 구성을 포함하여 호스트의 **모든** 구성에 적용됩니다. 활성화한 뒤에는 배포하는 빌드에서 `start()`를 호출하지 않도록 하는 것이 호스트의 책임입니다.

`DEBUG`도 trait도 없으면 프로덕트에는 이 패키지 중 진입점 외에는 아무것도 들어 있지 않습니다. 서버도, `Network` 심볼도, 프로토콜의 인코딩 코드도 없습니다. 테스트 스크립트는 데모 앱의 Release 빌드에 대해 `nm`으로 이를 확인합니다.

`CutawayWire`와 `CutawayFlatBuffers`는 구현 세부 사항입니다. 호스트는 Debug 빌드에서 이를 import할 수 있지만, 그 안의 어떤 것도 공개 API가 아니며 버전 번호의 보장 대상도 아닙니다.

<a id="performance"></a>
## 성능

앱을 검사한다고 해서 앱의 동작이 달라져서는 안 됩니다. CutawayServer는 이를 중심으로 설계되었습니다.

- **메인 스레드는 응답성을 유지합니다.** UIKit과 Core Animation을 건드려야 하는 작업만 메인 스레드에서 한 번에 레이어 하나씩 실행되므로, 앱은 레이어와 레이어 사이에 이벤트를 처리합니다. 압축, 인코딩, 네트워킹은 백그라운드 큐에서 실행됩니다.
- **Cutaway가 따라오지 못해도 메모리 사용량에는 한도가 있습니다.** 아직 전송하지 않은 데이터와 압축을 기다리는 이미지의 합이 32 MiB를 넘으면, 서버는 클라이언트가 따라잡을 때까지 새 이미지도, 다음 요청도 시작하지 않습니다. 대기 중인 요청이 64개가 되면 읽기를 멈춥니다.
- **긴 세션에서도 아무것도 쌓이지 않습니다.** 레이어와 뷰는 약한 참조로 보유되며, 연결이 소유한 모든 것은 연결이 닫힐 때 해제됩니다.
- **잘못된 입력으로 앱이 충돌하지 않습니다.** 형식이 잘못된 데이터와 극단적인 요청에는 오류로 응답합니다.

테스트 스위트는 실행할 때마다 이 한도를 검증합니다. 측정값은 iOS Simulator, Debug 빌드 기준입니다.

| 시나리오 | 한도 | 측정값 |
|---|---|---|
| 10,000개 레이어의 트리: 계층을 가져온 뒤 모든 레이어의 이미지, 속성, 제약 조건을 가져옴 — 메인 스레드를 한 번에 점유하는 가장 긴 시간¹ | 150 ms | 65–76 ms |
| 같은 작업의, 요청부터 마지막 레이어의 세부 정보까지 | 30 s | 약 6 s |
| 전혀 읽지 않는 클라이언트 — 앱 메모리 증가량 (32 MiB 예산 대비) | 1.5 × | 1.07 × |
| UI가 바뀌는 동안 계층, 세부 정보, 편집, 새로고침을 200회 반복 — 10회차 이후의 메모리 증가량 | 4 MiB | ≤ 0.06 MiB |
| 한꺼번에 보낸 1,000개의 요청 | 순서대로 응답함. 메모리가 요청 수에 비례해 늘지 않음 | 통과 |
| 변형, 절단, 이어 붙이기를 가한 100,000개 이상의 프레임 | 충돌 없음 | 통과 |

¹ 단일 레이어 자체의 렌더링은 포함하지 않습니다.

<a id="behavior-on-the-device"></a>
## 기기에서의 동작

**네트워킹**

- 루프백 주소 `127.0.0.1`에서만 TCP 수신 대기를 하며, 다른 네트워크 인터페이스에서는 절대 수신 대기하지 않습니다.
- 48160부터 48167까지 중 처음으로 비어 있는 포트를 사용합니다. 모두 사용 중이면 수신 대기하지 않고, 다음에 앱이 활성화될 때 다시 시도합니다.
- 실행 중에 수신 대기가 실패하면 (예를 들어 앱이 일시 중단에서 재개된 뒤), 앱이 활성 상태인 동안 0.5초 후에 이전에 사용하던 포트를 우선하여 다시 수신 대기합니다. 이후 실패할 때마다 간격은 두 배가 되며, 최대 30초까지 늘어납니다.
- 연결은 TCP keepalive를 사용합니다. 약 25초 동안 응답하지 않는 상대는 연결이 끊기며, 서버는 즉시 다음 클라이언트를 받아들일 수 있습니다.

**캡처**

- 멤버 변수 이름은 소유자의 메모리 안에서 주소를 비교하여 찾습니다. getter는 호출하지 않습니다. 기본(안전한) `unowned` 프로퍼티와 배열 같은 컬렉션이 보유한 참조는 찾지 못합니다. `weak`, `unowned(unsafe)`, `lazy`, 그리고 제네릭 클래스의 프로퍼티는 찾습니다.
- 이미지는 레이어 단위로 렌더링됩니다. 레이어를 렌더링하는 동안 해당 레이어의 opacity를 일시적으로 1로 설정하고 보이도록 하며, 서브레이어를 제외한 이미지에서는 서브레이어를 일시적으로 숨깁니다. 이 모든 것은 메인 스레드 코드의 같은 구간 안에서, 애니메이션이나 레이아웃 없이 원래대로 복원됩니다.
- 속성을 읽어도 레이아웃은 일어나지 않습니다. 색상은 sRGB로 전송되므로 넓은 색 영역의 색상은 잘립니다. 동적 색상은 뷰의 현재 외관(라이트 또는 다크)에 맞게 결정됩니다.

**제한 사항**

- 시스템의 렌더 서버가 합성하는 콘텐츠는 이미지에 포함되지 않습니다. 블러 효과, Metal 및 비디오 레이어 등이 이에 해당합니다.
- 한 번에 하나의 클라이언트만 지원합니다. 첫 번째 클라이언트가 연결되어 있는 동안 두 번째 클라이언트는 거부됩니다.

<a id="roadmap"></a>
## 로드맵

1.0 이후에 계획된 방향입니다. 순서와 범위는 바뀔 수 있습니다.

- **프로토콜 1.0.** Cutaway 프로토콜을 동결하여, 이후의 기능은 프로토콜에 추가만 하도록 합니다.
- **상호작용 분석.** 제스처 인식기와 target–action 쌍을 표시하고, 제스처를 활성화·비활성화하며, 객체의 메서드를 호출합니다.
- **호스트 앱을 위한 확장 API.** 사용자 정의 속성, 가상 자식 노드, 그리고 기본적으로 접혀 있는 클래스, 색상 별칭, 이미지에서 제외할 뷰 같은 설정.
- **대규모 계층.** 보이는 레이어만 캡처하는 빠른 모드. 매우 큰 이미지의 분할 전송.
- **더 많은 연결 방식과 플랫폼.** 인증과 암호화를 갖춘 Wi-Fi 연결. tvOS와 visionOS.
- **SwiftUI.** 레이어 트리와 나란히 SwiftUI 뷰의 의미적 계층을 제공합니다.

<a id="faq"></a>
## FAQ

**CutawayServer가 App Store 빌드에 포함되나요?**
기본적으로는 포함되지 않습니다. `ReleaseEnabled` trait를 활성화하지 않는 한, `DEBUG`가 없는 빌드에는 빈 `start()`만 들어 있습니다. [Debug 빌드와 Release 빌드](#debug-and-release-builds)를 참조하세요.

**네트워크의 다른 기기가 내 앱에 연결할 수 있나요?**
아니요. 서버는 `127.0.0.1`에서만 수신 대기합니다. 기기의 경우 Mac은 USB 연결을 통해 서버에 접근합니다.

**검사하면 앱이 바뀌나요?**
캡처는 메인 스레드가 다음 작업으로 넘어가기 전에 건드린 모든 것을 복원하며, 속성을 읽어도 레이아웃은 일어나지 않습니다. 앱을 바꾸는 것은 Cutaway에서 한 편집과, 그 편집으로 인해 발생하는 레이아웃뿐입니다.

**블러, 비디오, Metal 뷰가 이미지에서 비어 있는 이유는 무엇인가요?**
그 콘텐츠는 앱 프로세스 바깥에 있는 시스템의 렌더 서버가 합성하므로, 레이어 트리에서 렌더링할 수 없습니다.

<a id="development"></a>
## 개발

클론한 뒤 `./setup.sh`를 한 번 실행하세요. 프로토콜 서브모듈을 체크아웃하고, Xcode가 있는지 확인하고, XcodeGen과 jq가 없으면 Homebrew로 설치하고, 버전이 고정된 도구를 `.tools/`에 설치하고, git 훅을 설정하고, 데모 Xcode 프로젝트를 생성합니다. 다시 실행해도 문제가 없습니다.

| 작업 | 명령 |
|---|---|
| 모든 검사 실행 (iPhone 시뮬레이터 필요) | `scripts/verify.sh` |
| 시뮬레이터가 필요 없는 검사를 CI와 같이 실행 | `scripts/verify.sh --mac-only` |
| 포맷 | `"$(scripts/get-swiftformat.sh)" .` |
| 린트 | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer "$(scripts/get-swiftlint.sh)" lint --strict` |
| 실행 중인 서버 확인 | `swift run cutaway-probe --bundle-id dev.cutaway.demo --wait 30` |

- pre-commit 훅은 스테이징된 Swift 파일을 포맷하고, 그 결과를 스테이징한 뒤 린트합니다. 린트 위반이 있는 커밋은 거부됩니다. Xcode는 SwiftLint의 지적 사항을 보여 주지 않으므로, 지적 사항이 드러나는 곳은 이 훅과 `scripts/verify.sh`입니다.
- `cutaway-probe`는 실행 중인 서버에 연결하여 핸드셰이크를 수행하고, 아이콘, 계층, 모든 레이어의 이미지와 속성을 가져오며, 받은 모든 프레임을 검사합니다. 데모 앱을 대상으로 할 때는 `--expect-demo`가 알려진 콘텐츠, 색상, 속성 값도 확인합니다. `--slow-read 200`은 느린 클라이언트처럼 읽어서, 백프레셔 상황에서도 서버가 스트림을 끝까지 완료하는지 확인합니다.

<a id="license"></a>
## 라이선스

CutawayServer는 MIT 라이선스로 배포됩니다. [LICENSE](../../LICENSE)를 참조하세요.
`Sources/CutawayFlatBuffers`는 FlatBuffers Swift 런타임이며, Apache License 2.0을 따릅니다. 해당 디렉터리의 [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) 파일을 참조하세요.
