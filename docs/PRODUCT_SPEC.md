# SIDEY 제품 기획서

- 문서 버전: 0.5
- 최종 갱신: 2026-08-31
- 상태: macOS alpha 배포, Windows 네이티브 햄스터 vertical slice 개발
- 현재 대상 플랫폼: macOS 26 이상 Apple Silicon, Windows 11 25H2 이상 x64
- 현재 개발 브랜치: `main`

## 1. 제품 정의

`SIDEY`는 최대 5명의 가까운 친구가 2D 픽셀 동물로 사용자의 화면 가장자리에 머물며 상태, 타이핑, 짧은 메시지를 보여주는 초대 전용 데스크톱 ambient messenger다.

각 캐릭터는 실제 친구 한 명을 나타낸다. 공개 커뮤니티, AI 캐릭터, 가상 반려동물, 게임형 성장 시스템은 제품 범위가 아니다. 제품명은 항상 `SIDEY`를 사용한다.

핵심 가치는 다음 세 가지다.

- 별도 채팅창을 계속 열지 않아도 친구의 존재와 상태가 보인다.
- 짧은 메시지가 캐릭터의 말풍선으로 자연스럽게 나타난다.
- 평소에는 뒤 애플리케이션의 클릭과 작업 흐름을 방해하지 않는다.

## 2. 현재 범위와 제외 범위

### 2.1 현재 macOS slice

- macOS 네이티브 클라이언트는 현재 alpha 기준 구현으로 유지한다.
- 햄스터 vertical slice의 구조 위에 내장 픽셀 동물 5종을 제공한다.
- 실제 그룹은 최대 5명이다. 렌더러 안정성은 별도 20노드 합성 스트레스 테스트로 검증한다.
- macOS 코드·인증·설정 schema는 Windows 개발을 위해 재작성하지 않는다.
- 기존 설치의 인증 세션과 설정을 잃지 않도록 Swift 기반 legacy migration 호환만 유지한다.

### 2.2 Windows 구현 목표

- Windows 11 25H2(build 26200) 이상 x64 네이티브 클라이언트를 C#/.NET 10 LTS·WinUI 3·Win32로 구현한다.
- 일반 창은 SIDEY 브랜드의 Windows Fluent UI로 만들고, 투명 월드는 전용 Win32 HWND가 소유한다. 첫 햄스터 local slice는 사전 생성한 premultiplied BGRA frame을 `UpdateLayeredWindow`로 표시해 창 정책과 자원 안정성을 검증하며, 최종 5캐릭터 렌더러는 이 실측 뒤 결정한다.
- 햄스터 1종으로 창 정책·DPI·클릭 통과·hotspot·잠금·절전 복귀를 먼저 통과한 후 5종과 전체 기능으로 확장한다.
- 최종 목표는 macOS와 서버 계약·제품 행동이 동등한 Windows 판이며, 플랫폼 창·설정 UI는 Windows 관례를 따른다.
- Godot·WPF·Electron·WebView는 사용하지 않는다.

### 2.3 명시적 제외

- 내장 5종을 넘는 추가 동물
- 모바일·웹 클라이언트
- 공개 그룹·검색·발견
- 5명을 넘는 그룹
- 이미지·파일 전송, 음성·영상 통화
- 사용자 업로드 아바타와 캐릭터 커스터마이징
- AI 동료

## 3. 그룹과 계정

- 그룹은 초대 전용 비공개 방이다.
- 방당 최대 5명이며 서버 함수가 트랜잭션 잠금 안에서 제한한다.
- 사용자당 참여 가능한 방은 최대 5개다.
- 오버레이에는 한 번에 활성 그룹 하나만 표시한다.
- 닉네임은 줄바꿈 없는 2~8자로 제한한다. 닉네임과 캐릭터 선택은 같은 방에서 중복 가능하며 권한·식별은 UUID로 처리한다.
- 초대 코드는 방장이 재발급하기 전까지 유효하고 DB에는 해시만 저장한다.
- 사용자·프로필·방·메시지는 RLS를 통과해야 한다.
- macOS는 익명 인증과 기존 세션 복구 정책을 유지한다. 복구 실패를 새 익명 계정 생성으로 조용히 덮어쓰지 않는다.
- Windows 신규 설치는 시스템 브라우저의 Google OAuth PKCE 로그인을 필수로 하고 `sidey://auth/callback`으로 복귀한다. Google 이름·사진은 프로필에 자동 복사하지 않는다.
- Windows와 macOS의 서로 다른 사용자 UUID가 같은 방에 참가하는 것을 지원하며, Mac↔Windows 계정 이전은 범위 밖이다.

