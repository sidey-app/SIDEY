# SIDEY 제품 기획서

- 문서 버전: 0.8
- 최종 갱신: 2026-09-02
- 상태: macOS `v1.0.3`(build 14) 정식 공개, 그 위에 상점·Google 연결·별빛 우파루파 개발, Windows 네이티브 `v1.0.3` 정식 출시
- 현재 대상 플랫폼: macOS 26 이상 Apple Silicon, Windows 11 25H2 이상 x64
- 통합 브랜치: `main`; 작업 브랜치: `macos/*`, `windows/*`, `shared/*`

## 1. 제품 정의

`SIDEY`는 최대 12명의 가까운 친구가 2D 픽셀 동물로 사용자의 화면 가장자리에 머물며 상태, 타이핑, 짧은 메시지를 보여주는 초대 전용 데스크톱 ambient messenger다.

각 캐릭터는 실제 친구 한 명을 나타낸다. 공개 커뮤니티, AI 캐릭터, 가상 반려동물, 게임형 성장 시스템은 제품 범위가 아니다. 제품명은 항상 `SIDEY`를 사용한다.

핵심 가치는 다음 세 가지다.

- 별도 채팅창을 계속 열지 않아도 친구의 존재와 상태가 보인다.
- 짧은 메시지가 캐릭터의 말풍선으로 자연스럽게 나타난다.
- 평소에는 뒤 애플리케이션의 클릭과 작업 흐름을 방해하지 않는다.

## 2. 현재 범위와 제외 범위

### 2.1 현재 macOS slice

- macOS 네이티브 클라이언트는 현재 정식판 기준 구현으로 유지한다.
- 현재 내장 픽셀 동물 5종을 제공한다.
- 실제 그룹은 최대 12명이다. 렌더러 안정성은 별도 20노드 합성 스트레스 테스트로 검증한다.
- macOS 코드·인증·설정 schema는 Windows 개발을 위해 재작성하지 않는다.
- 기존 설치의 인증 세션과 설정을 잃지 않도록 Swift 기반 legacy migration 호환만 유지한다.
- macOS 설정과 메뉴바에서 첫 유료 캐릭터 상점을 제공하고, 기존 익명 계정을 Google identity에 연결한 뒤 브라우저 결제를 시작한다.

### 2.2 Windows 구현 목표

- Windows 11 25H2(build 26200) 이상 x64 네이티브 클라이언트를 C#/.NET 10 LTS·WinUI 3·Win32로 구현한다.
- 일반 창은 SIDEY 브랜드의 Windows Fluent UI로 만들고, 투명 월드는 전용 Win32 HWND가 소유한다. 첫 기능 빌드부터 `PixelCharacterCatalog`와 하나의 `UpdateLayeredWindow` 렌더러가 무료 5종의 사전 생성 premultiplied BGRA frame을 표시한다.
- 햄스터 1종 실기 계측은 같은 5종 렌더러의 입력 snapshot을 제한하는 Debug 전용 내부 모드로 수행한다. 햄스터 전용 제품 구현을 만들거나 이 모드를 Release에 노출하지 않으며, 나머지 4종 구현을 계측 뒤로 미루지 않는다.
- 최종 목표는 macOS와 서버 계약·제품 행동이 동등한 Windows 판이며, 플랫폼 창·설정 UI는 Windows 관례를 따른다.
- Godot·WPF·Electron·WebView는 사용하지 않는다.

### 2.3 명시적 제외

- 승인된 catalog 상품 외의 추가 동물
- 모바일·웹 클라이언트
- 공개 그룹·검색·발견
- 12명을 넘는 그룹
- 이미지·파일 전송, 음성·영상 통화
- 사용자 업로드 아바타와 캐릭터 커스터마이징
- AI 동료

### 2.4 공식 다운로드 웹사이트

- 공식 주소는 GitHub 프로젝트 Pages `https://sidey-app.github.io/SIDEY/`다. 루트는 한국어, `/en/`은 영어이며 각 페이지에서 언어를 전환할 수 있다.
- `website/`의 정적 HTML·CSS·최소 JavaScript만 배포한다. 이 사이트는 제품 소개와 다운로드 안내만 담당하며 로그인·그룹·메시지 기능을 제공하는 웹 클라이언트가 아니다.
- macOS 기본 CTA는 현재 공개 버전의 고정 공증 DMG를 직접 가리키고 `brew install --cask sidey-app/tap/sidey`를 함께 제공한다. 다음 공개 릴리스에서는 버전 표기와 고정 DMG URL을 같은 배포 작업에서 갱신한다.
- Windows 기본 CTA는 현재 정식 버전의 고정 MSI를 직접 가리킨다. 저장소의 다운로드 버튼은 Release 검증 전까지 비활성 상태로 두고, Pages Actions가 정식 Release의 단일 MSI를 확인한 배포 아티팩트에서만 링크로 활성화한다.
- Windows 업데이트 채널은 macOS Release와 분리된 `windows-v<version>` 태그와 `website/windows-latest.json`을 사용한다. 호환 경로 `website/windows/update.json`은 같은 내용을 유지한다. 저장소 manifest의 `sha256`은 `null`로 두고, Pages Actions가 Release MSI를 다시 내려받아 계산한 64자리 SHA-256으로 두 배포 manifest를 완성한다. Release가 없거나 draft·pre-release이거나 MSI 외 자산이 있으면 기존 Pages를 교체하지 않는다.
- 첫 화면에서 플랫폼·아키텍처·정식 배포 상태를 밝히고, 개인정보 수집 경계, E2EE 미지원, 보안 화면·DRM·권한 상승 앱·모든 독점 전체화면 위 표시를 보장하지 않는다는 제한을 숨기지 않는다.
- `main`의 웹 파일 또는 Pages 워크플로가 바뀌면 GitHub Actions가 `website/`만 Pages artifact로 올리고 `github-pages` 환경에 배포한다. custom domain과 별도 Sites 호스팅은 사용하지 않는다.

### 2.5 공개 업데이트 문서와 향후 계획

- README는 짧은 제품 소개와 macOS·Windows 설치 안내를 유지하고, 그 아래에 플랫폼별 날짜·버전·최신 변경과 공통 향후 계획을 제공한다. 기술 스택·아키텍처·백엔드·개발·빌드 설명은 공개 README에 두지 않는다.
- `docs/releases/*`와 GitHub Release 본문은 일반 사용자가 체감하는 결과를 짧은 문장으로 설명한다. 설치 행동과 지원 환경, 데이터 위험처럼 사용자가 알아야 하는 내용은 유지하되 DB·schema·API·클래스·파이프라인 세부는 제외한다.
- 공개 향후 계획은 새로운 말풍선 디자인, Windows 기능 안정화, 캐릭터 드래그 앤 드롭, 캐릭터 효과음, macOS 이모지 입력 버그 개선, 다른 사람 캐릭터 클릭 이펙트다. 이는 완료 기능이나 일정 약속이 아니며 현재 MVP 범위를 바꾸지 않는다.
- 캐릭터 드래그 앤 드롭은 현재 제거된 기능으로 유지한다. 기본 클릭 통과와 명시적 상호작용 모드를 보존하는 별도 제품 결정과 입력 설계가 확정된 뒤에만 다시 구현한다.

## 3. 그룹과 계정

