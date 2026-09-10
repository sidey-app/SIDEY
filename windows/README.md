# SIDEY for Windows

Windows 11 25H2(build 26200)+ x64용 네이티브 클라이언트입니다. 첫 기능 빌드부터 `pixel_hamster`, `pixel_cat`, `pixel_puppy`, `pixel_rabbit`, `pixel_penguin` 5종을 같은 catalog 기반 renderer로 다룹니다. 햄스터 1종 검증은 별도 제품 구현이 아니라 같은 renderer의 Debug 제한 모드입니다.

현재 Windows 정식 출시 버전은 [release/windows.json](../release/windows.json)의 `version`을 기준으로 합니다.

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
- `Sidey.Core`: 무료 5종·유료 4종 캐릭터와 꾸미기 catalog, 플랫폼 독립 모델·검증·Realtime 규칙·이동 시뮬레이션
- `Sidey.Infrastructure`: Supabase adapter, Windows Credential Manager, atomic preferences
- `Sidey.Overlay`: 단일 Win32 world HWND, self 1개·상대 최대 11개의 hotspot HWND, 30 FPS 고정 step, premultiplied BGRA frame cache
- `Sidey.Platform.Windows`: 창·DPI·모니터·트레이·로그인 실행·시스템 유휴/잠금 감지

UI는 Supabase DTO, Credential Manager, HWND를 직접 소유하지 않습니다. `Sidey.Core`는 Windows·Supabase 패키지를 참조하지 않습니다. 종별 switch·HWND·renderer class는 추가하지 마세요. 새 내장 캐릭터는 asset, manifest, catalog entry로만 추가합니다.

## 빌드와 자동 검증

저장소 루트의 PowerShell에서 실행합니다.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./scripts/windows/Test-WindowsBuild.ps1
dotnet build ./windows/SIDEY.Windows.slnx -c Release
```

GitHub Actions의 `Windows CI`는 일반 PR·`main` 푸시에서 릴리스 메타데이터·에셋, 복원·포맷·Release 빌드·전체 테스트, 공유 런타임 전제조건, 게시 payload·실행 스모크와 NSIS 컴파일을 검증합니다. 정식 배포는 `main`의 수동 `Windows Release`에서 manifest 버전을 확인 입력해 실행합니다. 전체 검증·패키징 후 draft Release의 단일 Setup EXE를 다시 내려받아 후보 SHA-256과 대조한 뒤 공개하고 Pages 배포를 호출합니다. 태그 푸시는 배포 진입점이 아닙니다. 배포 후보 Setup EXE는 Actions artifact로 7일 보관하며 정식 Release에는 설치 파일 하나만 게시합니다.

일반 실행과 설치본은 macOS와 같은 production Supabase publishable 구성을 기본 사용하며, 같은 익명 세션을 복구하거나 신규 설치에서만 생성합니다. Release는 Google 연결·PortOne 구매를 컴파일 타임으로 잠그며 `sidey://auth/google` callback 등록 기반만 포함합니다. `SideyDevelopmentCommerce=true`로 컴파일하고 `SIDEY_WINDOWS_DEVELOPMENT_COMMERCE=1`로 실행한 Debug 빌드에서만 staging의 기존 계정 Google 연결·PKCE·`sidey-dev://auth/google` callback과 테스트 결제를 허용합니다. 로컬 개발에서만 아래 환경변수로 두 값을 함께 덮어쓸 수 있습니다. HTTPS 또는 localhost HTTP와 publishable key만 허용하며 service-role/secret key는 거부합니다.

```powershell
$env:SIDEY_SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co'
$env:SIDEY_SUPABASE_PUBLISHABLE_KEY = 'YOUR_PUBLISHABLE_KEY'
dotnet run --project ./windows/src/Sidey.App/Sidey.App.csproj --configuration Debug
```

두 환경변수가 없으면 production backend를 사용합니다. 서버 없는 5종 로컬 미리보기와 햄스터 제한 계측은 아래 Debug 검증 모드에서만 실행되며 Release에는 노출되지 않습니다.