## 4. 픽셀 월드

### 4.1 활동 영역

활동 영역은 선택한 모니터의 `visibleFrame`에 붙는 투명 렌더 캔버스다. 기본 깊이는 240pt이며 작은 화면에서는 visible frame 세로 길이의 1/3을 넘지 않는다. 캐릭터의 발은 화면 경계의 1차원 track에 고정되고, 나머지 깊이는 닉네임·상태 효과·말풍선에만 사용한다.

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
| 자리 비움 | 선 채 눈을 감고 고개를 떨어뜨리는 졸기, 작은 `z`, 원래 채도 | 주황 |
| 오프라인 | 옆으로 웅크린 잠, 저채도, 약 75% 불투명도 | 빨강 |
| 재연결 | 정지 | 회색 |

타이핑은 캐릭터 모션을 바꾸지 않는다. `TypingIndicatorNode`가 `.` → `..` → `...`을 0.35초 간격으로 반복한다. 같은 캐릭터에 실제 메시지 말풍선이 있으면 타이핑 action을 중단하고 메시지를 우선하며, 메시지 만료 뒤 여전히 타이핑 중이면 점 애니메이션을 다시 시작한다. Broadcast 빈도와 schema는 바꾸지 않는다.

닉네임 상태 점은 고정 x 좌표를 사용하지 않는다. 실제 닉네임 label frame의 왼쪽에서 점 반지름과 5pt 간격만큼 떨어진 위치를 계산해 최대 8자 이름과 `· 나` 표식에서도 겹치지 않게 한다. 흰색 닉네임 뒤에는 여백이 있는 반투명 검정 캡슐을 렌더하며, 뒤 애플리케이션의 실제 픽셀은 읽지 않는다.

내 캐릭터를 더블클릭하면 캐릭터 스프라이트만 발 위치를 기준으로 4배까지 0.14초 동안 커지고 0.42초 동안 원래 크기로 복귀한다. 닉네임·상태 점·말풍선은 확대하지 않는다. 로컬에서 즉시 재생한 뒤 같은 방에 이벤트 UUID와 사용자 UUID를 담은 `character_pulse` Broadcast를 보내며, 송신·수신 모두 캐릭터별 1초 쿨타임을 적용한다. 동일 이벤트 UUID는 한 번만 재생한다.

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
- Presence는 연결·온라인·자리 비움 상태에 사용한다.
- Broadcast는 SIDEY 입력창의 타이핑과 `character_pulse`처럼 저장하지 않는 이벤트에만 사용한다.
- macOS 클라이언트는 5초마다 WebSocket과 각 방 채널의 실제 구독 상태를 확인한다. 비정상이 8초 이상 지속되면 채널 및 수신 스트림을 재생성하고, 실패가 이어지면 8초·16초·최대 30초 간격으로 재시도한다.
- 재구독 중에는 로컬 상태를 재연결로 표시한다. 성공하면 현재 Presence를 다시 publish하고 방·멤버 snapshot과 최근 메시지를 다시 읽어 단절 중 누락된 가입·메시지를 보정한다.
- 메시지 ledger는 `senderID`를 보존한다.
- 클라이언트가 UUID로 메시지를 낙관적으로 표시하고 동일 UUID의 저장·Realtime 결과와 중복 제거한다.
- 저장 실패 시 낙관 기록과 말풍선을 제거하고 입력 원문을 복구한다.

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
- 전체 영역이 `ignoresMouseEvents`로 뒤 애플리케이션에 클릭을 통과시킨다.
- 숨길 때 SpriteKit 렌더링과 장면 업데이트를 정지한다.
- 보안 화면, DRM 앱, 권한이 더 높은 앱, 모든 독점 전체화면 게임 위 표시는 보장하지 않는다.

### 6.2 입력창