- 그룹은 초대 전용 비공개 방이다.
- 방당 최대 12명이며 서버 함수가 트랜잭션 잠금 안에서 제한한다.
- 사용자당 참여 가능한 방은 최대 5개다.
- 오버레이에는 한 번에 활성 그룹 하나만 표시한다.
- 닉네임은 줄바꿈 없는 2~8자로 제한한다. 닉네임과 캐릭터 선택은 같은 방에서 중복 가능하며 권한·식별은 UUID로 처리한다.
- 초대 코드는 128-bit 난수의 32자리 hex를 `8-8-8-8`로 표시한다. 방장이 재발급하기 전까지 유효하며 API 비노출 private schema에는 Vault pepper 기반 HMAC-SHA256만 저장한다. 보안 migration 전의 짧은 코드는 모두 비활성화하고 방장에게 재발급을 요구한다.
- 사용자·프로필·방·메시지는 RLS를 통과해야 한다.
- macOS 그룹 설정에서 모든 멤버는 기본 접힘 상태인 각 그룹 카드의 제목 영역 또는 오른쪽 끝의 좌우 10pt 여백을 둔 단일 화살표를 눌러 캐릭터·닉네임·`나` 표시를 펼쳐 볼 수 있다. 헤더 왼쪽 기본 disclosure 화살표와 별도 `…` 메뉴는 두지 않으며, 비활성 그룹 전환 버튼은 `그룹 참가`로 표시한다. 방장은 닉네임 바로 왼쪽의 금색 `crown.fill`로 표시하며 오버레이 이름표에는 왕관을 넣지 않는다.
- 현재 `owner_id`인 방장만 펼친 멤버 목록 아래의 그룹 이름 변경·그룹 삭제 버튼과 본인을 제외한 멤버의 추방 버튼을 볼 수 있다. 이름은 앞뒤 공백을 제거한 줄바꿈·탭 없는 1~20자이며, 추방은 대상 닉네임을 표시한 확인을 거친다. 삭제는 멤버와 모든 메시지가 영구 삭제된다는 파괴적 2단계 확인을 거친 hard delete다.
- macOS 그룹 작업은 `idle / creating / joining / switching(UUID)`로 모델링한다. 생성 버튼은 `만드는 중…`, 코드 참여 버튼은 `참여 중…`, 전환 대상 카드는 스피너와 `연결 중…` 및 accent 배경·테두리를 표시한다. 전환 중에는 다른 그룹 선택만 계속 허용하고 생성·삭제·이름 변경·추방 같은 mutation은 차단한다.
- 그룹 선택은 150ms 동안 합쳐 마지막 대상만 남기며 이미 시작한 네트워크 작업은 직렬 실행한다. 최종 대상 Presence와 해당 `roomID`의 최근 메시지 조회가 모두 성공하기 전에는 현재 활성 그룹과 기록을 유지한다. 이전 요청의 성공·실패는 UI에 적용하지 않고, 최종 실패 시 이전 활성 그룹 Presence를 복구하며 복구도 실패한 경우에만 Realtime 연결 오류로 전환한다.
- 관리 권한은 클라이언트 표시 여부와 별개로 서버 RPC에서 다시 검증한다. 활성 그룹이 추방·삭제로 사라지면 composer·typing·말풍선을 정리하고 가장 오래된 남은 그룹을 활성화한다. 마지막 그룹이 사라지면 오버레이를 숨기고 기존 프로필을 유지한 그룹 참여 화면으로 돌아간다.
- macOS는 익명 인증과 기존 세션 복구 정책을 유지한다. 복구 실패를 새 익명 계정 생성으로 조용히 덮어쓰지 않는다.
- Windows는 저장된 Supabase 익명 세션을 먼저 복구하고, 세션이 없는 신규 설치에서만 새 익명 계정을 만든다. access·refresh token과 평문 초대 코드는 Windows Credential Manager에 보관하며 Google OAuth·PKCE·callback은 사용하지 않는다.
- Windows와 macOS의 서로 다른 사용자 UUID가 같은 방에 참가하는 것을 지원하며, Mac↔Windows 계정 이전은 범위 밖이다.

## 4. 픽셀 월드

### 4.1 활동 영역

활동 영역 `activityFrame`은 선택한 모니터의 `visibleFrame`에 붙으며 기본 깊이는 240pt이고 작은 화면에서는 visible frame 세로 길이의 1/3을 넘지 않는다. 캐릭터의 발은 화면 경계의 1차원 track에 고정되고, 이동·영역 프리셋·말풍선 접선 보정은 이 frame만 기준으로 계산한다.

SpriteKit 장면과 투명 월드 패널은 리액션 전용 `renderFrame`을 사용한다. render frame은 화면 안쪽 깊이를 최대 360pt까지 확보하고 activity frame의 접선 양쪽에 최대 144pt씩 여유를 더하되 `visibleFrame`을 넘지 않는다. 패널 크기는 리액션 여부와 무관하게 고정하며 hotspot은 render frame 원점 기준 로컬 좌표를 화면 좌표로 변환한다. 물리적인 화면 끝에서는 확대가 OS 경계만큼 잘릴 수 있지만 기존 240pt 앱 창 때문에 잘리지는 않게 한다.

설정은 다음 12개 조합을 제공한다.

| 축 | 선택값 |
| --- | --- |
| 가장자리 | 하단, 좌측, 우측, 상단 |
| 길이 | 1/3, 1/2, 전체 |

짧은 띠는 해당 가장자리의 중앙에 배치한다. 기본값은 `하단·전체`다. 하단·상단에서는 가로 접선 좌표만, 좌측·우측에서는 세로 접선 좌표만 변한다. 모든 스프라이트 프레임의 최저 불투명 발 픽셀은 실제 화면 경계 0pt에 1pt 이내로 맞춘다. 캐릭터·닉네임·상태 점·말풍선은 발이 가장자리를 향하도록 함께 회전한다.

월드와 입력창은 선택한 모니터 한 대에만 표시한다. 저장한 모니터가 제거되면 주 화면으로 복귀하고 새 식별자를 설정에 저장한다. 메뉴바와 Dock을 포함하는 전체 frame이 아니라 visible frame만 사용한다.

### 4.2 멤버와 상태

활성 그룹의 모든 멤버와 내 캐릭터를 기본 표시한다. 오프라인 멤버는 설정에서 숨길 수 있다.

| 논리 상태 | 행동 | 점 색상 |
| --- | --- | --- |
| 온라인 | 산책 또는 idle | 초록 |
| 자리 비움 | 선 채 눈을 감고 고개를 떨어뜨리는 졸기, 고정 14pt 주황 `Zzz`와 약 2pt 어두운 외곽선·0.55↔1 alpha·3pt 부유 유지, 원래 채도 | 주황 |
| 오프라인 | 옆으로 웅크린 잠, 저채도, 약 75% 불투명도 | 빨강 |
| 재연결 | 정지 | 회색 |

타이핑은 캐릭터 모션을 바꾸지 않는다. `TypingIndicatorNode`가 `.` → `..` → `...`을 0.35초 간격으로 반복한다. 같은 캐릭터에 실제 메시지 말풍선이 있으면 타이핑 action을 중단하고 메시지를 우선하며, 메시지 만료 뒤 여전히 타이핑 중이면 점 애니메이션을 다시 시작한다. 클라이언트는 Broadcast에 직접 쓰지 않고 인증 RPC가 방·epoch·사용자·event·rate를 검증한 뒤 ephemeral topic에 발행한다.

자리 비움이 해제되면 부유·alpha action을 취소한다. `Zzz` 글자 수는 상태가 유지되는 동안 순환하지 않는다.

닉네임 상태 점은 고정 x 좌표를 사용하지 않는다. 실제 닉네임 label frame의 왼쪽에서 점 반지름과 5pt 간격만큼 떨어진 위치를 계산해 최대 8자 이름과 `· 나` 표식에서도 겹치지 않게 한다. 흰색 닉네임 뒤에는 여백이 있는 반투명 검정 캡슐을 렌더하며, 뒤 애플리케이션의 실제 픽셀은 읽지 않는다.

내 캐릭터를 더블클릭하면 캐릭터 스프라이트만 발 위치를 기준으로 7배까지 0.20초 동안 커지고 0.60초 동안 원래 크기로 복귀한다. 닉네임·상태 점·말풍선은 확대하지 않는다. 로컬에서 즉시 재생한 뒤 같은 방에 이벤트 UUID와 사용자 UUID를 담은 `character_pulse` Broadcast를 보내며, 송신·수신 모두 캐릭터별 1초 쿨타임을 적용한다. 동일 이벤트 UUID는 한 번만 재생한다.

### 4.3 이동

- 각 캐릭터는 선택한 가장자리와 평행한 1차원 track의 로컬 랜덤 목적지를 향해 산책하고 간헐적으로 idle 한다.
- 일반 산책 속도는 최대 22pt/s다.
- 캐릭터끼리 부드럽게 회피하되 강한 충돌 물리나 순간이동을 사용하지 않는다.
- 캐릭터가 겹치면 idle을 즉시 끝내고 진행을 방해하는 분리력은 제거한 뒤 목표 방향으로 잠시 가속해 빠르게 통과한다.
- 실제 메시지 말풍선 본문이 접선 방향으로 겹치면 두 발신자의 idle을 즉시 끝내고 반대 방향으로 240pt/s² 분리 가속한다. 최대 속도는 72pt/s이며 본문 사이에 최소 8pt 여유가 생길 때까지 분리 상태를 유지한다.
- 말풍선 충돌이 해소되면 즉시 22pt/s 제한과 기존 산책 목표로 복귀한다. 타이핑 `.`·`..`·`...` 말풍선은 이동 충돌 계산에서 제외한다.
- 한쪽이 track 끝이나 정지 상태라 해당 방향으로 움직일 수 없으면 그 쌍의 남는 힘을 전체 분리 방향을 뒤집지 않는 범위에서 움직일 수 있는 상대에게 배분한다. 둘 다 움직일 수 없으면 현재 위치를 유지한다.
- 3~4개 말풍선이 동시에 겹치면 충돌 진입 시의 1차원 순서를 유지하며 모든 충돌 쌍의 분리력을 합산한다. 속도 상한과 track 범위를 우선하며 공간이 부족하면 일부 겹침을 허용한다.
- 상단 월드에서는 입력창이 실제로 열려 있을 때만 상단 중앙의 440×76 영역을 우선 회피한다.
- 공간이 부족해도 설정이나 월드 크기를 자동 변경하거나 순간이동하지 않는다.
- 실제 메시지 말풍선이 떠 있어도 온라인 발신자는 이동을 계속하며, 말풍선과 꼬리가 위치를 추적한다.
- 좌표는 네트워크로 보내지 않는다.
- 설치 seed, room UUID, user UUID로 안정적인 초기 위치를 만들고 UUID diff로 기존 노드의 위치를 보존한다.

