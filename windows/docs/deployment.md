# Windows 배포 구조

SIDEY Windows는 framework-dependent 방식으로 게시해요. 앱과 SIDEY 자산은 배포하지만 .NET, Visual C++ Redistributable, Windows App Runtime은 Microsoft가 설치한 공유 런타임을 사용한다는 뜻이에요. 런타임을 앱마다 복사하지 않아 설치 크기와 보안 업데이트 책임을 줄일 수 있어요.

## 실행 파일과 실제 앱을 분리해요

사용자가 실행하는 `SIDEY.exe`는 Launcher예요. Launcher는 필요한 런타임을 확인한 뒤 `Runtime\SIDEY.Host.exe`를 실행해요. Host가 실제 WinUI 앱이에요.

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
  Sidey.Core.dll
  Sidey.Infrastructure.dll
  Sidey.Overlay.dll
  Sidey.Platform.Windows.dll
  Sidey.Presentation.dll
```

일반 `dotnet publish` 결과가 곧 최종 배포 구조는 아니에요. `ConvertTo-PublishLayout.ps1`이 Launcher와 Host 구조로 변환하고 독립 실행형 런타임 잔여물이 없는지 확인해요.

## 자산도 실행 계약이에요

코드가 빌드돼도 `Assets\Characters`나 `Langs`가 빠지면 앱은 정상 동작하지 않아요. 따라서 다음 파일은 부가 자료가 아니라 배포 계약이에요.

- 여러 언어의 `Langs\*.json`
- 픽셀 캐릭터와 말풍선, 던질 수 있는 물체 자산
- 충돌 효과음과 앱 아이콘
- 각 프로젝트의 관리 어셈블리와 런타임 설정

원본 자산은 App과 Overlay 프로젝트에 나뉘어 있지만 게시 결과에서는 배포 루트의 정해진 위치로 모여요. Host의 어셈블리는 `Runtime`에 두고 `Assets`와 `Langs`를 그 안에 다시 복사하지 않아요. 경로를 바꾸면 프로젝트의 복사 규칙, 게시 변환, 배포 테스트를 같은 변경에서 고쳐요.

## 설치 전제 조건을 먼저 확인해요

필수 런타임과 최소 버전은 `windows/installer/Sidey.Setup/prerequisites.json`이 정해요.

- Visual C++ Redistributable x64
- .NET Runtime x64
- Windows App Runtime 패키지 집합

설치 관리자는 먼저 조건을 검사하고, 부족한 런타임만 Microsoft 주소에서 내려받아요. 런타임 설치가 성공한 뒤 새 payload 전체를 현재 설치 폴더와 같은 볼륨의 보호된 staging 폴더에 풀고 검증해요. 설치 폴더의 부모가 일반 사용자에게 쓰기 가능한 경로이거나 reparse point를 포함하면 상승된 파일 쓰기와 경로 바꾸기 경쟁을 막을 수 없으므로 설치를 중단해요. 선행 조건이나 staging이 실패할 때는 기존 SIDEY를 그대로 실행할 수 있어야 해요.

배포된 Setup은 선행 조건 설치, 오류 정규화, 설치 transaction, 프로세스 종료를 .NET Framework 4.7.2 기반의 컴파일된 도우미로 수행해요. 사용자 PC에서 PowerShell 스크립트나 `ExecutionPolicy Bypass`를 실행하지 않으며, 패키징 검사는 이 호출이 NSIS 런타임 경로에 다시 들어오는 것을 차단해요. 빌드·검증용 저장소 스크립트는 이 제한의 대상이 아니에요.

WiX MSI와 NSIS 사이에는 하나의 원자적 rollback 경계가 없어요. Setup은 이전 MSI를 감지하면 자동 제거하지 않고 기존 설치를 그대로 둔 채 중단해요. 사용자가 Windows 설정의 앱 화면에서 이전 MSI를 제거한 뒤 Setup을 다시 실행해야 해요.

## 사용자 데이터와 프로그램 파일을 구분해요

업데이트와 제거 과정에서 프로그램 설치 폴더는 교체할 수 있지만 사용자 데이터는 보존해요. 기존 NSIS 또는 MSI 설치를 정리할 때도 메시지와 설정이 있는 사용자 데이터 경로를 삭제 대상으로 사용하지 않아요.

Setup과 제거기는 Program Files, HKLM, 모든 사용자 시작 메뉴를 바꾸기 위해 관리자 권한으로 실행돼요. 반면 설치 완료 후 앱 실행과 `%LOCALAPPDATA%`, Credential Manager, HKCU 자동 실행 정리는 데스크톱 셸 사용자의 토큰으로 분리해요. 표준 사용자가 UAC 창에 다른 관리자 계정을 입력해도 관리자 계정의 데이터나 자격 증명을 현재 사용자 데이터로 취급하면 안 돼요. 데스크톱 사용자 토큰을 얻지 못하면 앱을 관리자 권한으로 대신 실행하거나 관리자 계정의 데이터를 지우지 않고 안전하게 실패해요.

Setup과 제거기는 전역 mutex 하나로 직렬화해요. 새 payload를 활성화할 때는 기존 NSIS 설치를 먼저 제거하지 않아요. 완성된 staging을 준비한 뒤 실행 중인 앱을 종료하고, 기존 설치 폴더를 rollback 형제 폴더로 이름 변경한 다음 staging을 live 경로로 이름 변경해요. 설치 전 등록 정보도 transaction 상태에 저장해요. 파일 활성화나 등록 정보 갱신이 실패하면 파일·머신 등록·공용 바로가기를 이전 상태로 복원하고, 등록까지 성공해 commit한 뒤에만 이전 폴더를 지워요. 다음 Setup 실행은 중단된 transaction 상태를 먼저 복구하며, 제거기는 지연된 rollback 정리도 함께 끝내요.

설치·업데이트 코드를 바꿀 때는 다음 순서를 지켜요.

1. 필요한 런타임이 준비됐는지 확인해요.
2. 새 게시 결과를 같은 볼륨의 staging 폴더에 모두 풀고 검증해요.
3. 실행 중인 SIDEY 프로세스를 종료해요.
4. 기존 live 폴더를 rollback으로 보존하고 staging을 live로 활성화해요.
5. 공용 바로가기와 시스템 등록 정보를 갱신해요.
6. 실패하면 이전 live를 복원하고, 성공하면 rollback을 정리해요.
7. 사용자가 선택한 경우에만 데스크톱 사용자 토큰으로 Launcher를 실행해요.

## 게시 결과를 직접 검사해요

저장소 루트에서 먼저 솔루션을 검증해요.

```powershell
dotnet restore windows/SIDEY.Windows.slnx
dotnet build windows/SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test windows/SIDEY.Windows.slnx --configuration Release --no-restore --no-build
```

`Test-WindowsBuild.ps1`은 별도의 게시 폴더를 만들고 framework-dependent 계약, 선행 조건, Launcher와 Host의 시작까지 검사해요. 선행 조건 설치가 필요하면 머신 상태가 바뀔 수 있으므로 스크립트의 범위를 확인한 뒤 실행해요.

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/Test-WindowsBuild.ps1
```

