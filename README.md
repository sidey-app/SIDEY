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

## 설치

<!-- sidey-release:macos:start -->
### macOS

macOS 26 이상 Apple Silicon Mac을 지원합니다. Intel Mac은 지원하지 않습니다.

Homebrew로 설치하려면 다음 명령을 실행합니다.

```sh
brew install --cask sidey-app/tap/sidey
```

직접 설치하려면 [SIDEY Releases](https://github.com/sidey-app/SIDEY/releases)에서 최신 `SIDEY-macOS-arm64-<version>.dmg`를 받은 뒤 `SIDEY.app`을 Applications 폴더로 옮깁니다. 새로 설치할 때는 ZIP이 아닌 DMG를 사용하세요.

현재 공개 버전은 `v1.2.1`(build 29)입니다. 직배포판의 실행 표시 이름은 `SIDEY-DIRECT`이며, 설치 파일 안의 `SIDEY.app`을 기존 앱과 같은 위치에 옮기면 됩니다. App Store판은 `SIDEY`로 표시됩니다.

<!-- sidey-release:macos:end -->

<!-- sidey-release:windows:start -->
### Windows

설치 대상은 Windows 10 1809 이상 x64 PC입니다.

[SIDEY Releases](https://github.com/sidey-app/SIDEY/releases)에서 `SIDEY-Windows-x64-v1.3.1-Setup.exe`를 받아 실행합니다.

기존 버전 위에 설치하면 설정과 로그인 정보가 유지됩니다.

공인 코드 서명 전 정식판으로, SmartScreen 경고가 표시되거나 일부 보안 설정에서 실행이 차단될 수 있습니다. Windows 앱에서는 구매를 지원하지 않으며, 유료 상품은 연결한 계정의 보유 내역을 확인한 뒤 사용할 수 있습니다.

<!-- sidey-release:windows:end -->

## 최신 업데이트

### macOS · 2026년 9월 12일 · v1.2.1

- 상점 캐릭터 7종에 짧은 이야기가 담긴 소개를 추가했습니다.
- 캐릭터 소개를 구매 카드 안으로 옮겨 애착 물건 설명과 함께 읽기 편하게 정리했습니다.
- 나무의 우클릭 조작 안내를 미리보기 안에 배치했습니다.

### Windows · 2026년 9월 15일 · v1.3.1

- Windows 10 1809 이상 x64로 실행 호환 범위를 넓혔습니다.
- 창 크기를 바꿀 때의 안정성과 프로필·상점의 배치, 로딩 표시를 개선했습니다.
- 프로필 갱신 중 캐릭터 선택이 바뀌는 문제와 투척물 표시 오류를 수정했습니다.
- 상점에서 연속으로 물건을 던질 때 동작이 끊기는 문제를 수정하고 내부 안정성을 개선했습니다.

[Windows v1.3.1 변경 사항](docs/releases/windows-v1.3.1.md)

## 추후 개선 및 개발 예정

- **Windows:** 기능 안정화
- 캐릭터 드래그 앤 드롭 기능

위 항목은 개발 예정 내용이며 일정과 제공 순서는 변경될 수 있습니다.

## Contributors

SIDEY를 함께 만들어 주신 분들께 감사드립니다.

<table>
  <tr>
    <td align="center" width="160">
      <a href="https://github.com/patulus">
        <img src="https://avatars.githubusercontent.com/u/7178737?v=4" width="80" height="80" alt="@patulus"><br>
        <sub><strong>@patulus</strong></sub>
      </a><br>
      <sub>Windows 개발</sub>
    </td>
    <td align="center" width="160">
      <a href="https://github.com/jungjiyu">
        <img src="https://avatars.githubusercontent.com/u/142137932?v=4" width="80" height="80" alt="@jungjiyu"><br>
        <sub><strong>@jungjiyu</strong></sub>
      </a><br>
      <sub>캐릭터 5종 에셋 제공</sub>
    </td>
  </tr>
</table>

## 라이선스

유료 캐릭터와 전용 투척물은 공개 저장소에서 열람할 수 있지만 오픈소스 에셋은 아닙니다.
복제·수정·재배포·상업 이용 조건은
[SIDEY Paid Asset License 1.0](assets/PAID_ASSET_LICENSE.md)을 확인해 주세요.