### 4.4 내장 캐릭터 에셋

다음 5종을 제공한다. 같은 그룹에서 닉네임과 캐릭터 선택은 중복 가능하며 UUID가 실제 식별자다. `minty_pup`과 알 수 없는 ID는 클라이언트 호환을 위해 햄스터로 표시한다.

| ID | 표시명 | 기본 팔레트 |
| --- | --- | --- |
| `pixel_hamster` | 아기 햄스터 | 골든·크림·페리윙클 |
| `pixel_cat` | 아기 고양이 | 스모크 그레이·크림·라일락 |
| `pixel_puppy` | 아기 강아지 | 캐러멜·크림·스카이 블루 |
| `pixel_rabbit` | 아기 토끼 | 아이보리·피치·라벤더 |
| `pixel_penguin` | 아기 펭귄 | 네이비·크림·민트 |

첫 유료 catalog 상품은 `pixel_starlight_upalupa` 별빛 우파루파다. macOS 선택 목록에는 무료 5종과 현재 계정이 활성 소유권을 가진 유료 캐릭터만 표시한다. 환불 또는 소유권 만료 시 로컬 선택을 햄스터로 되돌리며, macOS에서 다른 사용자의 유료 캐릭터를 렌더링할 때는 보는 사람의 소유권을 요구하지 않는다. 이번 Windows 릴리스는 별빛 우파루파 ID를 원격 렌더링하지 않고 기존 안전한 fallback을 사용한다.

- 논리 프레임: 24×24 픽셀
- 화면 크기: 2배 정수 확대, 약 48pt
- 필터: nearest-neighbor
- 팔레트: 위 표의 종별 기본 팔레트를 사용하며, 공통 픽셀 명암 규칙을 유지한다.
- 애니메이션: idle 2프레임, walk 4프레임, doze 2프레임, offline curled sleep 2프레임
- 실시간 그림자와 3D 런타임 없음

원본 콘셉트 이미지는 `docs/assets/pixel_<species>_concept.png`, 런타임 시트는 `macos/SIDEY/Resources/Characters/Pixel<Species>/pixel_<species>.png`에 둔다. 모든 시트는 결정적 Swift 생성기와 240×24 RGBA·10프레임·발 기준선·hash 검증으로 관리한다.

## 5. 메시지와 타이핑

### 5.1 데이터 흐름

- Postgres가 메시지 원본이다.
- 메시지는 생성 후 7일이 지나면 서버의 일일 정리 작업으로 영구 삭제한다.
- Presence는 연결·온라인·자리 비움 상태에 사용한다.
- Broadcast는 SIDEY 입력창의 타이핑과 `character_pulse`처럼 저장하지 않는 이벤트, 그리고 서버가 발행하는 DB 변경 식별자에만 사용한다. 클라이언트 직접 발행은 Presence만 허용한다.
- 각 방은 멤버 변경마다 증가하는 `realtime_epoch`을 가지며 DB·ephemeral private topic을 분리한다. DB event에는 message UUID와 operation만 담고, macOS는 RLS를 거쳐 해당 row를 재조회한 뒤 확정한다.
- macOS 클라이언트는 5초마다 WebSocket과 각 방 채널의 실제 구독 상태를 확인한다. 비정상이 8초 이상 지속되면 채널 및 수신 스트림을 재생성하고, 실패가 이어지면 8초·16초·최대 30초 간격으로 재시도한다.
- 재구독 중에는 로컬 상태를 재연결로 표시한다. 성공하면 현재 Presence를 다시 publish하고 방·멤버 snapshot과 최근 메시지를 다시 읽어 단절 중 누락된 가입·메시지를 보정한다.
- confirmed message ledger는 `senderID`를 보존하며 방별 최근 50개·7일 범위로 제한한다. pending·failed 전송은 방별 outbox에 분리한다.
- macOS 최근 기록은 최신순 카드 목록이며 각 카드에 40pt 슬롯 안의 24×24 무배율 픽셀 캐릭터, 닉네임·`나` 표식, 로컬 시각, 본문과 pending·failed 상태를 표시한다. 발신자 UUID가 현재 방 멤버 snapshot에 없으면 햄스터와 `알 수 없는 친구`로 표시한다.
- 최근 기록의 최초·추가 조회는 RLS가 적용된 `messages`를 `created_at DESC, id DESC`로 51개 읽어 50개를 표시하고, 마지막 표시 row의 원본 `created_at` 문자열과 UUID를 keyset cursor로 사용한다. 하단 도달 시 자동으로 다음 페이지를 가져오며 서버 보관 정책과 같은 최근 7일 cutoff를 모든 조회에 적용한다.
- Postgres `created_at`은 소수 초 유무와 `Z` 또는 `+00:00` 같은 UTC offset이 있는 ISO-8601을 엄격히 해석한다. 기록 표시는 기존처럼 사용자 로컬 시간을 사용하고, 해석 실패를 현재 시각으로 대체하지 않으며 기술 오류로 노출한다.
- 클라이언트가 UUID와 원래 `roomID`로 메시지를 낙관적으로 표시하고 동일 UUID의 저장·Realtime 결과와 중복 제거한다.
- 확정 여부가 애매한 네트워크 실패는 같은 UUID를 RLS로 조회하고 같은 UUID로 한 번 재시도한다. 최종 실패는 원래 방 outbox에만 남기며 다른 방의 draft를 덮지 않는다.

### 5.2 말풍선 규칙

- 발신자별 최신 실제 메시지 하나만 표시한다.
- 동시에 실제 메시지는 최대 네 명까지 표시한다.
- 다섯 번째 발신자가 메시지를 보내면 가장 오래된 말풍선을 닫는다.
- 기본 표시 시간은 10초다.
- 실제 메시지가 보여도 온라인 발신자의 이동은 멈추지 않는다.
- 기록 조회나 서버 snapshot 복원은 과거 말풍선을 다시 재생하지 않는다.
- 본문은 실제 문자열을 측정해 최대 220pt 폭으로 줄바꿈하며 200자·3줄 입력을 생략하지 않는다.
- 프리셋 접선 길이가 짧으면 최대 폭을 `길이 - 16pt`로 줄여 다시 측정한다.
- 캐릭터가 가장자리 끝에 도달해도 순간이동시키지 않는다. 말풍선만 접선 방향으로 보정한다.
- 메시지와 타이핑 말풍선에는 삼각형 꼬리가 있으며, 보정 뒤에도 꼬리 끝은 발신자 캐릭터를 가리킨다.
- 실제 메시지 본문 frame만 이동 충돌 범위로 사용하고 타이핑 말풍선은 제외한다.
- 충돌을 해결하기 위한 추가 줄 올림, 본문 축약, 오래된 메시지 조기 제거는 하지 않는다.

### 5.3 조용히 모드와 미확인 수

조용히 모드는 새 메시지 본문 말풍선을 표시하지 않는다. 비활성 방과 조용히 모드에서 받은 메시지는 그룹별 미확인 수에 반영한다. 타이핑 순환 점은 본문이 아니므로 계속 표시한다.

## 6. 창과 조작 정책

### 6.1 macOS 월드 창

- 투명하고 테두리가 없으며 일반 앱 위에 떠 있다.
- 전체 월드 영역은 항상 `ignoresMouseEvents`로 뒤 애플리케이션에 클릭을 통과시킨다.
- 숨길 때 SpriteKit 렌더링과 장면 업데이트를 정지한다.
- 보안 화면, DRM 앱, 권한이 더 높은 앱, 모든 독점 전체화면 게임 위 표시는 보장하지 않는다.

### 6.2 입력창

