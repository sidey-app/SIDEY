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
- 전용 Win32 오버레이 렌더러 구현 전
- 햄스터 외 4종은 플랫폼 slice 승인 전까지 의도적으로 미포함
- 코드 서명·MSIX·자동 업데이트·ARM64 제외
- 다중 모니터 연결·제거와 mixed-DPI 실기 미검증
