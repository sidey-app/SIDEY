# SIDEY macOS bridge

macOS 13 이상에서만 빌드한다. 공식 `godot-cpp` 서브모듈을 사용하며 네이티브 바이너리는 커밋하지 않는다.

```sh
git submodule update --init
./scripts/build_macos_bridge.sh editor arm64
./scripts/build_macos_bridge.sh editor x86_64
./scripts/build_macos_bridge.sh template_release arm64
./scripts/build_macos_bridge.sh template_release x86_64
```

빌드 스크립트는 설치된 Godot에서 정확한 GDExtension API를 덤프한다. 같은 `4.7` 계열이라도
엔진과 `godot-cpp` 내장 API가 어긋나면 종료 시 크래시가 날 수 있으므로, 내장 JSON에 기대지 않는다.
Godot 경로가 기본 설치 위치와 다르면 `SIDEY_GODOT_BIN`으로 지정한다.

공식 Godot export template을 설치한 뒤 아래 명령으로 arm64/x86_64 릴리스 브리지를 빌드하고,
macOS 13 이상용 universal 앱을 ad-hoc 서명해 내보낼 수 있다.

```sh
./scripts/export_macos.sh
```

로컬 export 결과는 `build/macos/SIDEY.app`에 생성되며 Git에는 포함하지 않는다.

브리지가 제공하는 기능:

- Keychain 비밀 저장
- 마지막 시스템 입력 이후 경과 시간
- 화면 잠금 및 절전/복귀 이벤트
- Carbon hot key 기반 전역 단축키(Accessibility 권한 불필요)
- 모든 Space 및 일반 fullscreen용 보조 창 정책
- `SMAppService` 로그인 실행
- Dock 아이콘을 숨기는 accessory activation policy
- AppKit `ignoresMouseEvents` 클릭 통과 보강
- 활성 SIDEY 입력창의 Return을 IME 처리 전에 관찰하는 앱 내부 키 모니터

전역 단축키 기본값은 메시지 작성 `⌘⇧Space`, 상호작용 잠금 전환 `⌘⌥L`이다.