- 선택 모니터의 `visibleFrame` 상단 중앙, 노치·메뉴바 아래 10pt에 400×56으로 고정한다. 노치가 없는 화면에서도 같은 상단 여백을 사용한다.
- 왼쪽 `×` 닫기 버튼, `메시지를 입력해 주세요` placeholder가 있는 텍스트 입력, 오른쪽 전송 버튼만 제공한다.
- 이 패널만 키보드 포커스와 포인터 입력을 받는다.
- 패널의 둥근 glass 영역 밖과 hosting surface는 포커스 여부와 무관하게 완전 투명하며 400×56 사각 배경을 그리지 않는다.
- 최대 200자·3줄, Enter 전송, Shift+Enter 줄바꿈 계약을 유지한다.
- `NativeMessageField`의 텍스트 컨테이너는 입력 폭을 추적하고 문서 높이는 실제 자동 줄바꿈 결과만큼 확장한다. 명시적 줄바꿈 3줄 제한은 `MessageValidator`가 유지하며 시각적 자동 줄바꿈을 3줄에서 잘라내지 않는다.
- 한 시각 줄은 세로 중앙 정렬하고 여러 시각 줄은 3pt 상단 inset과 숨겨진 세로 스크롤을 사용한다. 일반 입력·삭제, 한글 IME 확정, Shift+Enter, 방향키·Home·End·마우스 선택, undo·redo, 외부 draft 복원과 전송 실패 재표시 뒤 선택·삽입 커서를 자동으로 보이는 영역에 스크롤한다.
- 스크롤 상태는 `NativeMessageField`와 내부 `NSTextView`만 소유하고 `AppModel.draft`에는 추가하지 않는다. 유효성 실패로 마지막 정상 문자열과 선택을 복구한 뒤에도 복구 커서를 표시하며 가로 무한 확장은 사용하지 않는다.
- 앱 실행과 오버레이 표시 직후에는 숨겨져 있다.
- 내 캐릭터 단일 클릭 또는 메뉴바 `메시지 작성`으로 열고 즉시 포커스한다.
- 내 캐릭터 더블클릭은 리액션을 실행하고 입력창은 열린 상태로 유지한다.
- 캐릭터 또는 입력 패널 클릭으로 앱이 활성화될 때는 수동 앱 재열기로 처리하거나 설정창을 열지 않는다.
- 왼쪽 `×`, 내 캐릭터 재클릭, Esc 또는 입력창 외부 클릭은 draft를 보존하고 닫으며 `typing_stop`을 보낸다. 외부 클릭은 전역 마우스 이벤트나 좌표를 수집하지 않고 입력 패널의 키 포커스 상실로 판정한다.
- 유효한 메시지를 전송하면 입력창을 유지하고 마지막 전송 시점부터 5초 뒤 자동으로 닫는다. 5초 안에 다시 전송하면 타이머를 갱신한다.
- 낙관적 전송 실패 시 예약 닫힘을 취소하고 실패 항목을 원래 방 outbox에 보존한 뒤, 그 방이 아직 활성 방이면 입력창을 열어 포커스한다. 현재 draft는 실패 본문으로 덮지 않는다.
- 오버레이 숨김, 활성 방 전환, 현재 사용자 노드 제거 시 입력창을 닫는다.

월드 패널 전체는 `ignoresMouseEvents`로 클릭을 통과시킨다. 내 캐릭터 위의 52×52pt 투명 `NSPanel`만 최대 15Hz·1pt 임계값으로 위치를 따라가며 메시지·리액션 클릭을 받는다. 전역 마우스 좌표와 전역 이벤트 모니터는 사용하지 않는다.

오버레이 영역 자체의 자유 이동·크기 조절·잠금, 캐릭터 직접 드래그, 오버레이 내부의 최근 기록·설정 버튼은 제거한다. 최근 기록은 메뉴바에서 여는 일반 레벨의 macOS 창으로 제공하며 최초 로딩·빈 기록·오류와 재시도, 추가 페이지 로딩·오류와 재시도를 서로 구분한다. 방 전환을 시작하면 보던 목록을 즉시 초기화해 전환 대상 방을 조회하고, 창을 닫으면 진행 중 요청을 취소하고 적재한 페이지를 해제한다.

### 6.3 메뉴바

상태 아이콘은 18×18 1x·36×36 2x 픽셀 햄스터 얼굴 template image다. 읽지 않은 메시지가 있으면 우측 상단 원형 표시가 포함된 unread variant를 사용한다. 접근성 설명과 tooltip에도 unread 상태를 반영하며 전용 이미지 로딩 실패 시에만 `pawprint.fill`을 사용한다.

메뉴바에는 다음 항목만 둔다.

- 오버레이 표시·숨김
- 메시지 작성
- 활성 그룹과 그룹별 미확인 수
- 조용히 모드
- 최근 기록
- 꾸미기·상점
- 그룹 설정
- 로그인 시 실행
- 업데이트 확인
- 설정
- 종료

### 6.4 macOS 꾸미기·상점

- 설정과 메뉴바의 `꾸미기·상점`은 같은 화면을 열고 판매 상품을 등록 순서대로 2열 그리드에 표시한다.
- 화면에는 외부 상점 섹션 카드와 별도의 미리보기 카드 배경을 두지 않고 `StoreProductCard` 한 단계만 사용한다.
- 각 상품 카드는 최대 210pt의 배경 없는 미리보기 영역 안에 96pt 캐릭터를 최대 1.45배로 표시한다. 좌상단에는 상태 배지, 우상단에는 `hand.tap` 아이콘 미리보기 버튼을 overlay하며 버튼은 보이는 텍스트 없이 접근성 라벨과 도움말을 제공한다.
- 이름과 서버 가격은 같은 행에 배치하고 설명·오류·상태별 구매 action을 아래에 둔다. `1회 구매`, 카드별 `부가세 포함`, 텍스트 `반응 미리보기`, 소유권 배지와 중복되는 비활성 `보유 중` 버튼은 표시하지 않는다.
- 공통 안내는 상품 그리드 아래 가변 여백 다음에 가로 중앙 정렬한다. 내용이 짧으면 설정 상세 영역 하단, 창이 작으면 카드와 겹치지 않는 스크롤 끝에 표시한다.
- 공통 안내는 부가세 포함·Google 연결 필요, 결제 승인과 서버 소유권 확인 뒤 즉시 디지털 사용권 제공 시작, 제공 시작 뒤 단순 변심 청약철회 제한, 미제공·계약 불일치·중복 또는 무단 결제 등 법정 사유 전액 환불을 한 번만 전달한다.
- 카드별 미리보기 scale·effect generation·취소 가능한 Task는 `StoreProductCard`가 소유하고 상품 ID별 정렬된 서버 상태와 구매 action은 `AppModel`·`AppCoordinator`·`SideyBackend`가 소유한다.

### 6.5 Windows 창과 트레이

- 월드는 WinUI XAML 창에 투명 표현을 위임하지 않고 `WS_POPUP` 기반 전용 Win32 HWND가 소유한다. 무료 5종은 24px 원본에서 정수 nearest-neighbor로 미리 만든 premultiplied BGRA frame을 같은 `UpdateLayeredWindow` 렌더러로 표시하며 tick마다 bitmap이나 surface를 새로 할당하지 않는다.
- 월드 HWND는 작업 표시줄·Alt-Tab에 나타나지 않고 활성화되지 않으며 외부 앱으로 포인터를 통과시킨다.
- 내 캐릭터 상호작용 52×52 hotspot은 별도 HWND가 소유하고 최대 15Hz·1 DIP 임계값으로 위치를 갱신한다. 전역 마우스 hook·전역 좌표 수집은 금지한다.
- composer는 400×56 DIP 별도 WinUI 창이며, 내 캐릭터 클릭·트레이 `메시지 작성`만 이 창을 활성화한다.
- 트레이 메뉴는 macOS 메뉴바의 제품 행동에 맞춰 오버레이, 메시지 작성, 활성 그룹, 조용히 모드, 최근 기록, 상점, 그룹 설정, 로그인 실행, 업데이트 확인, 설정, 종료를 제공한다. 익명 세션을 사용하는 Windows판에는 로그아웃 메뉴를 두지 않는다.
- 앱은 Pages의 Windows 전용 manifest를 시작 시 한 번 확인하고 트레이·설정에서 수동 확인도 제공한다. 새 버전의 고정 GitHub Release MSI URL과 SHA-256이 모두 유효할 때만 사용자 승인을 받아 내려받고 hash 검증 뒤 설치기를 실행하며 무인 자동 설치는 하지 않는다.
- 시작 단계와 예외 유형·HRESULT·stack은 `%LOCALAPPDATA%\SIDEY\Logs\startup.log`에 기록하되 token·메시지 본문·평문 초대 코드는 기록하지 않는다. WinUI 창 생성 전 실패하면 네이티브 오류창으로 로그 경로를 알리고, 트레이 아이콘 초기화만 실패한 경우 설정창은 계속 유지하며 창을 닫으면 앱을 종료한다.
- 보안 화면·DRM·관리자 권한 앱·모든 독점 전체화면 위 표시는 보장하지 않는다.

## 7. 클라이언트 구조

### 7.1 소유권

`PixelWorldScene`이 다음 렌더링 상태를 단독 소유한다.

- 캐릭터 SpriteKit 노드와 애니메이션
- 현재 위치·속도·로컬 목적지
- 닉네임과 상태 점
- 타이핑·메시지 말풍선
- 입력창 및 캐릭터 상호 회피
- 타이핑 점과 상태 모션 frame
- 캐릭터 리액션의 이벤트 UUID 중복 제거와 발 기준 확대·복귀 action
- 캐릭터의 1차원 접선 좌표, 실제 메시지 말풍선 충돌 범위·분리 순서와 말풍선 꼬리 배치

`AppModel`은 다음 제품·서버 상태를 소유한다.

- 사용자, 방, 멤버 snapshot
- Presence와 타이핑 상태
- bounded confirmed message ledger, 방별 outbox와 active bubble 목록
- 오버레이 영역, 모니터, 오프라인 표시 등 환경설정
- 편집 중인 `selectedCharacterID`
- 연결 상태와 분리된 현재 `GroupOperation`
- 상품 ID별 commerce 상태, Google 연결 여부와 활성 소유권