이미 만든 게시 폴더만 검사할 때는 `Test-FrameworkDependentPublish.ps1`과 `Test-PublishedApplication.ps1`에 같은 `-PublishDirectory`를 명시해요. 두 스크립트는 게시 폴더를 자동으로 찾지 않아요.

이 검사는 다음을 확인해야 해요.

- Launcher와 Host가 정해진 위치에 있는가
- 일곱 언어 카탈로그와 모든 렌더링·오디오 자산이 있는가
- 독립 실행형 .NET 또는 Windows App Runtime 파일이 섞이지 않았는가
- Launcher가 실제 Host를 시작할 수 있는가

설치 관리자를 바꿨다면 런타임 선행 조건 검사, `Test-InstallTransaction.ps1`, 배포 계약 테스트도 실행해요. 실제 설치 검사는 머신의 런타임과 설치 상태를 바꿀 수 있으므로 관련 스크립트의 입력과 범위를 먼저 확인해요.

## 배포 실패를 고칠 때 구조를 우회하지 않아요

누락된 DLL을 발견했다고 해당 파일만 수동으로 Setup에 추가하면 로컬에서는 동작해도 다음 게시에서 다시 빠질 수 있어요. 누락이 생긴 단계가 프로젝트 출력, 게시 변환, 설치 복사 중 어디인지 찾고 그 단계의 계약을 고쳐요.

버전 결정과 릴리스 문서는 저장소의 Windows 버전 정책을 따로 확인해요. 이 문서는 배포 구조와 안전한 설치 순서만 설명해요.
