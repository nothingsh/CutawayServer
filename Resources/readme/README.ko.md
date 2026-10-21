<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="cutaway-server-dark.svg">
    <img src="cutaway-server-light.svg" alt="CutawayServer — Capture iOS layers, images and attributes." width="850">
  </picture>
</p>

[![Swift](https://img.shields.io/badge/Swift-6.1+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-iOS%2013+-blue)](#요구-사항)
[![Swift Package Manager](https://img.shields.io/badge/SwiftPM-compatible-brightgreen)](#설치)
[![License](https://img.shields.io/badge/License-MIT-lightgrey)](../../LICENSE)
[![verify](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml/badge.svg)](https://github.com/nothingsh/CutawayServer/actions/workflows/verify.yml)

[English](../../README.md) | [简体中文](README.zh-Hans.md) | [繁體中文](README.zh-Hant.md) | [日本語](README.ja.md) | **한국어** | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

*이 문서는 번역본입니다. 내용이 다를 경우 [영어 README](../../README.md)가 우선합니다.*

CutawayServer는 개발 중인 앱에 포함하는 iOS SDK입니다. macOS 앱 [**Cutaway**](https://github.com/nothingsh/Cutaway)가 실행 중인 앱의 인터페이스를 검사할 수 있게 합니다. Cutaway가 연결하면 CutawayServer는 요청받은 레이어, 이미지, 속성을 수집하여 [Cutaway 프로토콜](https://github.com/nothingsh/CutawayProtocol)로 돌려보냅니다. 시뮬레이터에서 실행되는 앱과 USB로 Mac에 연결된 기기에서 실행되는 앱 모두에서 동작합니다.

<a id="features"></a>
## 기능

- **한 줄로 통합.** 실행 시 `CutawayServer.start()`를 호출하면 됩니다. UIKit과 SwiftUI 모두 지원합니다. [Installation](https://nothingsh.github.io/Cutaway/integrate/)
- **Cutaway가 보여 주는 모든 것.** 뷰 컨트롤러와 멤버 변수가 표시된 레이어 트리, 모든 레이어의 이미지, 실시간으로 편집할 수 있는 속성, Auto Layout 제약 조건, 외관과 텍스트 크기 재정의. [Guide](https://nothingsh.github.io/Cutaway/guide/getting-started)
- **앱만의 정보.** 속성 추가, 뷰가 직접 그리는 내용을 위한 가상 노드, 색상 이름 등록, 기본으로 접히거나 이미지에서 제외되는 뷰. [Customizing what Cutaway shows](https://nothingsh.github.io/Cutaway/integrate/customizing)
- **릴리스 빌드에는 들어가지 않습니다.** `ReleaseEnabled` 트레이트를 켜지 않는 한 `DEBUG`를 정의한 빌드에만 컴파일됩니다. [Debug and Release builds](https://nothingsh.github.io/Cutaway/integrate/builds)
- **앱을 방해하지 않습니다.** 메인 스레드는 응답성을 유지하고, 메모리 사용에는 상한이 있으며, 루프백 주소에서만 수신합니다. [Behavior on the device](https://nothingsh.github.io/Cutaway/integrate/on-device)
- **순수 Swift, 서드파티 의존성 없음.**

<a id="requirements"></a>
## 요구 사항

- iOS 13 이상. Xcode 27로 빌드한 경우 iOS 15 이상에서 실행됩니다([이유](https://nothingsh.github.io/Cutaway/integrate/#requirements)).
- Xcode 16.3 이상, Swift 6.1 이상.
- Swift Package Manager. 다른 패키지 관리자는 지원하지 않습니다.

<a id="installation"></a>
## 설치

Xcode에서 **File › Add Package Dependencies…**를 선택하고
`https://github.com/nothingsh/CutawayServer`를 입력한 다음, `CutawayServer` 라이브러리를 앱 타깃에 추가합니다. `Package.swift`에서는:

```swift
.package(url: "https://github.com/nothingsh/CutawayServer", from: "1.2.0")
```

<a id="quick-start"></a>
## 빠른 시작

앱이 실행될 때 `start()`를 한 번 호출합니다. 예를 들어 `application(_:didFinishLaunchingWithOptions:)`나 SwiftUI `App`의 `init()`에서:

```swift
import CutawayServer

CutawayServer.start()
```

시뮬레이터 또는 Mac에 연결된 기기에서 앱을 실행한 다음 Cutaway를 엽니다. [설치 가이드](https://nothingsh.github.io/Cutaway/integrate/)에 UIKit과 SwiftUI 코드, 실행 시 일어나는 일이 나와 있습니다.

<a id="documentation"></a>
## 문서

나머지 내용은 모두 [Cutaway 웹사이트](https://nothingsh.github.io/Cutaway/)(영어)에 있습니다:

- [Integrate](https://nothingsh.github.io/Cutaway/integrate/): 설치, [Debug 및 Release 빌드](https://nothingsh.github.io/Cutaway/integrate/builds), [Cutaway에 표시되는 내용 사용자화](https://nothingsh.github.io/Cutaway/integrate/customizing), [기기에서의 동작](https://nothingsh.github.io/Cutaway/integrate/on-device), [제한 사항](https://nothingsh.github.io/Cutaway/integrate/limitations).
- [Protocol](https://nothingsh.github.io/Cutaway/protocol/): Cutaway와 CutawayServer가 통신하는 방법과 함께 쓸 수 있는 버전.
- [FAQ 및 문제 해결](https://nothingsh.github.io/Cutaway/resources/faq), [개인정보 보호 및 보안](https://nothingsh.github.io/Cutaway/resources/privacy), [성능](https://nothingsh.github.io/Cutaway/resources/performance), [릴리스 노트](https://nothingsh.github.io/Cutaway/resources/releases), [로드맵](https://nothingsh.github.io/Cutaway/resources/roadmap).

<a id="development"></a>
## 개발

CutawayServer를 빌드하고 검사하는 방법과 변경 사항 리뷰 방식은 [CONTRIBUTING.md](../../CONTRIBUTING.md)에 있습니다. 웹사이트의 [Contributing](https://nothingsh.github.io/Cutaway/resources/contributing) 페이지는 세 저장소가 어떻게 맞물리는지 설명합니다.

<a id="license"></a>
## 라이선스

CutawayServer는 MIT 라이선스로 배포됩니다. [LICENSE](../../LICENSE)를 참조하세요.
`Sources/CutawayFlatBuffers`는 FlatBuffers Swift 런타임이며, Apache License 2.0을 따릅니다. 해당 디렉터리의 [LICENSE](../../Sources/CutawayFlatBuffers/LICENSE) 파일을 참조하세요.