macOS 최근 기록의 페이지·cursor·최초 및 추가 로딩 상태는 창 수명에 묶인 `MessageHistoryStore`가 소유한다. `AppModel`의 방별 50개 confirmed ledger와 outbox 계약은 바꾸지 않으며, 화면에 표시할 때만 페이지 결과·실시간 신규 메시지·pending·failed 항목을 UUID로 병합한다. `SideyBackend`는 RLS가 적용된 페이지 조회만 담당하고 offset이나 별도 서버 schema를 추가하지 않는다.

그룹 설정의 각 행은 펼침 여부, 이름 변경 draft, 삭제·추방 확인 대상과 초대 코드 복사 피드백을 로컬 UI 상태로 소유한다. 복사 성공 시 해당 행의 버튼만 초록 `checkmark.circle.fill`과 `복사 완료`를 3초 동안 표시하고, 3초 안 재클릭하면 타이머를 다시 시작하며 행 제거 시 취소한다. 성공 전역 배너는 표시하지 않고 실패만 기존 오류 배너를 사용한다. 실제 Keychain 읽기와 클립보드 처리는 `AppCoordinator`가 담당한다. 서버에서 읽은 방·멤버 배열을 행 상태로 복제하거나 mutation 성공을 가정해 임의 수정하지 않는다.

macOS 설정창은 `fullSizeContentView`를 유지하되 투명 커스텀 타이틀바 대신 AppKit 네이티브 타이틀바 머티리얼과 자동 구분선을 사용한다. 스크롤 콘텐츠가 상단 타이틀바 뒤에 들어가면 시스템 재질이 해당 영역을 블러 처리한다. 온보딩의 캐릭터 선택은 4열로 배치하고 다섯 번째 항목부터 다음 줄에 표시한다. 설정 상세 화면은 가로 44pt·세로 40pt 바깥 여백과 카드 안 24pt 여백을 사용한다. 각 섹션은 아이콘·제목·설명을 카드 위에 표시하고, 카드는 `Color.primary.opacity(0.025)` 기반 배경과 각각 약 0.05·0.025의 테두리·그림자를 사용한다. 카드의 토글·선택 항목은 왼쪽 제목 아래 효과 설명과 240pt 오른쪽 컨트롤 영역을 한 행으로 대응시키며 Picker·버튼·토글의 보이는 오른쪽 끝을 맞춘다. 토글은 macOS 26 네이티브 switch를 유지하고 개발 세부 정보인 `동작 정보`는 표시하지 않는다. 그룹 화면은 폭이 짧은 `person.2` 아이콘을 사용하고 현재 그룹, 새 그룹 만들기, 초대 코드로 참여를 독립 카드로 구성하며 각 카드는 기존 `AppModel` 상태와 `SettingsActions` mutation만 호출한다.

닉네임 저장 버튼은 현재 macOS 필드 에디터에 한글 IME 조합 문자열이 남아 있으면 이를 먼저 확정하고 포커스를 내린 뒤 다음 메인 런루프에서 `SettingsActions.onSaveProfile`을 호출한다. 온보딩과 일반 프로필 설정 모두 같은 순서를 사용해 마지막 조합 글자가 누락되지 않게 한다.

Presence나 snapshot을 적용할 때 UUID 기준으로 추가·갱신·삭제하며 존재하는 캐릭터 노드의 위치를 초기화하지 않는다.

`OverlayWindowGroup`은 composer 표시 상태와 내 캐릭터 단일·더블클릭 패널을 소유한다. `AppCoordinator`는 `character_pulse` 송수신과 캐릭터별 1초 쿨타임을 소유한다. `AppModel`에는 화면 좌표나 애니메이션 frame을 저장하지 않는다.

`AppCoordinator`의 방 전환 파이프라인은 150ms 마지막 선택 우선 처리, 직렬 네트워크 실행, 최종 대상 메시지의 명시적 `roomID` 조회, 성공 뒤 활성 그룹·기록 commit, 최종 실패 rollback을 소유한다. `SideyBackend`는 epoch별 DB·ephemeral Realtime 채널, bounded 수신 stream, Presence publish와 자동 복구 watchdog을 소유한다. snapshot·복구·방 전환이 요청하는 Presence는 하나의 직렬 publication queue가 최신 전체 방 상태로 coalesce해 동시에 `track`하지 않는다. generation별 복구가 snapshot·활성 방 최근 메시지를 모두 맞춘 뒤에만 online을 확정하고, 사라진 그룹의 채널과 이 기기의 Keychain 초대 코드를 정리한다.

### 7.2 환경설정

Codable 계약은 다음과 같다.

```swift
OverlayRegionPreference(
    edge: OverlayEdge,
    span: OverlaySpan,
    screenIdentifier: String?
)
```

환경설정 schema 7은 기존 Keychain 전환 완료 여부를 추가한다. schema 6 이하 파일은 닉네임·방·오버레이 등 기존 값을 유지하면서 전환 미완료로 읽고, 새 설치 기본값은 완료 상태로 시작한다. 과거 frame, lock, scale, screen 값은 디코딩만 지원하며 마이그레이션 결과는 기존 화면 식별자를 가능한 경우 유지한 `하단·전체`다.

### 7.3 렌더링 기본값

- SpriteKit 목표 FPS: 30
- 배경: 투명
- texture filtering: nearest
- 노드 갱신: UUID diff
- 이동: 가장자리 평행 1차원 track, 발 법선 좌표 고정
- 월드 숨김: scene view 정지·분리

### 7.4 Windows 소유권과 저장

- `Sidey.Core`는 프로필·방·Presence·message ledger·bubble ledger·이동 시뮬레이션·검증 규칙을 소유하고 WinUI·Win32·Supabase를 참조하지 않는다.
- `Sidey.App`의 feature ViewModel은 화면에 표시할 상태와 사용자 명령만 소유한다. Supabase endpoint·Realtime payload·HWND를 직접 다루지 않는다.
- `Sidey.Infrastructure`는 `IAuthService`·`IBackendGateway`·`ICredentialStore`·`IPreferencesStore`를 구현하고 community Supabase C# client를 교체 가능한 adapter 뒤에 격리한다.
- `Sidey.Overlay`는 전용 Win32 message-loop thread와 30FPS 고정 step을 소유하고 불변 `WorldSnapshot`을 UUID diff로 반영한다. 위치·속도·animation frame은 앱 세션 상태에 저장하지 않는다. 무료 5종의 GDI bitmap frame은 시작할 때만 만들고 종료 시 모두 해제하며 Debug 검증 모드는 같은 렌더러의 캐릭터 목록만 햄스터로 제한한다.
- `Sidey.Platform.Windows`는 창 정책·모니터·DPI·트레이·로그인 실행·입력 유휴·잠금·절전 이벤트와 Windows update manifest·다운로드 hash 검증을 소유한다.
- Windows 일반 설정은 `%LOCALAPPDATA%\SIDEY\preferences.json`에 atomic replace로 저장하고, Supabase 익명 세션과 평문 초대 코드는 Windows Credential Manager에만 저장한다.
- 24px sprite는 물리 픽셀 기준 `max(2, round-away-from-zero(2 × dpi / 96))` 정수 배율로 렌더한다.

## 8. 서버 변경

`20260831030000_expand_room_capacity_and_reduce_message_retention.sql`은 방 정원 12명과 메시지 7일 보관을 적용한다. `20260901000000_security_hardening.sql`은 적용된 migration을 수정하지 않는 forward-only 보정이며 다음 계약을 추가한다.

- 사용자당 최대 5개 방
- private invite HMAC 비교, 128-bit 코드와 사용자 단위 직렬 rate limit
- 방 및 사용자 단위 transaction advisory lock
- RLS와 함수 실행 권한
- 중복 닉네임과 중복 캐릭터 선택 허용
- 닉네임 2~8자 제한과 기존 9~12자 닉네임의 앞 8자 migration
- membership 변경 시 증가하는 `realtime_epoch`, 서버 전용 DB event와 RPC 검증 transient event
- 메시지 UUID 멱등성과 서버 rate limit, 7일 retention의 방별 단일 invalidation event
- 7일 초과·프로필 없음·방 없음인 미완성 익명 가입만 삭제
- `rename_room(uuid,text)`, `remove_room_member(uuid,uuid)`, 방장 전용 `delete_room(uuid) returns void`; 삭제는 기존 FK cascade로 방 멤버십과 메시지를 함께 제거

`20260901010000_starlight_upalupa_commerce.sql`은 상품·가격·주문·결제 시도·소유권·환불 기록과 RLS를 추가한다. 클라이언트는 서버 catalog 가격과 활성 소유권만 사용하며 checkout 생성, 결제 승인·재조회, webhook, 환불은 Edge Functions가 서비스 권한으로 검증한다. 공개 callback 함수는 일회용 주문 token과 공급자 서명을 확인하고 임의 사용자·금액·소유권을 신뢰하지 않는다.

`20260902000000_commerce_policy_consent_and_refunds.sql`은 적용된 commerce migration을 수정하지 않는 forward-only 보정이며 다음 계약을 추가한다.