- 선택 모니터의 `visibleFrame` 상단 중앙, 노치·메뉴바 아래 10pt에 400×56으로 고정한다. 노치가 없는 화면에서도 같은 상단 여백을 사용한다.
- 왼쪽 `×` 닫기 버튼, `메시지를 입력해 주세요` placeholder가 있는 텍스트 입력, 오른쪽 전송 버튼만 제공한다.
- 이 패널만 키보드 포커스와 포인터 입력을 받는다.
- 패널의 둥근 glass 영역 밖과 hosting surface는 포커스 여부와 무관하게 완전 투명하며 400×56 사각 배경을 그리지 않는다.
- 최대 200자·3줄, Enter 전송, Shift+Enter 줄바꿈 계약을 유지한다.
- 앱 실행과 오버레이 표시 직후에는 숨겨져 있다.
- 내 캐릭터 단일 클릭 또는 메뉴바 `메시지 작성`으로 열고 즉시 포커스한다.
- 내 캐릭터 더블클릭은 리액션을 실행하고 입력창은 열린 상태로 유지한다.
- 캐릭터 또는 입력 패널 클릭으로 앱이 활성화될 때는 수동 앱 재열기로 처리하거나 설정창을 열지 않는다.
- 왼쪽 `×`, 내 캐릭터 재클릭, Esc 또는 입력창 외부 클릭은 draft를 보존하고 닫으며 `typing_stop`을 보낸다. 외부 클릭은 전역 마우스 이벤트나 좌표를 수집하지 않고 입력 패널의 키 포커스 상실로 판정한다.
- 유효한 메시지를 전송하면 입력창을 유지하고 마지막 전송 시점부터 5초 뒤 자동으로 닫는다. 5초 안에 다시 전송하면 타이머를 갱신한다.
- 낙관적 전송 실패 시 예약 닫힘을 취소하고 원문을 복구한 뒤 입력창을 열어 포커스한다.
- 오버레이 숨김, 활성 방 전환, 현재 사용자 노드 제거 시 입력창을 닫는다.

월드 패널 전체는 계속 `ignoresMouseEvents`로 클릭을 통과시킨다. 내 캐릭터 위의 52×52pt 투명 `NSPanel`만 최대 15Hz·1pt 임계값으로 위치를 따라가며 클릭을 받는다. 전역 마우스 좌표와 전역 이벤트 모니터는 사용하지 않는다. 다른 캐릭터와 빈 영역의 클릭은 뒤 애플리케이션으로 통과한다.

잠금, 직접 이동, 크기 조절, 오버레이 내부의 최근 기록·설정 버튼은 제거한다. 최근 기록은 메뉴바에서 여는 일반 레벨의 macOS 창으로 제공한다.

### 6.3 메뉴바

상태 아이콘은 18×18 1x·36×36 2x 픽셀 햄스터 얼굴 template image다. 읽지 않은 메시지가 있으면 우측 상단 원형 표시가 포함된 unread variant를 사용한다. 접근성 설명과 tooltip에도 unread 상태를 반영하며 전용 이미지 로딩 실패 시에만 `pawprint.fill`을 사용한다.

메뉴바에는 다음 항목만 둔다.

- 오버레이 표시·숨김
- 메시지 작성
- 활성 그룹과 그룹별 미확인 수
- 조용히 모드
- 최근 기록
- 그룹 설정
- 로그인 시 실행
- 업데이트 확인
- 설정
- 종료

### 6.4 Windows 창과 트레이

- 월드는 WinUI XAML 창에 투명 표현을 위임하지 않고 `WS_POPUP` 기반 전용 Win32 HWND가 소유한다. 첫 local slice는 24px 원본에서 정수 nearest-neighbor로 미리 만든 premultiplied BGRA frame을 `UpdateLayeredWindow`로 표시하며 tick마다 bitmap이나 surface를 새로 할당하지 않는다.
- 월드 HWND는 작업 표시줄·Alt-Tab에 나타나지 않고 활성화되지 않으며 외부 앱으로 포인터를 통과시킨다.
- 내 캐릭터 상호작용 52×52 hotspot은 별도 HWND가 소유하고 최대 15Hz·1 DIP 임계값으로 위치를 갱신한다. 전역 마우스 hook·전역 좌표 수집은 금지한다.
- composer는 400×56 DIP 별도 WinUI 창이며, 내 캐릭터 클릭·트레이 `메시지 작성`만 이 창을 활성화한다.
- 트레이 메뉴는 macOS 메뉴바의 제품 행동을 같게 제공하되 Windows alpha에서는 `업데이트 확인`을 제외하고 `로그아웃`을 제공한다.
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
- 메시지 ledger와 active bubble 목록
- 오버레이 영역, 모니터, 오프라인 표시 등 환경설정
- 편집 중인 `selectedCharacterID`

