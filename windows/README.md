# SIDEY for Windows

Windows 11 25H2(build 26200)+ x64용 네이티브 클라이언트입니다. 첫 기능 빌드부터 `pixel_hamster`, `pixel_cat`, `pixel_puppy`, `pixel_rabbit`, `pixel_penguin` 5종을 같은 catalog 기반 renderer로 다룹니다. 햄스터 1종 검증은 별도 제품 구현이 아니라 같은 renderer의 Debug 제한 모드입니다.

Windows 실기·장시간 검증 전 테스트용 pre-release이며 공개 준비 완료판이 아닙니다.

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

GitHub Actions의 일반 PR·`main` 푸시는 복원, 포맷 검사, Release 빌드와 테스트만 수행합니다. 설치 후보 생성은 수동 실행 또는 현재 프로젝트 버전과 일치하는 `windows-v*` 태그에서만 수행하며, 수동 실행은 `publish_release`를 선택한 경우에만 GitHub pre-release까지 게시합니다. Setup·SHA-256·공개 인증서·테스트 MSI는 보관 기간 7일의 단일 CI 아티팩트로 묶습니다.

일반 실행과 설치본은 macOS와 같은 production Supabase publishable 구성을 기본 사용하며, 같은 익명 세션을 복구하거나 신규 설치에서만 생성합니다. Google OAuth·PKCE·callback은 사용하지 않습니다. 로컬 개발에서만 아래 환경변수로 두 값을 함께 덮어쓸 수 있습니다. HTTPS 또는 localhost HTTP와 publishable key만 허용하며 service-role/secret key는 거부합니다.

```powershell
$env:SIDEY_SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co'
$env:SIDEY_SUPABASE_PUBLISHABLE_KEY = 'YOUR_PUBLISHABLE_KEY'
dotnet run --project ./windows/src/Sidey.App/Sidey.App.csproj --configuration Debug
```

두 환경변수가 없으면 production backend를 사용합니다. 서버 없는 5종 로컬 미리보기와 햄스터 제한 계측은 아래 Debug 검증 모드에서만 실행되며 Release에는 노출되지 않습니다.

완료된 온보딩을 자격증명이나 환경설정 초기화 없이 다시 확인하려면 Debug 전용 미리 보기 인자를 사용합니다. 랜딩부터 프로필·그룹·완료 단계를 모두 진행하지만 프로필과 그룹 변경은 서버에 저장하지 않습니다. Release 빌드에서는 이 인자를 무시합니다.

```powershell
dotnet run --project ./windows/src/Sidey.App/Sidey.App.csproj --configuration Debug -- --onboarding-preview
```

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

unpackaged·multi-file self-contained WinUI 앱을 `PublishSingleFile=false`로 게시합니다. 루트의 작은 `SIDEY.exe` 런처가 모든 인수를 `Runtime\SIDEY.Host.exe`로 전달하며, 앱 본체와 .NET·Windows App SDK 런타임은 `Runtime` 안에 격리합니다. 사용자 콘텐츠는 `Assets`, SIDEY 자체 JSON 번역 리소스는 `Langs`에 둡니다. 별도 런타임 설치는 필요하지 않으며 모든 파일은 하나의 검증된 버전 단위로 함께 설치·업데이트합니다. 자세한 기준은 [`DEPLOYMENT_LAYOUT.md`](DEPLOYMENT_LAYOUT.md)에 있습니다. WiX Toolset `6.0.2` Burn은 게시 트리 전체를 포함하는 머신 단위 MSI와 오프라인 Setup.exe를 만듭니다.

`package.ps1`의 숫자 4부 `BundleVersion`은 앞 세 자리를 표시 SemVer와 맞추고, 네 번째 값을 prerelease 순번으로 사용합니다. 이 값에서 MSI의 숫자 build를 파생하므로 다음 alpha는 반드시 더 큰 값을 써야 합니다(`alpha.1` → `0.3.0.1`, `alpha.2` → `0.3.0.2`; stable 예약값은 `999`). Burn과 MSI가 함께 downgrade를 차단하려면 이 순서를 거꾸로 재사용하면 안 됩니다.

```powershell
dotnet publish ./windows/src/Sidey.App/Sidey.App.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=false -p:Version=0.3.0-alpha.7 `
  -o ./build/windows/publish

pwsh ./scripts/windows/package.ps1 `
  -PublishDir ./build/windows/publish `
  -OutDir ./build/windows/artifacts
