# Windows 디버깅

디버깅은 증상을 보고 곧바로 코드를 바꾸는 일이 아니에요. 사용자가 한 동작이 어느 경계를 지나며 달라졌는지 좁혀 가는 일이에요. 경계를 먼저 찾으면 관련 없는 프로젝트를 읽고 수정하는 시간을 줄일 수 있어요.

## 재현 조건부터 고정해요

같은 버그처럼 보여도 창 상태, 연결 상태, DPI, 모니터 배치에 따라 원인이 다를 수 있어요. 조사 전에 다음 정보를 적어요.

- 사용자가 한 동작과 기대한 결과
- 실제 결과와 처음 나타난 시점
- Debug 또는 Release 구성, 앱 버전과 설치 방식
- Windows 버전, 모니터 수, 배율과 배치
- 선택한 앱 언어와 연결 상태
- 항상 재현되는지, 재시작 뒤에도 재현되는지

메시지 내용, 초대 코드, 원본 사용자·방 UUID 같은 개인정보는 재현 기록에 넣지 않아요.

## 동작이 지나가는 경계를 따라가요

예를 들어 전송 버튼이 동작하지 않는다면 다음 순서로 확인해요.

```text
XAML Command 바인딩
  → ComposerViewModel 명령과 상태
  → SendRequested 이벤트
  → App 조립 코드
  → AppCoordinator
  → 저장소와 서버 응답
```

처음으로 값이 기대와 달라지는 지점이 원인 후보예요. 처음부터 `AppCoordinator` 전체를 읽는 것보다 이 흐름을 한 단계씩 확인하는 편이 알아야 할 맥락이 적어요.

문제 유형에 따라 시작 지점을 바꿔요.

- 화면 상태와 명령은 `Sidey.Presentation`에서 시작해요.
- 서버, 인증, 설정, 로컬 저장은 `Sidey.Infrastructure`에서 시작해요.
- 픽셀 배치와 그리기는 `Sidey.Overlay`에서 시작해요.
- 창, 모니터, 입력 통과, 시작 프로그램은 `Sidey.Platform.Windows`에서 시작해요.
- 객체 생성과 수명 연결은 `Sidey.App`에서 시작해요.

## 가장 작은 검사부터 실행해요

원인 후보와 가까운 테스트를 먼저 실행하면 피드백이 빠르고 실패 이유도 선명해요.

```powershell
dotnet test windows/tests/Sidey.Presentation.Tests/Sidey.Presentation.Tests.csproj --configuration Release --nologo
```

수정 뒤에는 저장소 루트에서 전체 검사를 실행해요.

```powershell
dotnet restore windows/SIDEY.Windows.slnx
dotnet format windows/SIDEY.Windows.slnx --verify-no-changes --no-restore
dotnet build windows/SIDEY.Windows.slnx --configuration Debug --no-restore
dotnet build windows/SIDEY.Windows.slnx --configuration Release --no-restore
dotnet test windows/SIDEY.Windows.slnx --configuration Release --no-restore --no-build
```

ViewModel 테스트는 명령을 실행한 뒤 상태와 협력자 호출을 확인해요. XAML 자체가 계약이면 XML 구조를 읽어 필수 바인딩을 확인할 수 있지만, 공백과 속성 순서에는 의존하지 않아요. 실제 포커스, 창 활성화, 클릭 같은 WinUI 동작은 UI 상호작용 테스트나 수동 검사로 확인해요.

## 시작 문제는 Launcher와 Host를 나눠 봐요

게시된 SIDEY는 실행 환경을 확인하는 Launcher와 실제 WinUI 앱인 Host로 나뉘어 있어요. `SIDEY.exe`가 열리지 않는다고 해서 곧바로 View 코드 문제라고 판단하면 안 돼요.

1. 게시 폴더 구조가 완성됐는지 확인해요.
2. Launcher가 .NET, Visual C++ Redistributable, Windows App Runtime 조건을 통과했는지 확인해요.
3. Host가 시작됐는지 세션 로그의 단계 표식을 확인해요.
4. Host가 시작됐다면 `startup-complete` 전후에서 처음 실패한 단계를 찾아요.

진단 로그는 다음 위치에 있어요.

```text
%LOCALAPPDATA%\SIDEY\Logs\SIDEY.<버전>.<yyyyMMdd>.<HHmmss>.log
```

예외 메시지 전체가 아니라 예외 형식, HRESULT, 안전하게 분류한 네트워크·Win32 정보가 기록돼요. 자세한 규칙은 [`logging.md`](logging.md)를 따라요.

## 빌드 산출물을 무조건 지우지 않아요

오래된 `bin`과 `obj`가 원인일 수 있지만, 저장소 전체를 먼저 지우면 실제 원인을 가릴 수 있어요. 우선 실패한 프로젝트와 사용 중인 프로세스를 확인하고 `dotnet clean`으로 알려진 빌드 산출물만 다시 만들어요.

게시 문제라면 일반 빌드 결과가 아니라 실제 게시 결과를 검사해요.

```powershell
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/Test-FrameworkDependentPublish.ps1
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File scripts/windows/Test-PublishedApplication.ps1
```

이 검사는 배포 파일의 위치, 공유 런타임 전제, 실제 실행 가능성을 확인해요. 설치 관리자의 선행 조건 설치까지 포함하는 전체 배포 검사는 환경을 바꿀 수 있으므로 스크립트의 범위를 먼저 읽고 실행해요.

## 오버레이 문제는 좌표계를 적어요

오버레이는 논리 좌표, 화면 픽셀, 모니터 작업 영역을 함께 사용해요. 좌표계나 배율을 적지 않은 숫자는 정상처럼 보여도 다른 DPI에서 어긋날 수 있어요.

다음을 함께 확인해요.

- 모니터 원점과 작업 영역
- Windows 배율과 논리 크기
- 24×24 논리 픽셀의 정수 배율
- 좌우 반전과 premultiplied BGRA 처리
- 기본 입력 통과와 명시적 상호작용 모드 전환
- 프레임마다 새 비트맵이나 버퍼가 생기지 않는지

특정 보안 화면, DRM 앱, 관리자 권한 앱, 모든 독점 전체 화면 게임 위에 항상 보이는 동작은 제품이 보장하지 않아요. 이런 환경에서의 미표시를 일반 창 버그와 같은 기준으로 다루지 않아요.

## 수정 뒤에는 원인과 방지책을 남겨요

좋은 버그 수정 기록은 “무엇을 바꿨다”에서 끝나지 않아요. 어떤 경계에서 계약이 깨졌는지와 어떤 검사가 같은 문제의 재발을 막는지 설명해요.

- 원인: 이전 MSI 제거가 3010을 반환했는데 설치 관리자가 일반 실패로 처리했어요.
- 수정: 3010을 재시작 필요 상태로 분기하고 설치를 중단했어요.
- 방지: 설치 스크립트 계약 테스트가 해당 분기와 안내 문구를 확인해요.

이렇게 기록하면 다음 사람이 같은 증상을 만났을 때 구현 전체를 다시 추측하지 않아도 돼요.
