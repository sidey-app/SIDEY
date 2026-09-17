# Windows 배포 구조

SIDEY Windows는 PowerToys와 같은 고정 버전의 독립 실행형 배포 원칙을 사용해요. 앱이 사용하는 .NET과 Windows App SDK 파일은 게시할 때 함께 묶고, 사용자 PC의 공유 런타임을 다운로드하거나 변경하지 않아요. SDK와 런타임 버전은 `windows/global.json`, `Sidey.App.csproj`, `Directory.Packages.props`에서 정확히 고정해요.

## 실행 파일과 실제 앱을 분리해요

사용자가 실행하는 `SIDEY.exe`는 Launcher예요. Launcher는 앱 로컬 런타임이 있는 `Runtime\SIDEY.Host.exe`를 실행하고, Host가 실제 WinUI 앱을 구동해요.

```text
SIDEY.exe
Uninstall.exe
Langs\
Assets\
  Bubbles\
  Characters\
  Icons\
  Impacts\
  Throwables\
Runtime\
  SIDEY.Host.exe
  SIDEY.Host.dll
  SIDEY.Host.deps.json
  SIDEY.Host.runtimeconfig.json
  coreclr.dll
  hostfxr.dll
  Microsoft.WindowsAppRuntime.dll
  Microsoft.ui.xaml.dll
  Sidey.Core.dll
  Sidey.Infrastructure.dll
  Sidey.Overlay.dll
  Sidey.Platform.Windows.dll
  Sidey.Presentation.dll
```

일반 `dotnet publish` 결과가 곧 최종 배포 구조는 아니에요. `ConvertTo-PublishLayout.ps1`이 Launcher와 Host 구조로 변환하고 .NET과 Windows App SDK 파일을 모두 `Runtime` 아래에 모아요.

## 자산도 실행 계약이에요

코드가 빌드돼도 `Assets\Characters`나 `Langs`가 빠지면 앱은 정상 동작하지 않아요. 따라서 다음 파일은 부가 자료가 아니라 배포 계약이에요.

- 여러 언어의 `Langs\*.json`
- 픽셀 캐릭터와 말풍선, 던질 수 있는 물체 자산
- 충돌 효과음과 앱 아이콘
- 각 프로젝트의 관리 어셈블리와 런타임 설정

원본 자산은 App과 Overlay 프로젝트에 나뉘어 있지만 게시 결과에서는 배포 루트의 정해진 위치로 모여요. Host의 어셈블리는 `Runtime`에 두고 `Assets`와 `Langs`를 그 안에 다시 복사하지 않아요. 경로를 바꾸면 프로젝트의 복사 규칙, 게시 변환, 배포 테스트를 같은 변경에서 고쳐요.

## 런타임도 payload로 다뤄요

Setup은 .NET이나 Windows App Runtime 설치 프로그램을 실행하지 않아요. 게시 단계가 앱에 필요한 파일을 `Runtime`에 포함하고, `Test-SelfContainedPublish.ps1`이 실제 runtime pack과 Windows App SDK가 들어 있는지 검사해요. SIDEY에는 C++ 프로젝트가 없으므로 현재 Visual C++ 런타임 import도 없어요. 나중에 네이티브 바이너리가 VC 런타임 DLL을 동적으로 import하면 검사가 해당 앱 로컬 DLL이 `Runtime`에 함께 없을 때 실패해요.

Setup은 새 payload 전체를 현재 설치 폴더와 같은 볼륨의 보호된 staging 폴더에 풀고 검증해요. 설치 폴더의 부모가 일반 사용자에게 쓰기 가능한 경로이거나 reparse point를 포함하면 상승된 파일 쓰기와 경로 바꾸기 경쟁을 막을 수 없으므로 설치를 중단해요. staging이 실패할 때는 기존 SIDEY를 그대로 실행할 수 있어야 해요.

배포된 Setup은 오류 정규화, 설치 transaction, 프로세스 종료를 .NET Framework 4.7.2 기반의 컴파일된 도우미로 수행해요. 사용자 PC에서 PowerShell 스크립트나 `ExecutionPolicy Bypass`를 실행하지 않으며, 패키징 검사는 이 호출이 NSIS 런타임 경로에 다시 들어오는 것을 차단해요. 빌드·검증용 저장소 스크립트는 이 제한의 대상이 아니에요.

WiX MSI와 NSIS 사이에는 하나의 원자적 rollback 경계가 없어요. Setup은 이전 MSI를 감지하면 자동 제거하지 않고 기존 설치를 그대로 둔 채 중단해요. 사용자가 Windows 설정의 앱 화면에서 이전 MSI를 제거한 뒤 Setup을 다시 실행해야 해요.

## 사용자 데이터와 프로그램 파일을 구분해요

업데이트와 제거 과정에서 프로그램 설치 폴더는 교체할 수 있지만 사용자 데이터는 보존해요. 기존 NSIS 또는 MSI 설치를 정리할 때도 메시지와 설정이 있는 사용자 데이터 경로를 삭제 대상으로 사용하지 않아요.