```

공개 후보는 다음 두 파일입니다.

- `SIDEY-Windows-x64-v0.3.0-alpha.7-Setup.exe`
- `SIDEY-Windows-x64-v0.3.0-alpha.7-Setup.exe.sha256`
- `SIDEY-SelfSigned-CodeSigning.cer` (테스터가 서명 지문을 확인할 때 사용하는 공개 인증서)
- `SIDEY-Windows-x64-v0.3.0-alpha.7-Test.msi`와 `.sha256` (CI 아티팩트 및 직접 MSI 테스트 전용)

테스트 MSI는 CI 검증과 직접 설치 테스트에만 사용하고 GitHub Release에는 게시하지 않습니다. ZIP·직접 MSI·MSIX는 공개하지 않습니다. Setup은 관리자 승인 뒤 `C:\Program Files\SIDEY`에 설치하고 공용 시작 메뉴만 추가합니다. 바탕화면 바로가기와 설치 중 로그인 자동 실행은 만들지 않습니다.

기존 v0.3.0-alpha.1은 사용자별 MSI라 머신 단위 alpha.7로 자동 major upgrade할 수 없습니다. 새 Setup이 기존 설치를 감지하면 중단하므로 Windows 설정에서 alpha.1을 먼저 제거한 뒤 다시 설치해야 합니다. `%LOCALAPPDATA%\SIDEY` 설정과 Credential Manager 세션은 제거하지 않습니다.

GitHub pre-release에 Setup과 `.sha256`을 올린 뒤에는 로컬 CI 후보와 Release에서 다시 받은 바이트가 같은지 확인합니다. 이 명령이 성공하기 전에는 웹사이트 Windows CTA나 업데이트 manifest를 활성화하면 안 됩니다.

Windows와 macOS는 같은 GitHub 저장소를 사용하지만 릴리스 주기는 독립적입니다. Windows 릴리스 태그는 `windows-v<version>`, macOS 릴리스 태그는 기존 `v<version>` 형식을 사용합니다. Windows 앱은 Sparkle appcast나 저장소 전체의 `latest` Release를 읽지 않고 Pages의 `website/windows-latest.json`만 확인합니다. 개발 빌드의 이전 경로인 `website/windows/update.json`도 같은 내용으로 유지합니다. macOS Release가 먼저 게시되어도 Windows 업데이트로 오인하지 않습니다.

새 Windows 버전을 알릴 때 두 manifest에는 검증된 Setup.exe의 정확한 GitHub Release `installer_url`과 64자리 `sha256`도 함께 기록합니다. 앱은 URL이 해당 `windows-v<version>` Release의 정해진 Setup 파일인지 확인하고, 다운로드한 바이트의 SHA-256이 일치할 때만 설치 프로그램을 실행합니다. 현재 버전과 같거나 낮은 manifest에서는 두 필드를 `null`로 둘 수 있습니다.

```powershell
./scripts/windows/verify-release.ps1 `
  -Version 0.3.0-alpha.7 `
  -CandidateSetup ./build/windows/artifacts/SIDEY-Windows-x64-v0.3.0-alpha.7-Setup.exe
```

clean install, 시작 메뉴·성공 화면 실행, repair, 실행 중 major upgrade, downgrade 차단, uninstall/reinstall 후 설정·Credential Manager 세션 보존을 Windows에서 검증하기 전에는 공개 준비 완료로 표시하지 않습니다.

시작 직후 종료되거나 오류창이 나타나면 `%LOCALAPPDATA%\SIDEY\Logs\startup.log`를 확인합니다. 이 로그에는 시작 단계와 예외 유형·HRESULT·stack만 남기며 token·메시지 본문·초대 코드는 기록하지 않습니다.

## SIDEY 자체 서명과 SHA-256

배포 파이프라인은 루트 `SIDEY.exe`, `Runtime\SIDEY.Host.exe`, `SIDEY.Host.dll`, 모든 `Sidey.*.dll`, 내부 MSI와 최종 Setup.exe를 `CN=SIDEY` 자체 서명 인증서 하나로 Authenticode 서명합니다. Microsoft·.NET·Windows App SDK 런타임 파일은 공급자의 기존 서명을 그대로 유지합니다. 빌드 중 같은 인증서를 전달하기 위해 만든 임시 PFX는 성공·실패와 관계없이 패키징 종료 시 삭제하며, 개인 키가 없는 공개 인증서만 `SIDEY-SelfSigned-CodeSigning.cer`로 남깁니다.

자체 서명은 파일의 서명 주체와 배포 중 변조 여부를 확인하는 용도이며 Windows의 공인 신뢰나 SmartScreen 평판을 만들지는 않습니다. 따라서 새 PC에서는 `알 수 없는 게시자` 또는 SmartScreen 경고가 나타날 수 있고, Smart App Control이나 조직 정책에 따라 실행이 차단될 수도 있습니다. 우회를 보장하지 않으며 조직 정책이 차단하면 관리자 결정을 따릅니다.

Release의 `.sha256`과 다음 결과를 파일명·hash 모두 비교합니다.

```powershell
Get-FileHash .\SIDEY-Windows-x64-v0.3.0-alpha.7-Setup.exe -Algorithm SHA256
```

실제 GitHub Release에 파일을 올리고 다시 내려받은 Setup.exe의 hash가 후보와 일치하기 전에는 웹사이트 Windows 다운로드 버튼과 업데이트 manifest를 활성화하지 않습니다. 앱은 사용자가 새 버전 다운로드를 승인하면 정해진 GitHub Release Setup.exe만 내려받고, manifest의 SHA-256과 일치할 때에만 설치 프로그램을 실행합니다.

## 현재 승격 제외 항목

- Windows 30분 햄스터 제한 실기 계측 결과 미제공
- 12명 2시간·20노드 30분 장시간 실기 결과 미제공
- macOS↔Windows 메시지·Presence·typing·pulse·그룹 관리 양방향 실서버 검증 미완료
- clean install·repair·upgrade·downgrade·uninstall/reinstall Windows 실기 미완료
- 첫 alpha 코드 서명, MSIX, ARM64, 자동 설치 업데이트 미제공