- singleton private runtime 설정의 판매 활성화 스위치는 기본 `false`이고 결제 환경은 `test` 또는 `live` 하나로 고정한다.
- 주문은 정책 버전 `2026-09-02-v2`, 결제 당시 서버 고지 원문과 동의 시각을 함께 저장하며 셋 중 일부만 저장할 수 없다. 체크아웃에는 결제 환경·서버 검증·소유권 처리 같은 내부 구현 문구 대신 가격, 제공 시점, 청약철회 제한과 환불 조건만 사용자 언어로 표시한다.
- `commerce-checkout`의 주문 준비는 상품·가격·정책만 반환한다. 기본 미선택 체크박스가 명시적 `accepted=true`와 현재 정책 버전을 보낸 뒤 서버 동의 기록이 성공해야만 토스 클라이언트 설정과 반환 URL을 반환한다.
- 기존 `commerce_checkout_order`와 entitlement DB trigger는 동의 없는 결제 설정 조회와 활성 소유권 생성을 각각 차단한다. 반환 URL, 승인 RPC와 웹훅이 우회되어도 같은 DB 규칙을 통과해야 한다.
- Toss client/secret 키는 `test`/`live` 환경과 `gck↔gsk` 또는 `ck↔sk` 세트가 모두 일치해야 하며 checkout·반환 URL·웹훅·운영 환불의 결제사 API 호출 전에 현재 private runtime 환경과 대조한다.
- 운영 환불은 별도 ops key와 운영자 식별자, `not_provided`, `contract_mismatch`, `duplicate_payment`, `unauthorized_payment`, `minor_without_consent`, `other_statutory_reason` 중 하나를 요구한다. 단순 변심 코드는 허용하지 않고 사유·요청·결제사 상태·처리 결과를 `private.commerce_refund_operations`에 저장한다.

공개 웹사이트는 상품 `store.html`, 이용약관 `terms.html`, 개인정보 `privacy.html`, 환불 `refund.html`을 고정 URL로 제공한다. 한국어 랜딩 본문에는 상품을 표시하지 않고 모바일에서도 보이는 상단 `상점` 탭을 `store.html`로 연결한다. 상점 페이지는 macOS 앱과 같은 최소 300px·최대 360px adaptive 정사각형 캐릭터 카드 그리드를 사용한다. 현재 별빛 우파루파 1종을 표시하며 이후 캐릭터는 같은 목록에 카드를 추가한다. 랜딩 하단에는 배송일자를 `디지털 상품으로 결제 완료 즉시 사용 가능`으로 표시하고, 계정 귀속 상품의 교환·이전 불가, 즉시 제공 동의 뒤 단순 변심 청약철회 제한, 미제공·계약 불일치·중복 또는 무단 결제 등 법정 사유 전액 환불을 요약한다. 이어 판매자 싸이디(SIDEY), 대표 류태현, 사업자등록번호 388-53-01259, 경기도 용인시 기흥구 서천동로21번길 20-6, `010-9270-2973`, `ryu200112@gmail.com`, 통신판매업 신고 면제(간이과세자)를 작은 글씨로 표시한다. 사업자등록증의 생년월일·QR·동호수는 저장소나 웹사이트에 포함하지 않는다. 이번 Windows 릴리스는 구매와 별빛 우파루파 원격 렌더링을 지원하지 않는다.

기존 짧은 초대 코드는 migration에서 비활성화한다. 방장은 새 macOS 클라이언트에서 한 번 재발급해야 하며 public room 조회와 Realtime payload 어디에도 invite hash·version이 포함되지 않는다. macOS hotfix와 migration은 호환 순서로 배포하고 구버전의 기존 topic 계약은 유지하지 않는다.

임시로 방 정원을 20명으로 늘렸던 staging migration은 운영에 적용되지 않았고 `main`에서도 제거한다. 20명 조건은 렌더러 합성 부하 테스트에만 사용하며 제품 정원은 12명이다.

Windows 개발은 별도 Supabase staging 프로젝트에 같은 migration·RLS·private Realtime 정책을 적용한다. staging과 production 모두 익명 인증을 사용하고 일반 실행·설치본은 production publishable 구성을 기본 사용한다. 로컬 개발은 URL과 publishable key를 함께 덮어쓸 수 있지만 service-role·secret key는 클라이언트·저장소·CI 산출물에 넣지 않는다. 익명 사용자도 기존 `auth.users` UUID를 사용하므로 신규 DB schema나 membership migration을 추가하지 않는다.

## 9. 개인정보와 보안 경계

SIDEY가 사용할 수 있는 전역 활동 신호는 마지막 시스템 입력 후 경과 시간과 화면 잠금 상태뿐이다. 타이핑 상태는 SIDEY 입력창에서만 발생한다.

다음 정보는 수집하지 않는다.

- 화면 내용
- 활성 애플리케이션 목록
- 다른 애플리케이션에서 누른 키
- 전역 마우스 좌표
- 파일 내용
- 마이크 오디오
- 카메라 영상

E2EE는 현재 설계·구현·검증되지 않았다. 전송 암호화, Postgres, RLS를 근거로 종단간 암호화라고 표현하면 안 된다.

Windows는 Supabase 익명 인증만 사용하며 Google email·provider identity나 OAuth callback을 처리하지 않는다. 로컬 로그에는 access·refresh token, 메시지 본문, 평문 초대 코드를 남기지 않는다.

macOS commerce 로그와 공개 URL에는 Google OAuth token, 결제사 비밀키, service-role key, 일회용 주문 token, 전체 결제 식별자를 남기지 않는다. 결제 성공 redirect만으로 소유권을 지급하지 않고 토스 승인·재조회, 결제 당시 정책 동의와 Postgres 기록이 모두 일치해야 한다. 카드 번호·결제 비밀번호는 SIDEY가 수집하지 않는다.

## 10. 검증과 승격 기준

### 10.1 자동화 테스트

