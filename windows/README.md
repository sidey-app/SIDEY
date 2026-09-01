# SIDEY for Windows

Windows 11 25H2(build 26200)+ x64용 네이티브 클라이언트입니다. 첫 기능 빌드부터 `pixel_hamster`, `pixel_cat`, `pixel_puppy`, `pixel_rabbit`, `pixel_penguin` 5종을 같은 catalog 기반 renderer로 다룹니다. 햄스터 1종 검증은 별도 제품 구현이 아니라 같은 renderer의 Debug 제한 모드입니다.

아직 공개 alpha나 공개 Setup.exe가 없으며, Windows 실기·장시간 검증이 완료되지 않았습니다.

## 필수 환경

- Windows 11 25H2(build 26200) 이상 x64
- Visual Studio 2026
  - Windows application development
  - Desktop development with C++
  - Windows 11 SDK 10.0.26100 이상
- .NET 10 SDK

프로젝트는 Windows SDK 계약 `10.0.26100.0`을 대상으로 컴파일하고 실행 시 제품 최소 OS build 26200을 별도로 검사합니다. OS build와 SDK 계약 버전은 같은 값이 아닙니다.

## 구조와 소유권

- `Sidey.App`: 앱 수명, 서버 mutation, 방 전환, 트레이·창 coordinator와 WinUI UI
- `Sidey.Core`: 5종 catalog, 플랫폼 독립 모델·검증·Realtime 규칙·이동 시뮬레이션
- `Sidey.Infrastructure`: Supabase adapter, Windows Credential Manager, atomic preferences
- `Sidey.Overlay`: 단일 Win32 world HWND, 30 FPS 고정 step, 5종 premultiplied BGRA frame cache
- `Sidey.Platform.Windows`: 창·DPI·모니터·트레이·로그인 실행·시스템 유휴/잠금 감지

UI는 Supabase DTO, Credential Manager, HWND를 직접 소유하지 않습니다. `Sidey.Core`는 Windows·Supabase 패키지를 참조하지 않습니다. 종별 switch·HWND·renderer class는 추가하지 마세요. 새 내장 캐릭터는 asset, manifest, catalog entry로만 추가합니다.

## 빌드와 자동 검증

저장소 루트의 PowerShell에서 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
pwsh ./scripts/windows/test.ps1
dotnet build ./windows/SIDEY.Windows.slnx -c Release
```

일반 실행과 설치본은 macOS와 같은 production Supabase publishable 구성을 기본 사용하며, 같은 익명 세션을 복구하거나 신규 설치에서만 생성합니다. Google OAuth·PKCE·callback은 사용하지 않습니다. 로컬 개발에서만 아래 환경변수로 두 값을 함께 덮어쓸 수 있습니다. HTTPS 또는 localhost HTTP와 publishable key만 허용하며 service-role/secret key는 거부합니다.

```powershell
$env:SIDEY_SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co'
$env:SIDEY_SUPABASE_PUBLISHABLE_KEY = 'YOUR_PUBLISHABLE_KEY'
dotnet run --project ./windows/src/Sidey.App/Sidey.App.csproj --configuration Debug
```

두 환경변수가 없으면 production backend를 사용합니다. 서버 없는 5종 로컬 미리보기와 햄스터 제한 계측은 아래 Debug 검증 모드에서만 실행되며 Release에는 노출되지 않습니다.

## 햄스터 제한 실기 검증

Windows 실기에서만 다음 Debug 모드를 사용합니다.

```powershell
$env:SIDEY_WINDOWS_VALIDATION_MODE = '1'
Remove-Item Env:SIDEY_SUPABASE_URL -ErrorAction SilentlyContinue
Remove-Item Env:SIDEY_SUPABASE_PUBLISHABLE_KEY -ErrorAction SilentlyContinue
dotnet run --project ./windows/src/Sidey.App/Sidey.App.csproj --configuration Debug
```

종료하면 1초 간격 frame time, working set, GDI/USER handle 계측이 `%LOCALAPPDATA%\SIDEY\Validation\windows-renderer-*.json`으로 atomic export됩니다. `manualResult` 기본값은 `not_run`이며 구현자가 자동으로 통과 처리하지 않습니다.

다음을 30분 동안 사용자가 직접 확인합니다.

1. 메모장 위 스프라이트 밖 투명 영역의 클릭이 메모장으로 통과하는지 확인합니다.
2. 내 캐릭터 52×52 hotspot의 단일 클릭으로 400×56 composer가 열리고, 더블클릭으로 발 기준 pulse가 재생되며 composer가 열린 상태를 유지하는지 봅니다.
3. 한글 IME, `Enter` 전송, `Shift+Enter` 최대 3줄, `Esc`·외부 클릭 닫기, 전송 후 5초 유지, 실패 시 원문 복구를 확인합니다.
4. 가장자리 4개×길이 3개의 12개 프리셋에서 발 기준, 클릭 hotspot, 픽셀 선명도를 봅니다.
5. 100%, 125%, 150%, 200% DPI와 보조 모니터·mixed-DPI·모니터 연결 해제를 확인합니다.
6. 화면 잠금·해제, 절전·복귀, 장시간 유휴 후에도 렌더러와 Presence가 복귀하는지 봅니다.
7. JSON에 시간이 계속 늘어나는 sample이 남고, warm-up 후 working set 20MB 초과 증가·GDI/USER handle 지속 증가·100ms 이상 frame hang이 없는지 봅니다.

문제 보고에는 `test.ps1` 전체 출력, OS build, DPI/모니터, 영역 프리셋, 계측 JSON, 화면 녹화를 포함합니다. 별도로 12명 2시간·20노드 30분 장시간 테스트와 macOS↔Windows 양방향 계약 검증도 사용자가 수행하고 결과를 제공해야 합니다.

## Setup.exe 후보 생성

`PublishSingleFile`은 사용하지 않습니다. self-contained WinUI publish 폴더 전체를 사용자별 MSI에 넣고, WiX Toolset `6.0.2` Burn이 MSI와 payload를 내장한 오프라인 Setup.exe를 만듭니다.

`package.ps1`의 숫자 4부 `BundleVersion`은 앞 세 자리를 표시 SemVer와 맞추고, 네 번째 값을 prerelease 순번으로 사용합니다. 이 값에서 MSI의 숫자 build를 파생하므로 다음 alpha는 반드시 더 큰 값을 써야 합니다(`alpha.1` → `0.3.0.1`, `alpha.2` → `0.3.0.2`; stable 예약값은 `999`). Burn과 MSI가 함께 downgrade를 차단하려면 이 순서를 거꾸로 재사용하면 안 됩니다.

```powershell
dotnet publish ./windows/src/Sidey.App/Sidey.App.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=false -p:Version=0.3.0-alpha.1 `
  -o ./build/windows/publish

pwsh ./scripts/windows/package.ps1 `
  -PublishDir ./build/windows/publish `
  -OutDir ./build/windows/artifacts
```

