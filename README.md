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

현재 공개 버전은 `v1.0.10`(build 21)입니다.

### Windows

Windows 11 25H2 이상 x64 PC를 지원합니다.

[SIDEY Releases](https://github.com/sidey-app/SIDEY/releases)에서 `SIDEY-Windows-x64-v1.0.7-Setup.exe`를 받아 실행합니다.

Windows v1.0.3 또는 v1.0.4는 앱 안에서 업데이트 파일을 내려받지 못하므로, 최신 Setup EXE를 직접 받아 설치해야 합니다. 기존 정식 MSI에서 업데이트하면 설정과 로그인 정보는 유지됩니다.

Windows 버전은 현재 공인 코드 서명 전 정식판입니다. SmartScreen 경고가 표시되거나 일부 보안 설정에서 실행이 차단될 수 있습니다.

## 최신 업데이트

### macOS · 2026년 9월 5일 · v1.0.10

- 캐릭터 선택을 바로 적용하면서 작성 중인 닉네임은 유지합니다.
- 기본 말풍선과 캐릭터 기본 투척물의 장착 상태를 언제나 확인할 수 있습니다.
- 상점 정렬·보유 상품 숨기기와 그룹 나가기를 추가하고 그룹 연결 복구를 안정화했습니다.
- 최근 메시지와 기록은 생성 후 3일 동안 제공합니다.

### Windows · 2026년 9월 5일 · v1.0.7

- 최근 메시지와 기록의 조회·로컬 보관 기간을 생성 후 3일로 맞췄습니다.
- 한국어와 영어의 최근 기록 안내를 3일 기준으로 갱신했습니다.

## 추후 개선 및 개발 예정

- 새로운 말풍선 디자인 추가
- **Windows:** 기능 안정화
- 캐릭터 드래그 앤 드롭 기능
- 캐릭터 효과음

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