- 영역: 4개 가장자리 × 3개 길이의 240pt activity frame과 최대 360pt render frame, 접선 144pt 여유, 중앙 정렬, 회전, visible frame, 깊이 제한, hotspot 원점 변환, 모니터 fallback
- 이동: 20개 합성 노드가 3,000 tick 동안 1차원 track과 발 기준선을 유지하고 finite 좌표, 입력창·상호 회피, 겹침 시 idle 해제·가속 통과, 실제 메시지 말풍선의 240pt/s² 분리 가속·72pt/s 상한·8pt 해소·경계 힘 재배분·혼잡 시 안정적인 겹침·일반 목표 복귀
- 상태: 온라인·자리 비움 doze와 고정 `Zzz`의 부유·alpha 반복·해제 시 action 정리, 오프라인 curled sleep·재연결·타이핑, 내 캐릭터 항상 표시, 오프라인 숨김, 방 전환 UUID diff, 최대 8자 닉네임·반투명 배경과 상태 점 5pt 간격, 발 기준 7배·0.8초 리액션과 이벤트 UUID 중복 제거
- Realtime: current epoch topic 접근, client DB형 Broadcast 거부, 다른 사용자·방 transient event 거부, bounded stream overflow 재동기화, backoff와 generation 기반 snapshot reconciliation, Presence publication 최대 동시 실행 수 1을 검증한다. 실서버 2클라이언트에서는 강제 단절과 추방 뒤 자동 재구독·메시지·Presence·`character_pulse` 격리를 확인한다.
- 메시지: 발신자별 교체, 최대 4개 eviction, 10초 만료, 이동 중 말풍선 추적, 방별 outbox 낙관적 성공·실패, 응답 유실 시 동일 UUID 멱등성, 방 A 실패가 방 B draft를 건드리지 않음, confirmed ledger의 방별 50개·7일 cutoff, 최근 기록 0·1·20·50·51·120개 및 동일 timestamp keyset·페이지 중복 제거·실시간/pending/failed 병합·탈퇴 발신자 fallback·방 전환 취소·창 닫기 해제·추가 조회 실패와 재시도, 조용히 모드, 미확인 수, 엄격한 서버 시각 해석
- 말풍선: 1자·200자·3줄·프리셋 양 끝·4방향에서 본문과 꼬리 누적 frame이 캔버스 안에 유지하고 실제 메시지 본문만 접선 충돌 범위에 포함하며 타이핑 말풍선은 제외
- 창: 월드 항상 위·전체 클릭 통과, 내 캐릭터 52×52 hotspot, composer의 선택 모니터 상단 중앙·노치 아래 10pt 배치와 왼쪽 `×`·Esc·외부 클릭 닫기, 단일·더블클릭 분기와 캐릭터별 1초 리액션 쿨타임, composer 초기 숨김·열기·마지막 전송 뒤 5초 자동 닫힘·타이머 갱신·실패 복구, 기록 일반 창
- 업데이트: production 채널에 Sparkle `2.9.6` 프레임워크·메뉴 항목·피드 URL·EdDSA 공개키가 번들에 포함되고 signed feed와 압축 해제 전 검증을 강제하며, 업데이트 진행 중에는 수동 확인 메뉴를 비활성화. development 채널은 Sparkle을 시작하지 않고 수동 확인 메뉴도 항상 비활성화
- 에셋: 5개 시트의 240×24 RGBA·10프레임·공통 발 기준선·결정적 hash·Release 번들 포함, 메뉴 아이콘 1x·2x template/unread variant
- 설정: 860×640 최소 크기와 1000×760 기본 크기의 라이트·다크 렌더, 옅은 카드 명도, 240pt 컨트롤 영역과 Picker·버튼·토글 오른쪽 정렬, `동작 정보` 제거, 두 사람 그룹 아이콘, 한글 IME 조합 확정 후 닉네임 저장
- 입력 필드: 200자 끝, 한글 조합, 영문 긴 단어, 이모지, Shift+Enter 3줄, 중간 커서 이동·전체 선택, undo·redo, 외부 draft와 잘못된 입력 복구에서 마지막 글자와 커서가 보이고 텍스트 손실·IME 중복 확정·가로 스크롤이 없는지 검증한다.
- 상점: 2열 상품 카드의 독립 상태·정렬, 소유권·환불 fallback, Google callback scheme 분리, 최소·기본 크기와 라이트·다크 렌더, 한 단계 카드 구조, 상태 배지와 아이콘 미리보기 접근성, 넓은 창 중앙 하단·작은 창 스크롤 끝의 공통 정책 안내를 검증한다.
- commerce 서버·웹: 판매 기본 잠금, 동의 멱등성, 정책 버전 불일치, 체크박스 미동의, 동의 없는 승인·소유권 차단, 만료 token, 위조 금액, 중복 승인·중복 클릭·반환 URL 재호출, 허용 법정 사유 환불과 private 결과 기록·햄스터 복귀, test/live 키 혼용 거부를 검증한다.
- 그룹 설정: 0·1·12명 멤버 목록, 기본 접힘·제목 영역 및 오른쪽 단일 화살표 펼침, `그룹 참가` 문구, 생성·참여·전환별 진행 문구와 라이트·다크 대상 카드 강조, A→B→C 연속 선택에서 C만 commit, UUID 기반 방장 왕관과 펼친 목록 아래 방장 전용 이름 변경·삭제 버튼, 이름 변경 저장·취소, 대상 명시 추방 확인, 영구 삭제 2단계 확인, 활성·비활성·마지막 그룹 삭제 fallback, 초대 코드 복사 성공·실패와 3초 표시·재클릭 갱신·행 제거 취소
- DMG: 660×420 배경, `SIDEY.app`, `/Applications` 심볼릭 링크, 기존 5종 idle 프레임, `.DS_Store`를 자동 생성·마운트 검증하고 Finder에서 아이콘 위치·안내 문구·nearest-neighbor 픽셀 선명도를 수동 확인
- Keychain: schema 6에서 7로 값 보존, 신규 설치 안내 생략, 실행 중 `LAContext` 재사용, 동일 키 읽기 캐시, 동일 데이터 저장 생략, 거부 콜백 1회와 거부 후 추가 Security API 호출 차단
- 서버: 실제 anon/authenticated role의 RLS, 12번째 성공·13번째 거부와 여섯 번째 방 경합, 병렬 초대 제한, invite hash API 비노출, current epoch topic 권한, client Broadcast INSERT 봉쇄, transient event whitelist·rate, 메시지 멱등성·rate, 7일 retention, 비방장 관리 거부와 cascade를 SQL 테스트한다.
- Windows 설치·업데이트: clean install, `C:\Program Files\SIDEY`, 공용 시작 메뉴, 아이콘이 포함된 `Uninstall.exe`, 게시된 런처·호스트 시작 스모크, repair, 실행 중 upgrade의 정상 종료 요청, downgrade 차단을 Windows CI·실기에서 확인한다. Windows 설정·MSI·`Uninstall.exe`의 일반 제거에서 기본 미선택 데이터 삭제 옵션이 동작하고, 선택 시에만 현재 사용자의 `%LOCALAPPDATA%\SIDEY`와 Credential Manager `SIDEY/` 자격 증명을 삭제하며 upgrade·repair에는 실행하지 않는지도 검증한다. `windows-v<version>` manifest의 버전·태그·고정 MSI URL·SHA-256도 검증하며 기존 per-user·Burn 테스트 설치가 있으면 설치 전에 제거하도록 안내한다.

### 10.2 macOS 장시간 수동·계측 테스트

최대 방 인원 12명을 표시한 실제 앱을 30분 이상 실행하고, 별도 20노드 합성 부하를 병행하며 다음을 모두 확인한다.

- p95 frame time 40ms 이하
- 100ms 이상 main-thread hang 없음
- 지속적인 RSS 증가 없음
- 캐릭터 떨림·NaN·영역 이탈 없음
- 오버레이를 숨기면 SpriteKit이 정지함
- 다중 모니터 연결·분리 fallback
- 화면 잠금·절전·복귀
- Realtime 연결 끊김·재연결과 transient typing 정리

### 10.3 Windows 지속 검증 기준

1. 첫 기능 빌드부터 무료 5종을 `PixelCharacterCatalog`와 하나의 `UpdateLayeredWindow` 렌더러로 제공하고 asset·frame·발 기준선·방향·fallback 계약을 자동 검증한다.
2. 같은 렌더러를 햄스터 1종으로 제한하는 Debug 내부 모드에서 투명·최상위·외부 앱 클릭 통과·52×52 hotspot·composer 포커스·100/125/150/200% DPI를 Windows 11 25H2 x64 실기에서 통과한다. 이 모드는 Release에 노출하지 않는다.
3. 연결형 검증에서 익명 세션 복구·생성, 프로필, 방, 메시지, Presence, typing lease, `character_pulse`를 staging의 기존 macOS 클라이언트와 양방향 확인한다.
4. 최종 12명 월드를 2시간, 20노드 합성 부하를 30분 실행해 p95 frame time 40ms 이하, 100ms 이상 UI-thread hang 없음, warm-up 후 working set 20MB 초과 증가 없음, GDI/USER handle·COM surface 지속 증가 없음을 확인한다.
5. 보조 모니터의 mixed-DPI와 연결 해제를 실기에서 계속 회귀 검증하고 합성 모니터 geometry 테스트도 유지한다.

### 10.4 macOS 배포 절차

1. macOS·Supabase·웹·입력 수정 PR에서 전체 Swift 테스트·Release 빌드, pgTAP, 웹 계약 테스트와 20노드 합성 부하를 통과한다. 이 PR에서는 공개 다운로드와 앱 버전을 `v1.0.3` build 14로 유지한다.
2. 검증된 PR을 `main`에 병합하고 `20260902000000_commerce_policy_consent_and_refunds.sql`과 commerce Edge Functions를 운영 Supabase에 배포하되 private 판매 스위치는 `false`로 유지한다.
3. 이 지점에서 자동 작업을 멈추고 사용자가 토스 개발자센터에서 라이브 client·secret 키를 Supabase secret에 직접 입력하게 한다. 원문 키는 채팅·코드·셸 명령·로그에 남기지 않는다.
4. 판매 스위치를 잠시 켜 라이브 990원 결제 1건으로 승인, 소유권 지급, 앱 재실행 복구, 허용 사유 운영 취소, 소유권 회수와 햄스터 복귀를 확인한 뒤 즉시 다시 잠근다.
5. 즉시 제공·청약철회 제한·미성년자·통신판매업 신고 면제·판매자·개인정보 고지를 실제 운영 설정과 함께 법률 검토한다. 검토가 끝나지 않으면 판매와 릴리스를 진행하지 않는다.
6. `v1.0.4` build 15 릴리스 브랜치에서 앱·웹 다운로드·릴리스 문서를 갱신한다. 이 단계 전에는 공개 버전을 미리 바꾸지 않는다.
7. 이 지점에서 다시 작업을 멈추고 사용자가 p12를 로그인 Keychain에 설치하게 한다. Developer ID Application identity와 notary profile을 확인하되 인증서 원문과 비밀번호를 저장소·채팅·로그에 남기지 않는다.
8. Developer ID Application 인증서와 Hardened Runtime으로 앱·로그인 항목·Sparkle 중첩 코드를 서명하고 Apple 공증 뒤 ticket을 staple한다.
9. `scripts/package_macos_release.sh`로 버전·빌드 번호, arm64 아키텍처, 번들 메타데이터, 코드 서명, 신규 설치용 DMG, Sparkle용 ZIP과 각 SHA-256을 검증한다. 로그인된 Finder 세션에서 쓰기 가능한 DMG를 마운트해 660×420 배경, 왼쪽 `SIDEY.app`, 오른쪽 `/Applications` 바로가기, 숨긴 toolbar·sidebar·status bar와 `.DS_Store`를 설정한 뒤 UDZO로 변환한다. 변환본은 다시 마운트해 앱·심볼릭 링크·배경 크기·`.DS_Store`, Developer ID 서명·공증·staple을 모두 확인한다.
10. 검증된 동일 커밋에 `v1.0.4` 태그와 GitHub Release를 만든 뒤 DMG와 ZIP을 업로드한다. GitHub에서 다시 받은 두 파일이 로컬 SHA-256과 같아야 한다.
11. `scripts/macos/prepare_sparkle_appcast.sh`로 ZIP의 EdDSA 서명과 signed appcast를 만들고 Release ZIP URL이 실제 다운로드된 뒤에만 `updates/appcast.xml`을 게시한다. appcast를 먼저 게시하지 않는다.
12. 웹 다운로드 링크를 같은 DMG로 갱신하고 `sidey-app/homebrew-tap` Cask를 동일 고정 URL·SHA-256으로 갱신해 audit·style·신규 설치·실행·삭제를 검증한다.
13. 신규 설치, Sparkle 업데이트, Google 연결, 실제 결제 복구를 최종 확인한 뒤에만 판매 스위치를 `true`로 바꾸고 stable 승격 근거를 `docs/DECISIONS.md`에 기록한다. 현재 공개본은 여전히 macOS `v1.0.3`(build 14)이며 이 절차 완료 전에는 `v1.0.4`가 공개됐다고 표시하지 않는다.

