# Windows deployment layout

SIDEY는 사용자에게 보이는 진입점과 WinUI/.NET 실행 트리를 분리한 self-contained 배포를 사용합니다.

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
   ├─ System.*.dll                   # self-contained .NET 런타임
   ├─ Microsoft.*.dll                # Windows App SDK/WinUI
   ├─ <culture>/                     # WinUI MUI 리소스
   └─ Assets/                        # PRI/XAML 로더용 비공개 복사본
```

- 사용자는 루트 `SIDEY.exe`만 실행합니다. 런처는 모든 명령줄 인수를 `Runtime/SIDEY.Host.exe`로 전달하고 즉시 종료합니다.
- `Uninstall.exe`를 직접 실행하면 NSIS 제거 화면을 시작합니다. 설정·로그와 로그인 자격 증명 삭제 항목은 각각 기본 미선택이며 선택한 항목만 현재 사용자 프로필에서 삭제합니다. 업데이트와 복구에서는 이 정리를 실행하지 않습니다.
- 실제 프로세스는 `SIDEY.Host.exe`이므로 런처와 작업 관리자에서 구분할 수 있습니다.
- WinUI의 PRI 리소스는 호스트 파일 이름과 결합되므로 실제 앱은 빌드 단계부터 `SIDEY.Host`라는 어셈블리 이름을 사용합니다. 게시 후 EXE 이름만 바꾸면 안 됩니다.
- `Assets`는 사용자가 교체하거나 확인할 수 있는 SIDEY 콘텐츠입니다. WinUI XAML 로딩 호환성을 위해 같은 소형 자산 집합을 `Runtime/Assets`에도 복사합니다.
- `Langs`에는 SIDEY가 직접 관리하는 `ko-KR.json`, `en-US.json` 번역 카탈로그를 둡니다. WinUI 자체 `*.dll.mui` 폴더는 `Runtime` 내부에 유지합니다.
- 번역 키는 `onboarding.tagline` 같은 점 구분 경로를 사용합니다. XAML은 `{i18n:I18n Key=...}`, C#은 `I18n.Get(...)` 또는 `I18n.Format(...)`으로 같은 카탈로그를 참조합니다.
- Setup EXE는 게시 트리 전체를 설치하되 `*.pdb`와 Debug 온보딩 미리보기 명령은 제외합니다.
- 현재 배포 파이프라인은 자체 서명 인증서를 만들거나 SIDEY 파일에 자체 서명을 추가하지 않습니다. 공급자 런타임 파일의 기존 서명은 유지합니다.
- 사용자 설정, 자격 증명과 메시지 상태는 Program Files가 아니라 Windows 사용자 프로필 또는 Credential Manager에 유지하며 일반 제거의 데이터 삭제 옵션을 선택한 경우에만 함께 삭제합니다.

`Runtime`은 하나의 검증된 실행 단위입니다. 내부 DLL을 개별 교체하는 플러그인 ABI나 독립 업데이트 경계로 취급하지 않습니다.