Presence나 snapshot을 적용할 때 UUID 기준으로 추가·갱신·삭제하며 존재하는 캐릭터 노드의 위치를 초기화하지 않는다.

`OverlayWindowGroup`은 composer 표시 상태와 내 캐릭터 단일·더블클릭 패널을 소유한다. `AppCoordinator`는 `character_pulse` 송수신과 캐릭터별 1초 쿨타임을 소유한다. `AppModel`에는 화면 좌표나 애니메이션 frame을 저장하지 않는다.

`SideyBackend`는 Realtime 채널·수신 task·Presence publish와 자동 복구 watchdog을 소유한다. 복구 성공 시 snapshot 이벤트만 상위로 보내며, `AppCoordinator`가 이를 적용하고 활성 방의 최근 메시지를 재조회한다.

### 7.2 환경설정

Codable 계약은 다음과 같다.

```swift
OverlayRegionPreference(
    edge: OverlayEdge,
    span: OverlaySpan,
    screenIdentifier: String?
)
```

환경설정 스키마를 올리고 과거 frame, lock, scale, screen 값은 디코딩만 지원한다. 마이그레이션 결과는 기존 화면 식별자를 가능한 경우 유지한 `하단·전체`다.

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
- `Sidey.Overlay`는 전용 Win32 message-loop thread와 30FPS 고정 step을 소유하고 불변 `WorldSnapshot`을 UUID diff로 반영한다. 위치·속도·animation frame은 앱 세션 상태에 저장하지 않는다. 첫 local slice의 GDI bitmap frame은 시작할 때만 만들고 종료 시 모두 해제한다.
- `Sidey.Platform.Windows`는 창 정책·모니터·DPI·트레이·로그인 실행·입력 유휴·잠금·절전 이벤트를 소유한다.
- Windows 일반 설정은 `%LOCALAPPDATA%\SIDEY\preferences.json`에 atomic replace로 저장하고, OAuth 세션·PKCE verifier·평문 초대 코드는 Credential Locker에만 저장한다.
- 24px sprite는 물리 픽셀 기준 `max(2, round-away-from-zero(2 × dpi / 96))` 정수 배율로 렌더한다.

## 8. 서버 변경

운영에 적용된 `20260829000000_sidey_core.sql`의 `join_room` 함수가 방 정원을 5명으로 강제한다. 새 캐릭터 ID는 기존 `character_id` 형식에 맞으므로 pixel-world 또는 캐릭터용 schema migration은 추가하지 않는다. 다음 계약은 그대로 유지한다.

- 사용자당 최대 5개 방
- 초대 코드 hash 비교와 rate limit
- 방 및 사용자 단위 트랜잭션 advisory lock
- RLS와 함수 실행 권한
- 중복 닉네임과 중복 캐릭터 선택 허용
- 닉네임 2~8자 제한과 기존 9~12자 닉네임의 앞 8자 migration
- 메시지·Presence·Broadcast schema (`character_pulse`는 DB migration 없는 transient 이벤트)

임시로 방 정원을 20명으로 늘렸던 staging migration은 운영에 적용되지 않았고 `main`에서도 제거한다. 20명 조건은 렌더러 합성 부하 테스트에만 사용한다.

Windows 개발은 별도 Supabase staging 프로젝트에 같은 migration·RLS·private Realtime 정책을 적용한다. Google provider와 `sidey://auth/callback` redirect allow-list는 staging에서 먼저 검증하고 Windows alpha 승격 직전 production에 추가한다. OAuth client secret·service-role key는 클라이언트·저장소·CI 산출물에 넣지 않는다. OAuth 사용자도 기존 `auth.users` UUID를 사용하므로 신규 DB schema나 membership migration을 추가하지 않는다.

## 9. 개인정보와 보안 경계

SIDEY가 사용할 수 있는 전역 활동 신호는 마지막 시스템 입력 후 경과 시간과 화면 잠금 상태뿐이다. 타이핑 상태는 SIDEY 입력창에서만 발생한다.

다음 정보는 수집하지 않는다.

- 화면 내용
- 활성 애플리케이션 목록
- 다른 애플리케이션에서 누른 키
- 마우스 좌표
- 파일 내용
- 마이크 오디오
- 카메라 영상

E2EE는 현재 설계·구현·검증되지 않았다. 전송 암호화, Postgres, RLS를 근거로 종단간 암호화라고 표현하면 안 된다.

