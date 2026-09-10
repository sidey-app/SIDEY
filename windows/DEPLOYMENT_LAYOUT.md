# Windows deployment layout

SIDEY는 사용자에게 보이는 진입점과 앱 실행 트리를 분리한 framework-dependent 배포를 사용합니다. .NET 10 x64 Runtime과 Windows App Runtime은 Microsoft 공유 런타임을 사용하며 설치 파일에 포함하지 않습니다.

```text
SIDEY/
├─ SIDEY.exe                         # 약 100KB의 공개 런처
├─ Uninstall.exe                     # NSIS 제거 프로그램
├─ SIDEY-Onboarding-Preview.cmd      # Debug 온보딩 미리보기
├─ Assets/
│  ├─ Icons/
│  ├─ Characters/
│  └─ Throwables/
├─ Langs/                            # SIDEY 자체 JSON 번역 리소스
│  ├─ ko-KR.json                     # 기본·한국어 카탈로그
│  └─ en-US.json                     # 영어 카탈로그
└─ Runtime/
   ├─ SIDEY.Host.exe                 # 실제 WinUI 프로세스
   ├─ SIDEY.Host.dll                 # 애플리케이션 본체
   ├─ Sidey.Core.dll
   ├─ Sidey.Infrastructure.dll
   ├─ Sidey.Overlay.dll
   ├─ Sidey.Platform.Windows.dll
   ├─ Sidey.Presentation.dll
   ├─ SIDEY.Host.deps.json
   ├─ SIDEY.Host.runtimeconfig.json
   ├─ Microsoft.WindowsAppRuntime.Bootstrap*.dll  # 공유 런타임 로딩
   ├─ Microsoft.WinUI.dll            # 관리 코드 projection (WinUI 본체 제외)
   ├─ Microsoft.*.Projection.dll     # 앱에서 참조하는 관리 코드
   └─ SIDEY.Host.pri                 # 컴파일된 XAML 리소스
```

- 사용자는 루트 `SIDEY.exe`만 실행합니다. 런처는 모든 명령줄 인수를 `Runtime/SIDEY.Host.exe`로 전달하고 즉시 종료합니다.
- `Uninstall.exe`를 직접 실행하면 NSIS 제거 화면을 시작합니다. 설정·로그와 로그인 자격 증명 삭제 항목은 각각 기본 미선택이며 선택한 항목만 현재 사용자 프로필에서 삭제합니다. 업데이트와 복구에서는 이 정리를 실행하지 않습니다.
- 실제 프로세스는 `SIDEY.Host.exe`이므로 런처와 작업 관리자에서 구분할 수 있습니다.
- WinUI의 PRI 리소스는 호스트 파일 이름과 결합되므로 실제 앱은 빌드 단계부터 `SIDEY.Host`라는 어셈블리 이름을 사용합니다. 게시 후 EXE 이름만 바꾸면 안 됩니다.
- `Assets`는 사용자가 교체하거나 확인할 수 있는 SIDEY 콘텐츠입니다. 제목 표시줄 아이콘도 설치 루트의 절대 파일 경로에서 읽으며 `Runtime/Assets`에는 복사하지 않습니다. 컴파일된 XAML/PRI만 호스트 옆에 유지합니다.
- `Langs`에는 SIDEY가 직접 관리하는 `ko-KR.json`, `en-US.json`, `ja-JP.json` 번역 카탈로그를 둡니다. WinUI 자체 리소스는 공유 Windows App Runtime에서 제공합니다.
- 번역 키는 `onboarding.tagline` 같은 점 구분 경로를 사용합니다. XAML은 `{i18n:I18n Key=...}`, C#은 `I18n.Get(...)` 또는 `I18n.Format(...)`으로 같은 카탈로그를 참조합니다.
- Setup EXE는 게시 트리 전체를 설치하되 `*.pdb`와 Debug 온보딩 미리보기 명령은 제외합니다.
- 현재 배포 파이프라인은 자체 서명 인증서를 만들거나 SIDEY 파일에 자체 서명을 추가하지 않습니다. 공급자 런타임 파일의 기존 서명은 유지합니다.
- 사용자 설정, 자격 증명과 메시지 상태는 Program Files가 아니라 Windows 사용자 프로필 또는 Credential Manager에 유지하며 일반 제거의 데이터 삭제 옵션을 선택한 경우에만 함께 삭제합니다.

