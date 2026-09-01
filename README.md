```text
███████╗██╗██████╗ ███████╗██╗   ██╗        /\_/\
██╔════╝██║██╔══██╗██╔════╝╚██╗ ██╔╝       ( •.• )
███████╗██║██║  ██║█████╗   ╚████╔╝         > ^ <
╚════██║██║██║  ██║██╔══╝    ╚██╔╝                    ʕ•ᴥ•ʔ
███████║██║██████╔╝███████╗   ██║                     /| |\
╚══════╝╚═╝╚═════╝ ╚══════╝   ╚═╝                      / \          ●  your friends, beside you.                                      
```

# SIDEY

화면 가장자리의 2D 픽셀 동물로 친구들과 대화하는 데스크톱 오버레이 메신저입니다.

공식 웹사이트: [sidey-app.github.io/SIDEY](https://sidey-app.github.io/SIDEY/)

![SIDEY 하단 오버레이 사용 예시 — 작업 화면 아래에서 상태와 짧은 메시지를 보여주는 픽셀 동물 친구들](docs/assets/sidey-overlay-preview.png)


[![macOS 26+](https://img.shields.io/badge/macOS_26%2B-Native-3182F6?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/sidey-app/SIDEY/releases)
![Apple Silicon](https://img.shields.io/badge/Architecture-Apple_Silicon_arm64-191F28?style=for-the-badge)
![Stable](https://img.shields.io/badge/Status-Stable-2EA043?style=for-the-badge)

> 현재 공개 버전은 `v1.0.3`(build 14)입니다.

Windows 11 25H2 x64 네이티브판은 별도 코드베이스로 개발 중입니다. 

## SIDEY에서 할 수 있는 것

- 최대 12명의 친구들과 초대 전용 비공개 그룹 만들기
- 친구별 픽셀 동물로 온라인·자리 비움·오프라인 상태 확인
- SIDEY 입력창의 타이핑 상태와 최대 200자의 짧은 메시지 공유
- 화면 가장자리 12개 프리셋 중 하나에 SIDEY를 배치하고 오버레이로 화면에 상시 띄움
- macOS 로그인 시 자동 실행 설정

## macOS 설치

지원 환경은 **macOS 26 이상, Apple Silicon(arm64) Mac**입니다. Intel Mac은 지원하지 않습니다. 공개 배포본은 Developer ID Application으로 서명하고 Apple 공증과 ticket staple을 마쳤습니다.

### Homebrew로 설치

```sh
brew install --cask sidey-app/tap/sidey
```

업데이트와 삭제는 각각 다음 명령을 사용합니다. 삭제해도 SIDEY 계정과 로컬 설정은 자동으로 지우지 않습니다.

```sh
brew upgrade --cask sidey-app/tap/sidey
brew uninstall --cask sidey-app/tap/sidey
```

### DMG로 직접 설치

1. [SIDEY Releases](https://github.com/sidey-app/SIDEY/releases)에서 최신 `SIDEY-macOS-arm64-<version>.dmg`를 받습니다.
2. DMG를 열고 `SIDEY.app`을 `Applications` 바로가기로 드래그합니다.
3. 응용 프로그램 폴더에서 `SIDEY.app`을 실행합니다.

ZIP은 Sparkle 자동 업데이트용 산출물입니다. 새로 설치할 때는 DMG를 사용하세요.

### 업데이트

Homebrew 설치본은 `brew upgrade --cask sidey-app/tap/sidey`로 갱신할 수 있습니다. Sparkle 내장 빌드는 메뉴바의 **업데이트 확인…**과 사용자 동의 기반 자동 확인도 제공합니다. Sparkle이 없던 과거 alpha는 최신 DMG로 한 번 수동 교체해야 합니다.

앱 번들만 바꾸므로 계정 세션, 그룹, 닉네임과 로컬 설정은 유지됩니다. 수동 교체 시 실행 중인 SIDEY는 먼저 종료해야 합니다. 로컬 개발본 `Sidey-dev`는 Sparkle을 시작하지 않으며 업데이트 확인 메뉴도 비활성화됩니다.

기존 alpha에서 처음 업데이트하면 SIDEY가 macOS 키체인 사용 목적을 먼저 안내할 수 있습니다. 이어지는 macOS 인증창에서 `항상 허용`을 선택하면 같은 실행이나 다음 실행에서 인증창이 반복되는 일을 줄일 수 있습니다. 인증을 거부하면 추가 키체인 요청을 보내지 않고 SIDEY를 종료합니다.

파일 무결성은 Release에 함께 올라온 `.sha256` 파일과 다음 명령의 결과를 비교해 확인할 수 있습니다.

```sh
shasum -a 256 SIDEY-macOS-arm64-*.dmg
```

## 기술 구성

- macOS 앱과 UI: Swift 6, SwiftUI, AppKit
- 2D 픽셀 월드: SpriteKit, 24×24 스프라이트의 nearest-neighbor 확대
- Windows 앱과 UI: C#/.NET 10 LTS, WinUI 3, Windows App SDK, Win32
- Windows 2D 픽셀 월드: 전용 Win32 오버레이 HWND. 첫 1캐릭터 local slice는 `UpdateLayeredWindow`로 창·DPI·클릭 통과·자원 안정성을 검증하고 최종 렌더러는 실측 뒤 결정
- 사용자·그룹·메시지·실시간 상태: Supabase

메시지는 Postgres를 원본으로 7일간 저장하고 자동 삭제합니다. Presence는 접속 상태, Broadcast는 타이핑 같은 일시 이벤트에만 사용합니다.

## 개인정보와 현재 제한

SIDEY는 화면 내용, 실행 중인 앱 목록, 다른 앱에서 입력한 키, 마우스 좌표, 파일, 마이크 또는 카메라 데이터를 수집하지 않습니다. 전역 활동 신호는 마지막 시스템 입력 후 경과 시간과 화면 잠금 상태만 사용하며, 타이핑 표시는 SIDEY 입력창에서만 발생합니다.

현재 종단간 암호화(E2EE)는 제공하지 않습니다. 보안 화면, DRM 앱, 권한이 더 높은 앱 또는 모든 독점 전체화면 게임 위에 항상 표시된다고 보장하지도 않습니다.

Windows판은 `windows/` 아래에서 macOS와 분리해 개발합니다. 두 클라이언트는 UI 런타임을 공유하지 않고 Postgres schema, Realtime payload, 제품 행동 테스트를 공통 계약으로 사용합니다. 과거 Godot·3D 소스와 배포 경로는 재도입하지 않습니다.

## 개발·빌드

### Windows

Windows 11 25H2 x64, Visual Studio 2026의 Desktop development with C++·Windows application development workload, .NET 10 SDK가 필요합니다. 현재 Windows 코드는 내부 햄스터 vertical slice 기반 단계이며 공개 alpha가 아닙니다.

```powershell
pwsh ./scripts/windows/test.ps1
```

Windows runner는 Core 테스트와 전체 WinUI 솔루션 빌드 뒤 self-contained x64 ZIP·SHA-256을 생성합니다. 보조 모니터 연결·제거와 mixed-DPI는 아직 실기 검증되지 않았습니다. 자세한 명령과 로컬 준비는 [`windows/README.md`](windows/README.md)를 참고하세요.

### macOS

macOS 26과 Xcode 26 이상이 필요합니다. 기본 macOS 내보내기는 네이티브 arm64 앱을 빌드하고 번들 메타데이터·로그인 항목·Sparkle 프레임워크·서명·아키텍처를 검증한 뒤 ZIP과 SHA-256 파일을 만듭니다.

```sh
./scripts/export_macos.sh
```

결과는 `build/macos-native/SIDEY.app`, `SIDEY-macOS-arm64.zip`, `SIDEY-macOS-arm64.zip.sha256`에 생성됩니다.

전체 네이티브 테스트는 다음처럼 실행합니다.

```sh
./scripts/macos/test_native.sh
```

최신 `Release` 구성의 ad-hoc 개발본을 검증해 `/Applications/Sidey-dev.app` 하나로 설치하고 실행하려면 다음 스크립트를 사용합니다. 표시명과 채널만 `Sidey-dev`·`development`이며, 기존 익명 계정·그룹·설정을 이어 쓰기 위해 bundle ID와 `com.sidey.desktop` Keychain service는 배포본과 같습니다.

```sh
./scripts/install_macos_dev.sh
```

테스트 DerivedData는 macOS의 `Documents` 폴더 파일 접근 지연과
`SIDEY.app` 중복 산출물을 피하도록 임시 디렉터리에 만들고 종료 시 삭제합니다.

로컬 백엔드 구성을 덮어쓸 때는 `SIDEY_SUPABASE_URL`과 `SIDEY_SUPABASE_PUBLISHABLE_KEY`를 반드시 함께 설정합니다. secret 또는 service-role 키는 클라이언트에 넣으면 안 됩니다.

버전 태그와 일치하는 검증된 Release ZIP을 만들려면 다음 명령을 사용합니다.

```sh
./scripts/package_macos_release.sh v1.0.3
```

Developer ID 활성화 뒤 실제 배포본은 인증서 이름, Team ID, `notarytool` Keychain profile을 지정해 같은 스크립트로 서명·공증·staple까지 끝냅니다. 신규 설치용 DMG에는 `SIDEY.app`과 `Applications` 바로가기가 들어가며, Sparkle 업데이트용 ZIP과 함께 각각 SHA-256 파일이 생성됩니다. 공증 profile을 지정하지 않은 ad-hoc 빌드는 ZIP만 만들고 배포용 DMG 생성을 거부합니다.

```sh
SIDEY_CODE_SIGN_IDENTITY="Developer ID Application: YOUR NAME (TEAMID)" \
SIDEY_DEVELOPMENT_TEAM="TEAMID" \
SIDEY_HARDENED_RUNTIME=YES \
SIDEY_NOTARYTOOL_PROFILE="sidey-notary" \
  ./scripts/package_macos_release.sh v1.0.3
```

Developer ID로 서명·공증하고 GitHub Release에 동일 ZIP을 업로드한 뒤 Sparkle appcast를 만들려면 다음 명령을 사용합니다. ad-hoc 빌드는 appcast 게시 도구가 기본적으로 거부합니다.

```sh
SIDEY_RELEASE_NOTES=/path/to/release-notes.md \
  ./scripts/macos/prepare_sparkle_appcast.sh \
  v1.0.3 \
  build/releases/v1.0.3/SIDEY-macOS-arm64-v1.0.3.zip
```