Windows Google OAuth에서 Google과 Supabase Auth가 email·provider identity를 처리하지만 SIDEY 클라이언트는 이 값을 닉네임·캐릭터·친구 노출 정보로 복사하지 않는다. 로컬 로그에는 access/refresh token, OAuth callback query, 메시지 본문, 평문 초대 코드를 남기지 않는다.

## 10. 검증과 승격 기준

### 10.1 자동화 테스트

- 영역: 4개 가장자리 × 3개 길이, 중앙 정렬, 회전, visible frame, 깊이 제한, 모니터 fallback
- 이동: 20개 합성 노드가 3,000 tick 동안 1차원 track과 발 기준선을 유지하고 finite 좌표, 입력창·상호 회피, 겹침 시 idle 해제·가속 통과, 실제 메시지 말풍선의 240pt/s² 분리 가속·72pt/s 상한·8pt 해소·경계 힘 재배분·혼잡 시 안정적인 겹침·일반 목표 복귀
- 상태: 온라인·자리 비움 doze·오프라인 curled sleep·재연결·타이핑, 내 캐릭터 항상 표시, 오프라인 숨김, 방 전환 UUID diff, 최대 8자 닉네임·반투명 배경과 상태 점 5pt 간격, 발 기준 4배 리액션과 이벤트 UUID 중복 제거
- Realtime: backoff 계산을 단위 검증하고, 실서버 2클라이언트에서 한쪽 WebSocket 강제 단절 뒤 자동 재구독·메시지·Presence·`character_pulse` 재수신을 검증
- 메시지: 발신자별 교체, 최대 4개 eviction, 10초 만료, 이동 중 말풍선 추적, 낙관적 성공·실패, 조용히 모드, 미확인 수
- 말풍선: 1자·200자·3줄·프리셋 양 끝·4방향에서 본문과 꼬리 누적 frame이 캔버스 안에 유지하고 실제 메시지 본문만 접선 충돌 범위에 포함하며 타이핑 말풍선은 제외
- 창: 월드 항상 위·클릭 통과, 내 캐릭터 52×52 hotspot만 포인터 수신, composer의 선택 모니터 상단 중앙·노치 아래 10pt 배치와 왼쪽 `×`·Esc·외부 클릭 닫기, 단일·더블클릭 분기와 캐릭터별 1초 리액션 쿨타임, composer 초기 숨김·열기·마지막 전송 뒤 5초 자동 닫힘·타이머 갱신·실패 복구, 기록 일반 창
- 업데이트: Sparkle `2.9.6` 프레임워크·메뉴 항목·피드 URL·EdDSA 공개키가 번들에 포함되고 signed feed와 압축 해제 전 검증을 강제하며, 업데이트 진행 중에는 수동 확인 메뉴를 비활성화
- 에셋: 5개 시트의 240×24 RGBA·10프레임·공통 발 기준선·결정적 hash·Release 번들 포함, 메뉴 아이콘 1x·2x template/unread variant
- 서버: 5번째 성공, 6번째 `member_limit_reached`, 여섯 번째 방 거부, RLS, 중복 닉네임·캐릭터 허용

### 10.2 macOS 장시간 수동·계측 테스트

최대 방 인원 5명을 표시한 실제 앱을 30분 이상 실행하고, 별도 20노드 합성 부하를 병행하며 다음을 모두 확인한다.

- p95 frame time 40ms 이하
- 100ms 이상 main-thread hang 없음
- 지속적인 RSS 증가 없음
- 캐릭터 떨림·NaN·영역 이탈 없음
- 오버레이를 숨기면 SpriteKit이 정지함
- 다중 모니터 연결·분리 fallback
- 화면 잠금·절전·복귀
- Realtime 연결 끊김·재연결과 transient typing 정리

### 10.3 Windows 승격 기준

1. 햄스터 1종 local slice에서 투명·최상위·외부 앱 클릭 통과·52×52 hotspot·composer 포커스·100/125/150/200% DPI를 Windows 11 25H2 x64 실기에서 통과한다.
2. 연결형 햄스터 slice에서 Google PKCE 로그인, 프로필, 방, 메시지, Presence, typing lease, `character_pulse`를 staging의 기존 macOS 클라이언트와 양방향 확인한다.
3. 이 두 게이트 전에는 나머지 4종 캐릭터와 전체 Windows 기능을 구현하지 않는다.
4. 최종 5명 월드를 2시간, 20노드 합성 부하를 30분 실행해 p95 frame time 40ms 이하, 100ms 이상 UI-thread hang 없음, warm-up 후 working set 20MB 초과 증가 없음, GDI/USER handle·COM surface 지속 증가 없음을 확인한다.
5. 현재 보조 모니터 실기 검증은 공개 alpha 완료 조건에서 제외하되 합성 모니터 geometry 테스트는 통과시키고 release note에 mixed-DPI·연결 해제 실기 미검증을 명시한다.