공개 후보는 다음 두 파일입니다.

- `SIDEY-Windows-x64-v0.3.0-alpha.1-Setup.exe`
- `SIDEY-Windows-x64-v0.3.0-alpha.1-Setup.exe.sha256`

내부 MSI는 CI 검증에만 사용합니다. ZIP·직접 MSI·MSIX는 공개하지 않습니다. Setup은 관리자 권한 없이 `%LOCALAPPDATA%\Programs\SIDEY`에 설치하고 시작 메뉴만 추가합니다. 바탕화면 바로가기와 설치 중 로그인 자동 실행은 만들지 않습니다.

GitHub pre-release에 Setup과 `.sha256`을 올린 뒤에는 로컬 CI 후보와 Release에서 다시 받은 바이트가 같은지 확인합니다. 이 명령이 성공하기 전에는 웹사이트 Windows CTA나 업데이트 manifest를 활성화하면 안 됩니다.

```powershell
./scripts/windows/verify-release.ps1 `
  -Version 0.3.0-alpha.1 `
  -CandidateSetup ./build/windows/artifacts/SIDEY-Windows-x64-v0.3.0-alpha.1-Setup.exe
```

clean install, 시작 메뉴·성공 화면 실행, repair, 실행 중 major upgrade, downgrade 차단, uninstall/reinstall 후 설정·Credential Manager 세션 보존을 Windows에서 검증하기 전에는 공개 준비 완료로 표시하지 않습니다.

## 미서명 alpha 경고와 SHA-256

첫 공개 alpha Setup.exe는 코드 서명이 없습니다. SmartScreen 경고가 버전마다 반복될 수 있고 Smart App Control 정책을 포함한 일부 PC에서는 실행 자체가 차단될 수 있습니다. 우회를 보장하지 않으며, 조직 정책이 차단하면 관리자 결정을 따릅니다.

Release의 `.sha256`과 다음 결과를 파일명·hash 모두 비교합니다.

```powershell
Get-FileHash .\SIDEY-Windows-x64-v0.3.0-alpha.1-Setup.exe -Algorithm SHA256
```

실제 GitHub Release에 파일을 올리고 다시 내려받은 Setup.exe의 hash가 후보와 일치하기 전에는 웹사이트 Windows 다운로드 버튼과 업데이트 manifest를 활성화하지 않습니다. 앱은 새 버전을 확인하면 공식 GitHub Release 페이지만 열고, Setup.exe를 직접 다운로드하거나 실행하지 않습니다.

## 현재 승격 제외 항목

- Windows 30분 햄스터 제한 실기 계측 결과 미제공
- 12명 2시간·20노드 30분 장시간 실기 결과 미제공
- macOS↔Windows 메시지·Presence·typing·pulse·그룹 관리 양방향 실서버 검증 미완료
- clean install·repair·upgrade·downgrade·uninstall/reinstall Windows 실기 미완료
- 첫 alpha 코드 서명, MSIX, ARM64, 자동 설치 업데이트 미제공