로컬 앱 설정을 초기화했지만 Windows 자격 증명과 서버 데이터가 남아 있으면 온보딩 입력란에 기존 프로필과 활성 그룹 이름을 채웁니다. 복원된 데이터만으로 단계를 자동 진행하지 않으며 사용자가 각 단계를 직접 확인해야 합니다. 그룹 생성이나 참여를 원하지 않으면 그룹 단계에서 `건너뛰기`를 선택할 수 있고, 마지막 `SIDEY 시작`을 누른 뒤에만 온보딩 완료 상태를 저장합니다.

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

문제 보고에는 `Test-WindowsBuild.ps1` 전체 출력, OS build, DPI/모니터, 영역 프리셋, 계측 JSON, 화면 녹화를 포함합니다. 별도로 12명 2시간·20노드 30분 장시간 테스트와 macOS↔Windows 양방향 계약 검증도 사용자가 수행하고 결과를 제공해야 합니다.

## Setup EXE 생성과 정식 배포

unpackaged·multi-file framework-dependent WinUI 앱을 `SelfContained=false`, `WindowsAppSDKSelfContained=false`, `PublishSingleFile=false`로 게시합니다. 루트의 작은 `SIDEY.exe` 런처가 모든 인수를 `Runtime\SIDEY.Host.exe`로 전달하고, NSIS가 아이콘이 포함된 `Uninstall.exe`를 생성합니다. `Runtime`에는 앱 본체·의존성·bootstrapper를 두며 .NET 10 / Windows App Runtime 본체는 포함하지 않습니다. 설치기는 누락된 공유 런타임을 Microsoft 공식 경로에서 받아 서명과 설치 결과를 확인한 후 기존 SIDEY를 제거하고 새 앱을 설치합니다. 기존 self-contained `Runtime` 잔여 파일은 정리하고 공유 런타임은 SIDEY 제거 후에도 보존합니다. 사용자 콘텐츠는 `Assets`, SIDEY 자체 JSON 번역 리소스는 `Langs`에 둡니다. 자세한 기준은 [`DEPLOYMENT_LAYOUT.md`](DEPLOYMENT_LAYOUT.md)에 있습니다.

NSIS `3.12`는 게시 트리 전체를 포함하는 머신 단위 Setup EXE를 만듭니다. 배포 파이프라인은 SIDEY 파일을 자체 서명하지 않으며, 공급자가 서명한 .NET·Windows App SDK 파일은 원래 서명을 유지합니다.

```powershell
$sideyVersion = [string](Get-Content ./release/windows.json -Raw | ConvertFrom-Json).version

dotnet publish ./windows/src/Sidey.App/Sidey.App.csproj `
  -c Release -r win-x64 --self-contained false `
  -p:WindowsAppSDKSelfContained=false -p:PublishSingleFile=false -p:Version=$sideyVersion `
  -o ./build/windows/publish

./scripts/windows/New-WindowsInstaller.ps1 `
  -PublishDirectory ./build/windows/publish `
  -OutputDirectory ./build/windows/artifacts `
  -Version $sideyVersion
```

Windows 릴리스 후보 아티팩트와 GitHub 정식 Release에는 `SIDEY-Windows-x64-v<version>-Setup.exe` 하나만 게시합니다. MSI, ZIP, MSIX, 자체 서명 인증서, `.sha256` 파일은 포함하지 않습니다. Setup EXE는 관리자 승인 뒤 기본적으로 `C:\Program Files\SIDEY`에 설치하고 공용 시작 메뉴에 앱과 제거 바로가기를 추가합니다. 설치 위치는 신규 설치에서 선택할 수 있고 이후 업데이트와 복구에서 그대로 사용합니다. 앱 목록과 설치된 `Uninstall.exe`에는 SIDEY 아이콘을 사용합니다. 바탕화면 바로가기와 설치 중 로그인 자동 실행은 만들지 않습니다.

