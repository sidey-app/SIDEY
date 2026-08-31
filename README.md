```text
███████╗██╗██████╗ ███████╗██╗   ██╗
██╔════╝██║██╔══██╗██╔════╝╚██╗ ██╔╝
███████╗██║██║  ██║█████╗   ╚████╔╝
╚════██║██║██║  ██║██╔══╝    ╚██╔╝
███████║██║██████╔╝███████╗   ██║
╚══════╝╚═╝╚═════╝ ╚══════╝   ╚═╝
```

# SIDEY

화면 가장자리의 2D 픽셀 동물로 가까운 친구의 상태와 짧은 메시지를 보여주는 데스크톱 오버레이 메신저입니다.

[![macOS 26+](https://img.shields.io/badge/macOS_26%2B-Native-3182F6?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/sidey-app/SIDEY/releases)
![Apple Silicon](https://img.shields.io/badge/Architecture-Apple_Silicon_arm64-191F28?style=for-the-badge)
![Alpha](https://img.shields.io/badge/Status-Alpha-F04452?style=for-the-badge)

> 현재 공개 파일은 초기 테스트용 `alpha` 버전입니다. macOS용 빌드만 제공하며 UI와 동작이 바뀔 수 있습니다.

## SIDEY에서 할 수 있는 것

- 최대 5명의 가까운 친구와 초대 전용 비공개 그룹 만들기
- 친구별 픽셀 동물로 온라인·자리 비움·오프라인 상태 확인
- SIDEY 입력창의 타이핑 상태와 최대 200자의 짧은 메시지 공유
- 화면 가장자리 12개 프리셋 중 하나에 월드를 배치하고 평소 클릭은 뒤 앱으로 통과
- macOS 로그인 시 자동 실행 설정

## macOS 설치

지원 환경은 **macOS 26 이상, Apple Silicon Mac**입니다. Intel Mac은 이 네이티브 alpha에서 지원하지 않습니다.

1. [SIDEY Releases](https://github.com/sidey-app/SIDEY/releases)에서 최신 `SIDEY-macOS-arm64-<version>.zip`을 받습니다.
2. 다운로드한 ZIP의 압축을 풉니다.
3. `SIDEY.app`을 macOS의 `응용 프로그램` 폴더로 옮깁니다.
4. 처음 한 번은 Finder에서 `SIDEY.app`을 우클릭한 뒤 **열기**를 선택합니다.

### macOS가 실행을 막는 경우

이 alpha 빌드는 Apple Developer ID로 공증되지 않은 ad-hoc 서명 앱입니다. Apple이 확인한 개발자 앱처럼 바로 실행되지는 않습니다.

1. `SIDEY.app` 실행을 한 번 시도합니다.
2. **시스템 설정 → 개인정보 보호 및 보안**으로 이동합니다.
3. 보안 영역에서 SIDEY의 **확인 없이 열기**를 누릅니다.
4. 다시 표시되는 확인창에서 **열기**를 선택합니다.

반드시 이 저장소의 [공식 GitHub Releases](https://github.com/sidey-app/SIDEY/releases)에서 받은 파일만 실행하세요. 자세한 절차와 위험은 [Apple의 미확인 개발자 앱 안내](https://support.apple.com/en-ca/102445)를 확인할 수 있습니다.

파일 무결성은 Release에 함께 올라온 `.sha256` 파일과 다음 명령의 결과를 비교해 확인할 수 있습니다.

```sh
shasum -a 256 SIDEY-macOS-arm64-*.zip
```

## 기술 구성

- macOS 앱과 UI: Swift 6, SwiftUI, AppKit
- 2D 픽셀 월드: SpriteKit, 24×24 스프라이트의 nearest-neighbor 확대
- 사용자·그룹·메시지·실시간 상태: Supabase

메시지는 Postgres를 원본으로 저장하고, Presence는 접속 상태, Broadcast는 타이핑 같은 일시 이벤트에만 사용합니다.

## 개인정보와 현재 제한

SIDEY는 화면 내용, 실행 중인 앱 목록, 다른 앱에서 입력한 키, 마우스 좌표, 파일, 마이크 또는 카메라 데이터를 수집하지 않습니다. 전역 활동 신호는 마지막 시스템 입력 후 경과 시간과 화면 잠금 상태만 사용하며, 타이핑 표시는 SIDEY 입력창에서만 발생합니다.

현재 종단간 암호화(E2EE)는 제공하지 않습니다. 보안 화면, DRM 앱, 권한이 더 높은 앱 또는 모든 독점 전체화면 게임 위에 항상 표시된다고 보장하지도 않습니다.

Windows는 목표 플랫폼이지만 현재 픽셀 월드 vertical slice에는 포함되지 않습니다. `main`은 SwiftUI·AppKit·SpriteKit 기반 2D 네이티브 앱만 포함하며 과거 Godot·3D 소스와 배포 경로는 제거했습니다.

## 개발·빌드

macOS 26과 Xcode 26 이상이 필요합니다. 기본 macOS 내보내기는 네이티브 arm64 앱을 빌드하고 번들 메타데이터·로그인 항목·서명·아키텍처를 검증한 뒤 ZIP과 SHA-256 파일을 만듭니다.

```sh
./scripts/export_macos.sh
```

결과는 `build/macos-native/SIDEY.app`, `SIDEY-macOS-arm64.zip`, `SIDEY-macOS-arm64.zip.sha256`에 생성됩니다.

전체 네이티브 테스트는 다음처럼 실행합니다.

```sh
./scripts/macos/test_native.sh
```

테스트 DerivedData는 macOS의 `Documents` 폴더 파일 접근 지연과
`SIDEY.app` 중복 산출물을 피하도록 임시 디렉터리에 만들고 종료 시 삭제합니다.

로컬 백엔드 구성을 덮어쓸 때는 `SIDEY_SUPABASE_URL`과 `SIDEY_SUPABASE_PUBLISHABLE_KEY`를 반드시 함께 설정합니다. secret 또는 service-role 키는 클라이언트에 넣으면 안 됩니다.

버전 태그와 일치하는 검증된 Release ZIP을 만들려면 다음 명령을 사용합니다.

```sh
./scripts/package_macos_release.sh v0.2.0-alpha.1
```
