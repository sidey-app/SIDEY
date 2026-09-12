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

설치 관리자는 먼저 조건을 검사하고, 부족한 런타임만 Microsoft 주소에서 내려받아요. 런타임 설치가 성공한 뒤에만 기존 SIDEY 파일을 정리해요. 선행 조건 실패 전에 앱을 지우면 사용자는 이전 버전도 실행할 수 없게 되기 때문이에요.

이전 MSI를 제거할 때 종료 코드 `3010`은 실패가 아니라 Windows 재시작이 필요하다는 뜻이에요. 이때는 새 파일을 복사하지 않고 재시작 안내를 보여 준 뒤 종료해요. 사용자가 재시작한 다음 Setup을 다시 실행해야 안전하게 마이그레이션할 수 있어요.

## 사용자 데이터와 프로그램 파일을 구분해요

업데이트와 제거 과정에서 프로그램 설치 폴더는 교체할 수 있지만 사용자 데이터는 보존해요. 기존 NSIS 또는 MSI 설치를 정리할 때도 메시지와 설정이 있는 사용자 데이터 경로를 삭제 대상으로 사용하지 않아요.

설치·업데이트 코드를 바꿀 때는 다음 순서를 지켜요.

1. 실행 중인 SIDEY 프로세스를 안전하게 종료해요.
2. 필요한 런타임이 준비됐는지 확인해요.
3. 이전 설치 방식에 맞는 제거 경로를 선택해요.
4. 프로그램 파일만 정리해요.
5. 새 게시 결과를 복사하고 등록 정보를 갱신해요.
6. Launcher로 실제 시작을 확인해요.

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

설치 관리자를 바꿨다면 런타임 선행 조건 검사와 배포 계약 테스트도 실행해요. 실제 설치 검사는 머신의 런타임과 설치 상태를 바꿀 수 있으므로 관련 스크립트의 입력과 범위를 먼저 확인해요.

## 배포 실패를 고칠 때 구조를 우회하지 않아요

누락된 DLL을 발견했다고 해당 파일만 수동으로 Setup에 추가하면 로컬에서는 동작해도 다음 게시에서 다시 빠질 수 있어요. 누락이 생긴 단계가 프로젝트 출력, 게시 변환, 설치 복사 중 어디인지 찾고 그 단계의 계약을 고쳐요.

버전 결정과 릴리스 문서는 저장소의 Windows 버전 정책을 따로 확인해요. 이 문서는 배포 구조와 안전한 설치 순서만 설명해요.