기존 v1.0.5 정식 MSI는 Setup EXE가 자동으로 제거한 뒤 같은 위치에 새 버전을 설치하며 사용자 데이터는 보존합니다. v1.0.3·v1.0.4의 앱 내 업데이트는 파일 잠금 오류로 실패하므로 최신 Setup EXE를 한 번 수동 설치해야 합니다. 과거 per-user·Burn 테스트 설치는 등록 방식이 달라 먼저 Windows 설정에서 제거해야 합니다. 같은 버전의 Setup EXE를 다시 실행하면 복구·제거·닫기를 선택할 수 있고 더 낮은 버전 설치는 차단합니다. 일반 제거에서는 설정·로그와 로그인 자격 증명을 각각 삭제할지 기본 미선택 상태로 고를 수 있으며, 선택한 항목만 현재 사용자 프로필에서 삭제합니다. 업데이트와 복구에서는 사용자 데이터를 삭제하지 않습니다.

Windows와 macOS는 같은 GitHub 저장소를 사용하지만 릴리스 주기는 독립적입니다. Windows 릴리스 태그는 `windows-v<version>`, macOS 릴리스 태그는 기존 `v<version>` 형식을 사용합니다. Windows 앱은 Pages의 `/SIDEY/windows-latest.json`을 확인하며, 호환 경로인 `/SIDEY/windows/update.json`도 같은 내용으로 제공합니다.

공개 버전의 원본은 `release/windows.json`입니다. Pages가 정식 Release의 단일 Setup EXE를 다시 내려받아 검증한 뒤 배포 산출물인 `website/dist/windows-latest.json`과 `website/dist/windows/update.json`을 생성합니다. 두 업데이트 manifest의 버전·태그·고정 `installer_url`과 64자리 `sha256`은 이 과정에서 파생하며 수동으로 수정하지 않습니다. 앱은 URL이 해당 `windows-v<version>` Release의 정해진 Setup EXE인지 확인하고, 사용자 승인 뒤 내려받은 바이트의 SHA-256이 일치할 때만 설치 프로그램을 실행합니다.

```powershell
$sideyVersion = [string](Get-Content ./release/windows.json -Raw | ConvertFrom-Json).version

./scripts/windows/Test-WindowsRelease.ps1 `
  -Version $sideyVersion `
  -CandidateSetupPath "./build/windows/artifacts/SIDEY-Windows-x64-v$sideyVersion-Setup.exe"
```

이 명령은 실제 GitHub 정식 Release에서 다시 받은 Setup EXE의 hash를 로컬 후보와 비교합니다. 웹사이트 다운로드 버튼과 업데이트 manifest의 갱신은 정식 배포 후 Pages가 검증·생성한 산출물로 수행합니다.

시작 직후 종료되거나 오류창이 나타나면 `%LOCALAPPDATA%\SIDEY\Logs\SIDEY.<underscore-version>.<yyyyMMdd>.<HHmmss>.log` 세션 로그를 확인합니다. 버전의 점은 밑줄로 바꾸며 시작·실행 진단을 한 파일에 UTC로 기록합니다. 인증·연결·메시지 처리 단계·렌더링·성능·예외 유형·HRESULT·stack을 기록하되 token·메시지 본문·초대 코드·닉네임·email·UUID 원문과 다른 앱의 활동·입력 내용은 남기지 않습니다. 파일당 4MB 기록 한도와 30일·100개·총 32MB 보존 한도를 적용합니다.

## SHA-256 검증

패키징 명령은 Setup EXE의 SHA-256을 CI 로그에 출력합니다. Release에 별도 checksum 파일을 첨부하지 않으며 Pages가 공개 설치 파일을 검증하고 두 업데이트 manifest에 hash를 기록합니다.

```powershell
$sideyVersion = [string](Get-Content ./release/windows.json -Raw | ConvertFrom-Json).version
Get-FileHash "./build/windows/artifacts/SIDEY-Windows-x64-v$sideyVersion-Setup.exe" -Algorithm SHA256
```

## 정식 출시 후 지속 검증

- Windows 30분 햄스터 제한 실기 계측
- 12명 2시간·20노드 30분 장시간 실기
- macOS↔Windows 메시지·Presence·typing·pulse·그룹 관리 양방향 실서버 검증
- clean install·repair·upgrade·downgrade·기존 MSI 전환과 Windows 설정·`Uninstall.exe` 제거 옵션의 기본 미선택·선택 시 데이터 정리 회귀 검증
- 향후 공인 코드 서명, MSIX, ARM64 배포 검토