`Runtime`은 하나의 검증된 실행 단위입니다. 내부 DLL을 개별 교체하는 플러그인 ABI나 독립 업데이트 경계로 취급하지 않습니다.

설치기는 Windows 기본 PowerShell 5.1로 prerequisite를 확인합니다. 누락된 런타임만 Microsoft HTTPS 경로에서 내려받아 Microsoft Corporation 서명을 검증하고 무인 설치합니다. .NET은 10.0 정식 x64 런타임을 요구하며, Windows App Runtime의 Framework·Main·Singleton·DDLM은 버전과 아키텍처를 모두 확인합니다. NSIS의 관리자 권한으로 Main·Singleton·DDLM의 모든 사용자 provisioning도 완료합니다. 실패·취소·재시작 필요 시 기존 SIDEY 종료나 제거를 시작하지 않습니다.

prerequisite가 준비되면 기존 NSIS/MSI 제거기를 실행하고 SIDEY 설치 폴더의 `Runtime` 잔여 파일을 정리한 뒤 새 payload를 설치합니다. 이 정리는 junction/symlink를 거부하며 시스템 공유 런타임과 사용자 데이터는 건드리지 않습니다. 일반 SIDEY 제거 역시 공유 .NET / Windows App Runtime을 제거하지 않습니다.

`prerequisites.json`은 런타임 버전·공식 URL을 고정합니다. SDK 변경 시 함께 갱신해야 합니다. `scripts/windows/Test-FrameworkDependentPublish.ps1`은 복원한 SDK 메타데이터와 버전·패키지 identity를 대조하고, Microsoft framework MSIX에 들어 있는 모든 DLL과 .NET 런타임 본체·설치기가 publish에 없는지 검사합니다. SDK 2.4에서 별도 복사되는 ML native DLL은 앱 publish target에서 제외합니다.

설치 검증에는 런타임 없는 신규 설치, 기존 런타임으로 오프라인 설치, 다운로드/서명/설치 실패, 재시작 요구, self-contained NSIS/MSI 업그레이드, 동일 버전 복구, 일반 제거 후 공유 런타임 보존, 다른 관리자 계정으로 승격한 설치 후 원래 사용자 실행을 포함합니다. 자동 테스트는 prerequisite 상태 전환·정리 경계·NSIS 호출 순서와 publish/런처 스모크를 검증하며, 관리자 설치 UI 시나리오는 별도 실기 검증 대상입니다.

설치기는 영어·한국어·일본어·중국어 간체/번체·러시아어·우크라이나어를 제공합니다. 환영 화면 전의 언어 선택창은 시스템 표시 언어를 맨 위에 두고 나머지를 영어 언어명 알파벳순으로 표시합니다. 저장된 선택은 업데이트의 기본 선택 및 제거 UI에서 재사용합니다. 미지원 시스템 언어에서는 전체 알파벳순 목록과 영어 기본 선택을 사용합니다. 언어 선택 도우미는 Windows 기본 .NET Framework로 빌드해 NSIS 임시 폴더에서만 실행하며 .NET 10 설치 전에도 동작합니다. NSIS 기본 화면 번역과 `installer/Sidey.Setup/Languages.nsh`의 SIDEY 문구를 사용하고, 약관 본문은 기존 한국어 원문을 유지합니다.

언어 선택창은 확인 시 설치기 프로세스에 foreground 권한을 넘기며, 설치기는 GUI 초기화 시 창을 앞으로 표시합니다. `scripts/windows/tests/Test-InstallerLanguageUi.ps1 -SelectorExecutablePath <빌드된 Sidey.SetupLanguage.exe>`는 대화형 데스크톱에서 실제 언어 선택과 환영 화면 전환을 검증합니다. 제품의 시작 함수를 사용하는 별도 NSIS 테스트 창에서 Enter 입력 후 표시·최소화·foreground 상태를 확인하며, 앱 설치·제거 및 관리자 권한 요청은 수행하지 않습니다.

언어 선택창의 UI는 빌드에 사용하는 NSIS `LangDLL.dll`의 원본 대화상자 리소스를 재사용합니다. 기존 `Installer Language` 제목, 영어 안내·버튼, 왼쪽 앱 아이콘과 배치를 유지하고 목록에는 각 언어의 고유 이름만 표시합니다. 원본 리소스만 도우미에 포함하고 `CB_INSERTSTRING`으로 순서를 지정하므로, 별도의 WinForms UI나 런타임용 NSIS DLL 사본은 필요하지 않습니다.
