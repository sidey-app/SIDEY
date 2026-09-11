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

### macOS

macOS 26 이상 Apple Silicon Mac을 지원합니다. Intel Mac은 지원하지 않습니다.

Homebrew로 설치하려면 다음 명령을 실행합니다.

```sh
brew install --cask sidey-app/tap/sidey
```

직접 설치하려면 [SIDEY Releases](https://github.com/sidey-app/SIDEY/releases)에서 최신 `SIDEY-macOS-arm64-<version>.dmg`를 받은 뒤 `SIDEY.app`을 Applications 폴더로 옮깁니다. 새로 설치할 때는 ZIP이 아닌 DMG를 사용하세요.

현재 공개 버전은 `v1.2.1`(build 29)입니다. 직배포판의 실행 표시 이름은 `SIDEY-DIRECT`이며, 설치 파일 안의 `SIDEY.app`을 기존 앱과 같은 위치에 옮기면 됩니다. App Store판은 `SIDEY`로 표시됩니다.

### Windows

Windows 11 25H2 이상 x64 PC를 지원합니다.

[SIDEY Releases](https://github.com/sidey-app/SIDEY/releases)에서 `SIDEY-Windows-x64-v1.2.1-Setup.exe`를 받아 실행합니다.

Windows v1.0.3 또는 v1.0.4는 앱 안에서 업데이트 파일을 내려받지 못하므로, 최신 Setup EXE를 직접 받아 설치해야 합니다. 기존 정식 MSI에서 업데이트하면 설정과 로그인 정보는 유지됩니다.

## 최신 업데이트

### macOS · 2026년 9월 12일 · v1.2.1

- 상점 캐릭터 7종에 짧은 이야기가 담긴 소개를 추가했습니다.
- 캐릭터 소개를 구매 카드 안으로 옮겨 애착 물건 설명과 함께 읽기 편하게 정리했습니다.
- 나무의 우클릭 조작 안내를 미리보기 안에 배치했습니다.

### Windows · 2026년 9월 11일 · v1.2.1

- 앱과 설치 프로그램에서 한국어·영어·일본어·중국어 간체·중국어 번체·우크라이나어·러시아어를 지원합니다.
- 설치할 때 선택한 언어로 앱을 처음 열며 설정에서 바꾼 언어는 즉시 적용됩니다.
- 오버레이가 부드럽게 나타나며 Windows에서 애니메이션 효과를 끄면 전환 효과도 바로 표시됩니다.
- 그룹을 만들거나 초대 코드로 참여한 뒤 다음 화면으로 넘어가지 않던 문제를 수정했습니다.

## 추후 개선 및 개발 예정

- **Windows:** 기능 안정화
- 캐릭터 드래그 앤 드롭 기능

위 항목은 개발 예정 내용이며 일정과 제공 순서는 변경될 수 있습니다.

## Contributors

SIDEY를 함께 만들어 주신 분들께 감사드립니다.

<table>
  <tr>
    <td align="center" width="120">
      <a href="https://github.com/patulus">
        <img src="https://avatars.githubusercontent.com/u/7178737?v=4" width="80" height="80" alt="@patulus"><br>
        <sub><strong>@patulus</strong></sub>
      </a><br>
      <sub>Windows 개발</sub>
    </td>
  </tr>
</table>

## 라이선스

유료 캐릭터와 전용 투척물은 공개 저장소에서 열람할 수 있지만 오픈소스 에셋은 아닙니다.
복제·수정·재배포·상업 이용 조건은
[SIDEY Paid Asset License 1.0](assets/PAID_ASSET_LICENSE.md)을 확인해 주세요.