Setup과 제거기는 Program Files, HKLM, 모든 사용자 시작 메뉴를 바꾸기 위해 관리자 권한으로 실행돼요. 반면 설치 완료 후 앱 실행과 `%LOCALAPPDATA%`, Credential Manager, HKCU 자동 실행 정리는 데스크톱 셸 사용자의 토큰으로 분리해요. 표준 사용자가 UAC 창에 다른 관리자 계정을 입력해도 관리자 계정의 데이터나 자격 증명을 현재 사용자 상태로 취급하면 안 돼요. 데스크톱 사용자 토큰을 얻지 못하면 앱을 관리자 권한으로 대신 실행하거나 관리자 계정의 데이터를 지우지 않고 안전하게 실패해요.

Setup과 제거기는 전역 mutex 하나로 직렬화해요. 대화형 Setup이나 제거기를 다시 실행하면 두 번째 프로세스는 새 언어 선택 창을 만들지 않고 이미 열린 언어 선택기·Setup·제거기 창을 복원해 활성화를 시도한 뒤 종료 코드 `1618`로 끝나요. Windows가 전경 전환을 허용하지 않으면 기존 창의 작업 표시줄 표시를 깜빡이며, 무인 실행은 UI 없이 같은 코드로 종료해요. 새 payload를 활성화할 때는 기존 NSIS 설치를 먼저 제거하지 않아요. 완성된 staging을 준비한 뒤 실행 중인 앱을 종료하고, 기존 설치 폴더를 rollback 형제 폴더로 이름 변경한 다음 staging을 live 경로로 이름 변경해요. 설치 전 등록 정보도 transaction 상태에 저장해요. 파일 활성화나 등록 정보 갱신이 실패하면 파일·머신 등록·공용 바로가기를 이전 상태로 복원하고, 등록까지 성공해 commit한 뒤에만 이전 폴더를 지워요. 다음 Setup 실행은 중단된 transaction 상태를 먼저 복구하며, 제거기는 지연된 rollback 정리도 함께 끝내요.

설치·업데이트 코드를 바꿀 때는 다음 순서를 지켜요.

1. 앱 로컬 런타임을 포함한 새 게시 결과를 같은 볼륨의 staging 폴더에 모두 풀고 검증해요.
2. 실행 중인 SIDEY 프로세스를 종료해요.
3. 기존 live 폴더를 rollback으로 보존하고 staging을 live로 활성화해요.
4. 공용 바로가기와 시스템 등록 정보를 갱신해요.
5. 실패하면 이전 live를 복원하고, 성공하면 rollback을 정리해요.
6. 사용자가 선택한 경우에만 데스크톱 사용자 토큰으로 Launcher를 실행해요.

## 게시 결과를 직접 검사해요

먼저 `windows/`에서 솔루션을 검증해 `windows/global.json`의 SDK 고정을 적용해요.

```powershell
Push-Location windows
dotnet restore SIDEY.Windows.slnx
dotnet build SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test SIDEY.Windows.slnx --configuration Release --no-restore --no-build
Pop-Location
```

`Test-WindowsBuild.ps1`은 별도의 게시 폴더를 만들고 독립 실행형 계약과 Launcher·Host의 시작까지 검사해요.

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/tests/Test-WindowsBuild.ps1
```

이미 만든 게시 폴더만 검사할 때는 `Test-SelfContainedPublish.ps1`과 `Test-PublishedApplication.ps1`에 같은 `-PublishDirectory`를 명시해요. 두 스크립트는 게시 폴더를 자동으로 찾지 않아요.

이 검사는 다음을 확인해야 해요.

- Launcher와 Host가 정해진 위치에 있는가
- 일곱 언어 카탈로그와 모든 렌더링·오디오 자산이 있는가
- 고정한 .NET과 Windows App SDK 파일이 `Runtime`에 있고, 외부 VC 런타임 import가 해결됐는가
- Launcher가 실제 Host를 시작할 수 있는가

설치 관리자를 바꿨다면 `Test-SelfContainedPublish.ps1`, `Test-InstallTransaction.ps1`, 배포 계약 테스트도 실행해요. 실제 설치 검사는 머신의 설치 상태를 바꿀 수 있으므로 관련 스크립트의 입력과 범위를 먼저 확인해요.

## 배포 실패를 고칠 때 구조를 우회하지 않아요

누락된 DLL을 발견했다고 해당 파일만 수동으로 Setup에 추가하면 로컬에서는 동작해도 다음 게시에서 다시 빠질 수 있어요. 누락이 생긴 단계가 프로젝트 출력, 게시 변환, 설치 복사 중 어디인지 찾고 그 단계의 계약을 고쳐요.

버전 결정과 릴리스 문서는 저장소의 Windows 버전 정책을 따로 확인해요. 이 문서는 배포 구조와 안전한 설치 순서만 설명해요.
