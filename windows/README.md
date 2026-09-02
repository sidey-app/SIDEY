# SIDEY for Windows

Windows 11 25H2(build 26200)+ x64용 네이티브 클라이언트입니다. 첫 기능 빌드부터 `pixel_hamster`, `pixel_cat`, `pixel_puppy`, `pixel_rabbit`, `pixel_penguin` 5종을 같은 catalog 기반 renderer로 다룹니다. 햄스터 1종 검증은 별도 제품 구현이 아니라 같은 renderer의 Debug 제한 모드입니다.

현재 Windows 정식 출시 버전은 `v1.0.3`입니다.

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

GitHub Actions의 일반 PR·`main` 푸시는 복원, 포맷 검사, Release 빌드와 테스트만 수행합니다. MSI 후보 생성은 수동 실행 또는 현재 프로젝트 버전과 일치하는 `windows-v*` 태그에서만 수행하며, 수동 실행은 `publish_release`를 선택한 경우에만 GitHub 정식 Release까지 게시합니다. CI와 Release에는 버전이 표시된 MSI 하나만 올립니다.

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

## MSI 생성과 정식 배포

unpackaged·multi-file self-contained WinUI 앱을 `PublishSingleFile=false`로 게시합니다. 루트의 작은 `SIDEY.exe` 런처가 모든 인수를 `Runtime\SIDEY.Host.exe`로 전달하고, `Uninstall.exe`가 Windows Installer 제거를 시작하거나 제거 custom action에서 현재 사용자 데이터를 정리합니다. 앱 본체와 .NET·Windows App SDK 런타임은 `Runtime` 안에 격리합니다. 사용자 콘텐츠는 `Assets`, SIDEY 자체 JSON 번역 리소스는 `Langs`에 둡니다. 별도 런타임 설치는 필요하지 않으며 모든 파일은 하나의 검증된 버전 단위로 함께 설치·업데이트합니다. 자세한 기준은 [`DEPLOYMENT_LAYOUT.md`](DEPLOYMENT_LAYOUT.md)에 있습니다.

WiX Toolset `6.0.2`는 게시 트리 전체를 포함하는 머신 단위 MSI를 만듭니다. 배포 파이프라인은 SIDEY 파일을 자체 서명하지 않으며, 공급자가 서명한 .NET·Windows App SDK 파일은 원래 서명을 유지합니다.

```powershell
dotnet publish ./windows/src/Sidey.App/Sidey.App.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=false -p:Version=1.0.3 `
  -o ./build/windows/publish

pwsh ./scripts/windows/package.ps1 `
  -PublishDir ./build/windows/publish `
  -OutDir ./build/windows/artifacts `
  -Version 1.0.3
```

CI 아티팩트와 GitHub 정식 Release에는 `SIDEY-Windows-x64-v1.0.3.msi` 하나만 게시합니다. Setup EXE, ZIP, MSIX, 자체 서명 인증서, `.sha256` 파일은 Release에 포함하지 않습니다. MSI는 관리자 승인 뒤 `C:\Program Files\SIDEY`에 설치하고 공용 시작 메뉴에 앱과 제거 바로가기를 추가합니다. 앱 목록의 MSI 제품 정보와 설치된 `Uninstall.exe`에는 SIDEY 아이콘을 사용합니다. 바탕화면 바로가기와 설치 중 로그인 자동 실행은 만들지 않습니다.

기존 Windows 테스트 버전이 설치되어 있으면 Windows 설정에서 먼저 제거한 뒤 v1.0.3을 설치합니다. v1.0.3은 Windows 설정이나 MSI에서 제거할 때 `Uninstall.exe --cleanup`을 실행하고, 설치 폴더나 시작 메뉴에서 `Uninstall.exe`를 직접 실행하면 Windows Installer 제거를 시작합니다. 일반 제거는 `%LOCALAPPDATA%\SIDEY` 설정·로그와 Credential Manager의 `SIDEY/` 자격 증명까지 삭제하며, repair와 major upgrade는 이 데이터를 보존합니다.

Windows와 macOS는 같은 GitHub 저장소를 사용하지만 릴리스 주기는 독립적입니다. Windows 릴리스 태그는 `windows-v<version>`, macOS 릴리스 태그는 기존 `v<version>` 형식을 사용합니다. Windows 앱은 Pages의 `website/windows-latest.json`만 확인하며, 호환 경로인 `website/windows/update.json`도 같은 내용으로 유지합니다.

새 Windows 버전을 알릴 때 두 manifest에는 검증된 MSI의 정확한 GitHub Release `installer_url`과 64자리 `sha256`을 기록합니다. SHA-256은 업데이트 다운로드 검증에 사용하지만 별도 Release 파일로 공개하지 않습니다. 앱은 URL이 해당 `windows-v<version>` Release의 정해진 MSI인지 확인하고, 내려받은 바이트의 SHA-256이 일치할 때만 설치 프로그램을 실행합니다.

```powershell
./scripts/windows/verify-release.ps1 `
  -Version 1.0.3 `
  -CandidateMsi ./build/windows/artifacts/SIDEY-Windows-x64-v1.0.3.msi
```

실제 GitHub Release에서 다시 받은 MSI의 hash가 후보와 일치한 뒤에만 웹사이트 Windows 다운로드 버튼과 업데이트 manifest를 v1.0.3으로 갱신합니다.

시작 직후 종료되거나 오류창이 나타나면 `%LOCALAPPDATA%\SIDEY\Logs\startup.log`를 확인합니다. 이 로그에는 시작 단계와 예외 유형·HRESULT·stack만 남기며 token·메시지 본문·초대 코드는 기록하지 않습니다.

## SHA-256 검증

패키징 명령은 MSI의 SHA-256을 CI 로그에 출력합니다. Release에 별도 checksum 파일을 첨부하지 않고, 검증한 값을 두 Windows 업데이트 manifest에 기록합니다.

```powershell
Get-FileHash .\SIDEY-Windows-x64-v1.0.3.msi -Algorithm SHA256
```

## 정식 출시 후 지속 검증

- Windows 30분 햄스터 제한 실기 계측
- 12명 2시간·20노드 30분 장시간 실기
- macOS↔Windows 메시지·Presence·typing·pulse·그룹 관리 양방향 실서버 검증
- clean install·repair·upgrade·downgrade와 Windows 설정·MSI·`Uninstall.exe` 제거 시 데이터 정리 회귀 검증
- 향후 공인 코드 서명, MSIX, ARM64 배포 검토