### 10.4 macOS alpha 배포 절차

1. 전체 macOS 단위·창 정책 테스트와 20노드 합성 부하를 통과한다.
2. 로컬 Supabase에서 5명 제한과 SQL 테스트를 통과한다.
3. Developer ID Application 인증서와 Hardened Runtime으로 앱·로그인 항목·Sparkle의 중첩 코드를 서명하고 Apple 공증 뒤 ticket을 staple한다.
4. `scripts/package_macos_release.sh`로 버전·빌드 번호, arm64 아키텍처, 번들 메타데이터, 코드 서명, ZIP, SHA-256을 검증한다. `CFBundleVersion`은 이전 공개 빌드보다 반드시 커야 한다.
5. 검증된 커밋을 `main`에 푸시하고 동일 커밋에 버전 태그와 GitHub pre-release 또는 release를 만든 뒤, 그 태그에 검증된 ZIP을 업로드한다.
6. `scripts/macos/prepare_sparkle_appcast.sh`로 ZIP의 EdDSA 서명과 signed appcast를 생성한다. 이 도구가 Developer ID, Hardened Runtime, stapled notarization, 앱의 공개키·피드 URL·보안 플래그를 모두 통과하고, GitHub Release에서 다시 받은 ZIP이 로컬 검증본과 바이트 단위로 같아야 한다.
7. Release ZIP URL이 실제로 내려받아지는지 확인한 뒤 생성된 `updates/appcast.xml`을 커밋·푸시한다. appcast를 먼저 게시하면 클라이언트가 존재하지 않는 ZIP을 보게 되므로 순서를 바꾸지 않는다.
8. 30분 장시간 기준을 통과하기 전에는 stable 배포로 표시하지 않는다.

Sparkle `2.9.6`이 앱에 내장되며 메뉴바 `업데이트 확인…`에서 수동 확인할 수 있다. 자동 확인은 Sparkle의 사용자 동의 흐름을 사용하고, 익명 system profiling은 활성화하지 않는다. appcast와 ZIP은 서로 다른 검증 대상이므로 둘 다 `sidey-app` EdDSA 키로 서명하며 `SURequireSignedFeed`와 `SUVerifyUpdateBeforeExtraction`을 강제한다. 피드는 GitHub raw HTTPS URL, 설치 파일은 GitHub Releases를 사용한다.

Developer ID 활성화 전에는 서명된 appcast를 update item 없이 유지한다. Sparkle이 없는 기존 alpha 사용자는 Sparkle 내장 빌드로 한 번 수동 교체해야 하며, 이후 앱 내부 업데이트를 사용한다. 사용자 세션과 설정은 앱 번들 외부에 있어 교체·업데이트 후에도 유지된다. Sparkle 개인키는 저장소나 CI 로그에 넣지 않고 release operator의 로그인 Keychain과 암호화한 오프라인 백업에만 둔다.

자동화 테스트와 alpha 배포가 장시간 수동 기준이나 정식 배포 조건을 통과했다는 뜻은 아니다.

### 10.5 Windows alpha 배포 절차

1. Windows 전체 단위·계약·창 정책 테스트와 10.3의 실기·장시간 기준을 통과한다.
2. staging Google OAuth·RLS·private Realtime을 통과한 뒤 같은 Google provider·redirect를 production에 적용하고 다시 확인한다.
3. CI에서 .NET·Windows App SDK 런타임을 포함한 `win-x64` self-contained 산출물을 만들고 `SIDEY-Windows-x64-0.3.0-alpha.1.zip`·SHA-256을 검증한다.
4. 검증된 커밋에 `v0.3.0-alpha.1` 태그와 GitHub pre-release를 만들고 미서명 SmartScreen 경고, 수동 업데이트, ARM64·MSIX·다중 모니터 실기 미검증을 명시한다.
5. Windows 자동 업데이트·코드 서명·MSIX를 구현했다고 표현하지 않는다.