Sparkle `2.9.6`이 production 앱에 내장되며 메뉴바 `업데이트 확인…`과 설정의 업데이트 카드에서 수동 확인할 수 있다. 설정 버튼은 production updater가 사용 가능한 동안에만 활성화한다. 자동 확인은 Sparkle의 사용자 동의 흐름을 사용하고, 익명 system profiling은 활성화하지 않는다. appcast와 ZIP은 서로 다른 검증 대상이므로 둘 다 `sidey-app` EdDSA 키로 서명하며 `SURequireSignedFeed`와 `SUVerifyUpdateBeforeExtraction`을 강제한다. 피드는 GitHub raw HTTPS URL, 설치 파일은 GitHub Releases를 사용한다.

Sparkle이 없는 기존 alpha 사용자는 최신 공증 DMG로 한 번 수동 교체해야 하며, 이후 앱 내부 업데이트를 사용한다. 사용자 세션과 설정은 앱 번들 외부에 있어 교체·업데이트 후에도 유지된다. Sparkle 개인키는 저장소나 CI 로그에 넣지 않고 release operator의 로그인 Keychain과 암호화한 오프라인 백업에만 둔다.

공개 배포본은 표시명 `SIDEY`, 채널 `production`을 사용한다. 로컬 개발본은 최신 Release 구성의 ad-hoc 빌드를 표시명 `Sidey-dev`, 채널 `development`로 만들어 `/Applications/Sidey-dev.app`에만 설치하며 Sparkle controller를 생성하지 않는다. 두 채널은 기존 익명 계정·그룹·설정을 이어 쓰기 위해 `app.sidey.desktop` bundle ID, login item ID, `com.sidey.desktop` Keychain service를 공유한다. 설치 스크립트는 정확한 dev 앱 경로만 교체한다.

schema 6 이하 기존 설치가 alpha.6에서 처음 Keychain 정보를 읽기 전에는 SIDEY 자체 안내창을 먼저 표시한다. 안내창은 로그인 상태와 그룹 초대 코드를 macOS 키체인에 안전하게 보관·조회한다는 목적, 이전 버전 정보를 처음 불러올 때 Mac 로그인 암호를 요청할 수 있다는 점, 다음부터 묻지 않게 하려면 macOS 창에서 `항상 허용`을 선택해야 한다는 점, `허용`은 같은 실행이나 다음 실행에서 창을 반복시킬 수 있다는 점, SIDEY가 암호를 확인하거나 저장하지 않는다는 점을 설명한다. 버튼은 `계속`과 `SIDEY 종료`다. 신규 설치는 안내를 생략하고 새 항목을 만든다.

Keychain 접근은 앱 실행 동안 하나의 `LAContext`를 공유하고 `localizedReason`은 앱 이름을 제외한 `로그인 상태와 그룹 초대 코드를 안전하게 불러옵니다.`로 고정한다. 같은 service/account 읽기는 성공과 없음 결과를 메모리에 캐시하고, 캐시된 데이터와 같은 저장은 Security API 호출을 생략한다. `errSecUserCanceled` 또는 `errSecAuthFailed`가 한 번 발생하거나 자체 안내창에서 종료를 선택하면 프로세스 전역 거부 상태를 기록하고 후속 Security API를 호출하지 않은 채 앱을 종료한다. 기존 설치는 세션 복구에 성공한 뒤에만 schema 7 전환 완료 상태를 저장한다.

신규 설치 기본 파일은 공증 DMG다. Homebrew third-party tap은 같은 DMG의 고정 URL·SHA-256, arm64·macOS 26+ 조건, `auto_updates true`, `SIDEY.app`과 안전한 종료 규칙을 사용하고 사용자 데이터 삭제용 `zap`은 선언하지 않는다. ZIP은 Sparkle 전용으로 유지한다.

자동화 테스트와 공개 배포는 장시간 수동 기준을 대신하지 않는다. 수행하지 않은 장시간 항목을 통과했다고 기록하지 않고 정식판에서도 지속 검증한다.

### 10.5 Windows v1.0.3 정식 배포 절차

1. Windows 전체 단위·계약·창 정책·업데이트·배포 source 테스트와 10.3의 실기·장시간 기준을 통과한다.
2. staging에서 익명 세션·RLS·private Realtime을 통과한 뒤 production publishable 구성에서도 다시 확인한다. service-role·secret key는 클라이언트·저장소·CI 산출물에 넣지 않는다.
3. CI에서 `win-x64` unpackaged·multi-file self-contained 앱을 `PublishSingleFile=false`로 게시한다. 루트 `SIDEY.exe` 런처가 인수를 `Runtime\SIDEY.Host.exe`로 전달하고, 앱·.NET·Windows App SDK 런타임은 `Runtime`, 사용자 콘텐츠는 `Assets`, SIDEY 번역은 `Langs`에 둔다. 게시한 런처와 호스트를 실제 시작해 main 또는 미지원 OS 창 활성화 로그가 남고 프로세스가 유지되는지 확인한다.
4. WiX Toolset `6.0.2`로 전체 payload와 내부 cabinet을 포함한 머신 단위 `SIDEY-Windows-x64-v1.0.3.msi`를 만든다. Burn Setup EXE·ZIP·MSIX는 만들거나 공개하지 않는다.
5. 자체 서명 인증서·임시 PFX·공개 CER를 만들지 않고 Release용 MSI와 내부 검증용 SHA-256만 생성한다. `.sha256` 파일은 Release 자산으로 게시하지 않는다.
6. clean install·공용 시작 메뉴·아이콘이 포함된 `Uninstall.exe`·repair·실행 중 upgrade·downgrade 차단을 확인한다. Windows 설정·MSI·`Uninstall.exe`의 일반 제거에서 데이터 삭제 옵션이 기본 미선택이고, 선택 시에만 현재 사용자의 설정·로그·로그인 정보를 삭제하며 upgrade·repair에는 삭제하지 않는지 검증한 뒤, 검증된 커밋에 `windows-v1.0.3` 태그와 GitHub 정식 Release를 만든다. Release에는 MSI 하나만 게시하고 제거 옵션의 영향을 명시한다.
7. Windows Actions가 성공하면 Pages Actions가 GitHub 정식 Release의 단일 MSI를 다시 내려받아 SHA-256을 계산한다. 태그·고정 MSI URL·자산 구성이 모두 맞을 때 배포 아티팩트의 `website/windows-latest.json`과 호환 경로 `website/windows/update.json`에 64자리 SHA-256을 기록하고 Windows 다운로드 버튼을 활성화한다. 앱은 시작 시 한 번 새 버전을 확인하고 트레이·설정에서 수동 확인하며, 사용자 승인 뒤 다운로드·hash 검증을 통과한 설치기만 실행한다.

공개 MSI는 관리자 승인 뒤 모든 사용자용으로 `C:\Program Files\SIDEY`에 설치하고 공용 시작 메뉴에 앱과 제거 바로가기를 만든다. 설치 폴더에는 앱 아이콘을 포함한 `Uninstall.exe`를 두고, MSI 제품 정보에는 같은 아이콘을 등록한다. 기존 per-user·Burn 테스트 설치는 등록 방식이 달라 자동 전환하지 않으며 먼저 Windows 설정에서 제거하도록 안내한다. `Uninstall.exe`를 직접 실행하면 Windows Installer 제거를 시작하고, Windows 설정과 MSI 유지 관리 화면을 포함한 일반 제거에는 `설정, 로그 및 로그인 정보도 삭제` 체크박스를 기본 미선택으로 표시한다. 선택하면 MSI가 `Uninstall.exe --cleanup`을 실행해 현재 사용자의 `%LOCALAPPDATA%\SIDEY`와 Credential Manager의 `SIDEY/` 자격 증명을 삭제한다. 선택하지 않으면 사용자 데이터를 보존하며 major upgrade와 repair에서는 이 정리를 실행하지 않는다.

SHA-256은 PowerShell에서 `Get-FileHash .\SIDEY-Windows-x64-v1.0.3.msi -Algorithm SHA256`으로 계산한다. GitHub에서 다시 내려받은 MSI와 CI 후보가 같은지 검증하고 이 값을 업데이트 manifest에 기록하되 별도 `.sha256` Release 자산은 만들지 않는다.
