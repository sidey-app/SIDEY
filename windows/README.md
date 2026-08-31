# SIDEY for Windows

Windows 11 25H2(build 26200)+ x64용 네이티브 클라이언트입니다. 현재는 공개 배포본이 아니라 햄스터 1종 플랫폼 vertical slice를 만드는 단계입니다.

## 필수 환경

- Windows 11 25H2 x64
- Visual Studio 2026
  - Windows application development
  - Desktop development with C++
  - Windows 11 SDK 10.0.26100 이상
- .NET 10 SDK

프로젝트는 Windows SDK 계약 `10.0.26100.0`을 대상으로 컴파일하고, 실행 시 제품 최소 OS build 26200을 별도로 검사합니다. OS build와 SDK 계약 버전을 억지로 같은 값으로 맞추면 참조팩을 찾지 못해 빌드가 깨질 수 있습니다.

## 다른 Windows PC에서 빠르게 실행

아직 설치형 앱이 아니라 소스 기반 내부 검증 단계입니다. **Windows 11 25H2 x64 실기**에서 PowerShell 또는 Visual Studio Developer PowerShell을 열고 진행합니다.

처음 받는 PC라면:

```powershell
git clone https://github.com/sidey-app/SIDEY.git
cd SIDEY
git switch main
```

이미 저장소가 있다면 다른 로컬 변경을 먼저 보관한 뒤 최신 `main`을 받습니다.

```powershell
git switch main
git pull --ff-only
```

환경과 전체 자동 검증을 확인합니다.

```powershell
dotnet --version
Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsBuildNumber, OsArchitecture
Set-ExecutionPolicy -Scope Process Bypass
./scripts/windows/test.ps1
```

정상 기준은 .NET SDK `10.x`, OS build `26200` 이상, x64이며 두 테스트 프로젝트와 Release 빌드가 모두 성공하는 것입니다. 그다음 로컬 햄스터 slice를 실행합니다.

```powershell
dotnet run --project ./windows/src/Sidey.App/Sidey.App.csproj --configuration Debug
```

현재 slice는 로그인이나 서버 연결이 없는 플랫폼 검증본입니다. 정상이라면 SIDEY 검증 창과 화면 가장자리의 픽셀 햄스터가 함께 나타납니다.

### 실기 체크리스트

1. 메모장 위에서 햄스터가 없는 투명 영역을 클릭했을 때 클릭이 메모장으로 통과하는지 확인합니다.
2. 햄스터 위치의 52×52 hotspot을 클릭하면 400×56 입력창이 열리는지 확인합니다.
3. 한글 IME 조합 중 글자가 끊기지 않는지, `Enter` 전송·`Shift+Enter` 최대 3줄·`Esc` 닫기가 동작하는지 확인합니다. 현재 전송은 서버가 아니라 로컬 성공 표시만 바꿉니다.
4. 검증 창에서 가장자리 4개와 길이 3개를 모두 조합해 12개 프리셋을 적용합니다. 햄스터의 발이 선택한 가장자리를 향하고 화면 밖으로 잘리지 않아야 합니다.
5. Windows 디스플레이 배율을 100%, 125%, 150%, 200%로 바꾼 뒤 앱을 완전히 종료하고 다시 실행합니다. 픽셀이 흐려지거나 hotspot이 어긋나지 않아야 합니다.
6. 앱을 10분 이상 두고 햄스터 움직임이 멈추거나 CPU·메모리·GDI handle이 계속 증가하지 않는지 작업 관리자에서 확인합니다.

문제가 생기면 아래 네 가지를 함께 남깁니다.

- `./scripts/windows/test.ps1` 전체 출력
- OS build, 디스플레이 배율, 모니터 해상도
- 선택한 가장자리·길이 프리셋
- 증상이 보이는 화면 녹화 또는 스크린샷

## 프로젝트 소유권

- `Sidey.App`: WinUI 화면과 feature ViewModel
- `Sidey.Core`: 플랫폼 독립 모델·검증·Realtime 규칙·이동 시뮬레이션
- `Sidey.Infrastructure`: Supabase·Credential Locker·설정 adapter
- `Sidey.Overlay`: 전용 HWND의 30 FPS 픽셀 월드
- `Sidey.Platform.Windows`: 창·DPI·모니터·트레이·활동 감지

ViewModel은 Supabase endpoint, Realtime payload, HWND를 직접 소유하지 않습니다. `Sidey.Core`는 Windows 또는 Supabase 패키지를 참조하지 않습니다.

## 빌드와 테스트

저장소 루트의 PowerShell에서 실행합니다.

```powershell
pwsh ./scripts/windows/test.ps1
dotnet build ./windows/SIDEY.Windows.slnx -c Release
```

self-contained 내부 검증 ZIP은 다음처럼 만듭니다.

```powershell
dotnet publish ./windows/src/Sidey.App/Sidey.App.csproj `
  -c Release -r win-x64 --self-contained true `
  -o ./build/windows/publish

pwsh ./scripts/windows/package.ps1 `
  -PublishDir ./build/windows/publish `
  -OutDir ./build/windows
```

생성 이름은 `SIDEY-Windows-x64-0.3.0-alpha.1.zip`과 같은 이름의 `.sha256`입니다. 이 파일은 햄스터 플랫폼 slice와 전체 기능 동등성·장시간 검증을 모두 통과하기 전에는 공개하지 않습니다.

## 현재 제한

- Google OAuth·Supabase staging 연결 전
- 햄스터 1종용 `UpdateLayeredWindow` 렌더러만 구현됨. 최종 5종 렌더러 구조는 실기 측정 후 확정
- 햄스터 외 4종은 플랫폼 slice 승인 전까지 의도적으로 미포함
- 코드 서명·MSIX·자동 업데이트·ARM64 제외
- 다중 모니터 연결·제거와 mixed-DPI 실기 미검증
