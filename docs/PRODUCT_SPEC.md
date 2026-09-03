# SIDEY 제품 기획서

- 문서 버전: 0.8
- 최종 갱신: 2026-09-04
- 상태: macOS `v1.0.5`(build 16) 정식 공개·production 상점 판매 잠금, Windows 네이티브 `v1.0.5` 정식 출시
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
- macOS 설정과 메뉴바에서 유료 캐릭터 4종 상점을 제공하되 production은 출시 예정 잠금으로 배포한다. 격리된 Sidey-dev만 Google identity를 연결한 뒤 PortOne 테스트 결제를 시작한다.

### 2.2 Windows 구현 목표

- Windows 11 25H2(build 26200) 이상 x64 네이티브 클라이언트를 C#/.NET 10 LTS·WinUI 3·Win32로 구현한다.
- 일반 창은 SIDEY 브랜드의 Windows Fluent UI로 만들고, 투명 월드는 전용 Win32 HWND가 소유한다. `PixelCharacterCatalog`와 하나의 `UpdateLayeredWindow` 렌더러가 무료 5종과 다른 사용자가 선택한 유료 4종의 사전 생성 BGRA frame을 표시한다. Windows 프로필 선택은 무료 5종만 제공하고 구매는 지원하지 않는다.
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
- `website/`의 정적 HTML·CSS·최소 JavaScript만 배포한다. 랜딩과 정책 페이지는 제품 소개와 다운로드·상점 안내를 담당하며 로그인·그룹·메시지 기능을 제공하는 웹 클라이언트가 아니다.
- macOS 기본 CTA는 현재 공개 버전의 고정 공증 DMG를 직접 가리키고 `brew install --cask sidey-app/tap/sidey`를 함께 제공한다. 다음 공개 릴리스에서는 버전 표기와 고정 DMG URL을 같은 배포 작업에서 갱신한다.
- Windows 기본 CTA는 현재 정식 버전의 고정 MSI를 직접 가리킨다. 저장소의 다운로드 버튼은 Release 검증 전까지 비활성 상태로 두고, Pages Actions가 정식 Release의 단일 MSI를 확인한 배포 아티팩트에서만 링크로 활성화한다.
- Windows 업데이트 채널은 macOS Release와 분리된 `windows-v<version>` 태그와 `website/windows-latest.json`을 사용한다. 호환 경로 `website/windows/update.json`은 같은 내용을 유지한다. 저장소 manifest의 `sha256`은 `null`로 두고, Pages Actions가 Release MSI를 다시 내려받아 계산한 64자리 SHA-256으로 두 배포 manifest를 완성한다. Release가 없거나 draft·pre-release이거나 MSI 외 자산이 있으면 기존 Pages를 교체하지 않는다.
- 첫 화면에서 플랫폼·아키텍처·정식 배포 상태를 밝히고, 개인정보 수집 경계, E2EE 미지원, 보안 화면·DRM·권한 상승 앱·모든 독점 전체화면 위 표시를 보장하지 않는다는 제한을 숨기지 않는다.
- `/contribute/asset-previewer/`는 랜딩 내비게이션에 넣지 않는 공개 컨트리뷰터 도구다. 공식 햄스터 세트를 기본으로 불러오고 사용자가 넣은 `base.png`·`throw_hit.png`·`sprite.png`의 형식과 동작을 현재 탭에서만 검증한다. 파일은 서버로 보내거나 저장하지 않으며 외부 이미지 URL이나 사용자 JavaScript를 받지 않는다. 녹화는 프리뷰 Canvas의 30 FPS stream만 최대 30초 무음으로 저장하고 카메라·마이크·화면 녹화 권한을 요청하지 않는다.
- `main`의 웹 파일 또는 Pages 워크플로가 바뀌면 GitHub Actions가 `website/`만 Pages artifact로 올리고 `github-pages` 환경에 배포한다. custom domain과 별도 Sites 호스팅은 사용하지 않는다.

### 2.5 공개 업데이트 문서와 향후 계획

- README는 짧은 제품 소개와 macOS·Windows 설치 안내를 유지하고, 그 아래에 플랫폼별 날짜·버전·최신 변경과 공통 향후 계획을 제공한다. 기술 스택·아키텍처·백엔드·개발·빌드 설명은 공개 README에 두지 않는다.
- `docs/releases/*`와 GitHub Release 본문은 일반 사용자가 체감하는 결과를 짧은 문장으로 설명한다. 설치 행동과 지원 환경, 데이터 위험처럼 사용자가 알아야 하는 내용은 유지하되 DB·schema·API·클래스·파이프라인 세부는 제외한다.
- 공개 향후 계획은 새로운 말풍선 디자인, Windows 기능 안정화, 캐릭터 드래그 앤 드롭, 캐릭터 효과음, macOS 이모지 입력 버그 개선, 다른 사람 캐릭터 클릭 이펙트다. 이는 완료 기능이나 일정 약속이 아니며 현재 MVP 범위를 바꾸지 않는다.
- 캐릭터 드래그 앤 드롭은 현재 제거된 기능으로 유지한다. 기본 클릭 통과와 명시적 상호작용 모드를 보존하는 별도 제품 결정과 입력 설계가 확정된 뒤에만 다시 구현한다.

### 2.6 로컬 운영 어드민

- `/Users/aryu/Documents/sidey-admin`은 배포 제품이나 웹 클라이언트가 아닌 독립 로컬 운영 도구다. 운영 Supabase 하나만 조회하며 `개요 / 채팅방 / 사용자 / 다운로드 / 결제` 메뉴를 제공한다.
- Vite·React·TypeScript와 React Query를 사용하고 route는 주소 연결만 담당한다. 메뉴별 feature가 API query, loading·empty·error·background refresh 상태와 화면 구성을 소유한다.
- Node API만 `SUPABASE_SECRET_KEY`를 읽고 브라우저 번들에는 Supabase URL·Secret Key를 포함하지 않는다. 서버는 production project ref `whtejsviizgejauasqqt`를 고정 검증하며 `127.0.0.1`에만 bind하고 Host·Origin·production CSP를 강제한다.
- 이메일은 운영 식별을 위해 전체 표시하되 값이 없는 익명 계정은 `이메일 없음`으로 표시한다. UUID는 축약 표시하고 복사할 때 전체 값을 사용한다.
- 메시지 본문, 초대 코드·hash, checkout token, 카드 정보, PortOne Store·Channel·payment 식별자는 RPC가 반환하지 않는다. 어드민에는 mutation endpoint나 삭제·환불·지급 action을 두지 않는다.
- 라이트·다크 테마를 지원하고 SIDEY 앱 아이콘과 기존 24×24 캐릭터 sprite의 첫 frame을 정수 nearest-neighbor로 사용한다.

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
- Windows의 펼친 그룹 카드는 활성 여부와 관계없이 모든 멤버에게 `그룹 나가기` 버튼을 표시한다. 선택한 그룹 이름을 표시한 확인을 거쳐 해당 UUID의 `leave_room`을 호출하며, 방장에게는 가장 먼저 참여한 남은 멤버로 방장이 이전되고 마지막 멤버라면 그룹이 삭제된다는 영향을 안내한다.
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

캐릭터 물체 던지기는 `우클릭 후 던지기` 설정으로 입력 방식만 바꾼다. 기본값은 OFF이며 화면에 표시되는 다른 멤버의 52×52 hotspot을 Presence 상태와 무관하게 항상 표시해 한 번 클릭하면 즉시 던진다. ON이면 평소 친구 hotspot을 만들지 않고 내 캐릭터를 우클릭한 뒤 10초 동안만 표시한다. 우클릭을 다시 하면 10초로 갱신되고 활성 시간에는 여러 친구에게 계속 던질 수 있다. 두 방식 모두 송신자 기준 0.5초 쿨타임을 적용한다. 온라인·자리 비움·오프라인·재연결 캐릭터를 모두 대상으로 허용하며 자기 자신만 제외한다.

송신자는 약 0.4초 throw 동작을 재생하고 0.2초에 물체를 놓는다. 각 클라이언트가 현재 로컬 캐릭터 위치로 화면 안쪽을 향하는 2차 베지어 궤적을 계산하며 좌표는 전송하지 않는다. 호 높이는 거리의 18%를 24~96pt로 제한하고 비행 시간은 `0.35 + 거리 / 1600`초를 0.35~0.95초로 제한한다. 물체 회전은 약 83ms 간격이며 이동 중인 대상의 현재 몸통 위치로 종점을 매 frame 보정한다. 충돌 이펙트는 약 0.24초, hit 동작은 약 0.44초다. hit 중 대상 이동만 정지하고 기존 산책 목적지는 보존하며 연속 피격은 hit을 처음부터 다시 시작한다. 비행 중 Presence 상태가 바뀌어도 대상 노드가 화면에 남아 있으면 충돌 이펙트와 hit 동작을 모두 재생한다. 최근 이벤트 UUID는 256개, 활성 투사체는 월드당 32개로 제한한다.

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

유료 catalog는 `pixel_starlight_upalupa` 별빛 우파루파(1,900원), `pixel_guinea_pig` 아기 기니피그(990원), `pixel_monkey` 아기 원숭이(990원), `pixel_chinchilla` 아기 친칠라(990원)다. macOS 선택 목록에는 무료 5종과 현재 계정이 활성 소유권을 가진 유료 캐릭터만 표시한다. 환불 또는 소유권 만료 시 로컬 선택을 햄스터로 되돌리며, 다른 사용자의 유료 캐릭터를 렌더링할 때는 보는 사람의 소유권을 요구하지 않는다. 친칠라의 canonical ID는 `pixel_chinchilla`이고 과거 `pixel_koala`는 호환 alias로만 정규화한다.

결제 확인과 동시에 디지털 캐릭터 사용권 제공을 시작한다. 제공 시작 뒤 단순 변심에 따른 청약철회와 환불은 허용하지 않으며, 사용권 미제공·표시 또는 계약 내용 불일치·중복 결제·본인이 승인하지 않은 결제 등 관련 법령상 사유가 확인된 경우에만 전액 환불한다. 환불은 PortOne 취소 상태를 다시 확인한 뒤 구매 entitlement를 회수하며, 법이 보장하는 취소·피해구제 권리는 제한하지 않는다.

전환 시 지정 활동 계정 5개(`9c169b9f-e95c-4a3e-b0e9-ab329a035c6f`, `e68ec90f-6f5a-4a93-be0a-364f6a3f378f`, `839ec4d5-ada1-466d-bb1d-2a100dea2185`, `b4877c8c-3147-46ef-b035-5dbb95e86d4f`, `f0462289-2465-4a27-b90d-d4820ccf4b8c`)에는 기니피그·원숭이·친칠라 complimentary entitlement를 각각 지급한다. 주문과 분리된 총 15개 지급이며 `grant_reference`로 감사 근거를 남긴다. Windows는 무료 5종 선택과 구매 미지원 정책을 유지하되 유료 4종을 원격 친구 모습으로 렌더링한다.

- 논리 프레임: 24×24 픽셀
- 화면 크기: 2배 정수 확대, 약 48pt
- 필터: nearest-neighbor
- 팔레트: 위 표의 종별 기본 팔레트를 사용하며, 공통 픽셀 명암 규칙을 유지한다.
- 애니메이션: idle 2프레임, walk 4프레임, doze 2프레임, offline curled sleep 2프레임
- 실시간 그림자와 3D 런타임 없음

승인 원본은 최상위 `assets/v1`에 둔다. `manifest.json`이 9종 캐릭터의 `base.png`·`throw_hit.png`, 5종 투척물의 `sprite.png`, 캐릭터→투척물 매핑, fallback과 SHA-256을 단일 관리한다. macOS·Windows·웹에 있는 같은 PNG와 Windows BGRA는 배포용 mirror이며 직접 편집하지 않고 중앙 검사기로 원본과 일치하는지 확인한다. 작업 중 concept·candidate·확대 review 이미지와 일회성 importer는 승인 원본에 포함하지 않는다.

`manifest.json`의 `licensing`에 등록된 유료 캐릭터 4종과 전용 투척물 4종 및 그 mirror에는 `SIDEY Paid Asset License 1.0`을 적용한다. 파일은 공개 저장소에서 열람할 수 있지만 오픈소스 에셋은 아니며, 공식 SIDEY의 계정·entitlement 규칙에 따른 표시와 SIDEY 개발·검토 목적의 로컬 확인만 허용한다. 다른 앱·게임·웹사이트·상품에서 복제·추출·수정·재배포·판매할 수 없다. 유료 에셋 기여는 PR 제출만으로 판매나 수익 배분이 확정되지 않으며, 판매·정산·환불·배포 권한을 정한 별도 서면 계약 뒤에만 병합한다.

기본 시트는 240×24 RGBA이며 idle 2·walk 4·doze 2·offline 2프레임을 가진다. 물체 던지기 action 시트는 9종 각각 192×24 RGBA이며 24×24 셀의 throw 4프레임과 hit 4프레임을 가진다. 물체 시트는 5종 각각 192×16 RGBA이며 16×16 셀의 고정 중심 회전 8프레임과 충돌 4프레임을 가진다. 무료 5종은 비대칭 패치와 봉제선이 있는 패치 말랑공을 공유하고, 기니피그는 미니 파프리카, 원숭이는 바나나, 친칠라는 매듭 달린 먼지목욕 모래주머니, 별빛 우파루파는 회전 광점이 있는 별빛 구슬을 사용한다. 투명 배경, sRGB, 8-bit RGBA, hard alpha, 아래쪽 3px 발 기준선과 integer nearest-neighbor를 유지하고 안티앨리어싱과 실시간 그림자는 사용하지 않는다. 알 수 없는 캐릭터 ID는 햄스터 action과 패치 말랑공으로 fallback한다.

별빛 우파루파처럼 ambient sparkle과 더블클릭 particle burst를 제안할 수 있지만 이는 PNG가 아니라 별도 렌더러 효과다. 성능·색상·밀도·지속 시간을 검토하고 각 플랫폼에서 구현해야 하며 에셋 제출만으로 제품에서 자동 활성화하지 않는다. 공개 프리뷰어의 효과 토글은 제안 영상을 위한 로컬 시뮬레이션일 뿐 앱 설정이나 서버 payload를 만들지 않는다.

## 5. 메시지와 타이핑

### 5.1 데이터 흐름

- Postgres가 메시지 원본이다.
- 메시지는 생성 후 7일이 지나면 서버의 일일 정리 작업으로 영구 삭제한다.
- Presence는 연결·온라인·자리 비움 상태에 사용한다.
- Broadcast는 SIDEY 입력창의 타이핑, `character_pulse`, `character_throw`처럼 저장하지 않는 이벤트와 서버가 발행하는 DB 변경 식별자에만 사용한다. 클라이언트 직접 발행은 Presence만 허용하며 `character_throw`는 전용 인증 RPC만 사용한다.
- 각 방은 멤버 변경마다 증가하는 `realtime_epoch`을 가지며 DB·ephemeral private topic을 분리한다. DB event에는 message UUID와 operation만 담고, macOS는 RLS를 거쳐 해당 row를 재조회한 뒤 확정한다.
- macOS 클라이언트는 5초마다 WebSocket과 각 방 채널의 실제 구독 상태를 확인한다. 비정상이 8초 이상 지속되면 채널 및 수신 스트림을 재생성하고, 실패가 이어지면 8초·16초·최대 30초 간격으로 재시도한다.
- 재구독 중에는 로컬 상태를 재연결로 표시한다. 성공하면 현재 Presence를 다시 publish하고 방·멤버 snapshot과 최근 메시지를 다시 읽어 단절 중 누락된 가입·메시지를 보정한다.
- macOS는 전체 방 채널 구독 상태인 `transportConnected`, 현재 활성 방 채널 구독 상태인 `activeRoomTransportConnected`, 단절 복구 보정 상태인 `recoveryReconciled`를 별도로 관리한다. 원격 Presence 캐시는 실제 transport 단절에서만 폐기한다. 자기 캐릭터와 던지기 상호작용은 활성 방 transport가 끊긴 동안에만 회색·비활성 상태를 사용하며, 절전 복귀 뒤 해당 transport가 복구되면 다른 방 또는 snapshot·메시지 보정이 진행 중이어도 현재 로컬 Presence와 상호작용을 즉시 되돌린다. 프로필·닉네임·방 이름 `structure_changed`는 연결 상태를 바꾸지 않고 metadata snapshot만 갱신하며, 조회 실패도 transport를 online으로 유지한 채 metadata 작업만 backoff 재시도한다.
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
- 내 캐릭터 단일 클릭 또는 메뉴바 `메시지 작성`으로 열고 즉시 포커스한다. 월드와 캐릭터 hotspot은 모든 macOS Space에 유지하지만 입력창은 열기를 요청한 현재 Space로 이동해 표시한다.
- 내 캐릭터 더블클릭은 리액션을 실행하고 입력창은 열린 상태로 유지한다.
- 캐릭터 또는 입력 패널 클릭으로 앱이 활성화될 때는 수동 앱 재열기로 처리하거나 설정창을 열지 않는다.
- 왼쪽 `×`, 내 캐릭터 재클릭, Esc 또는 입력창 외부 클릭은 draft를 보존하고 닫으며 `typing_stop`을 보낸다. 외부 클릭은 전역 마우스 이벤트나 좌표를 수집하지 않고 입력 패널의 키 포커스 상실로 판정한다.
- 유효한 메시지를 전송하면 입력창을 유지하고 마지막 전송 시점부터 5초 뒤 자동으로 닫는다. 5초 안에 다시 전송하면 타이머를 갱신한다.
- 낙관적 전송 실패 시 예약 닫힘을 취소하고 실패 항목을 원래 방 outbox에 보존한 뒤, 그 방이 아직 활성 방이면 입력창을 열어 포커스한다. 현재 draft는 실패 본문으로 덮지 않는다.
- 오버레이 숨김, 활성 방 전환, 현재 사용자 노드 제거 시 입력창을 닫는다.

월드 패널 전체는 `ignoresMouseEvents`로 클릭을 통과시킨다. 내 캐릭터 위의 52×52pt 투명 `NSPanel`은 최대 15Hz·1pt 임계값으로 위치를 따라가며 메시지·리액션 클릭과 우클릭을 받는다. `우클릭 후 던지기`가 OFF이면 연결된 활성 방에서 화면에 표시되는 모든 친구마다 Presence 상태와 무관하게 같은 크기의 투명 hotspot을 항상 유지하고, ON이면 내 캐릭터 우클릭 뒤 10초 동안만 만든다. 설정 변경, 오버레이 숨김, 방 전환, Realtime 단절, 현재 사용자 노드 제거 시 10초 상태와 친구 hotspot을 즉시 재구성한다. 전역 마우스 hook·전역 좌표 수집·클릭 재주입은 사용하지 않는다.

설정 토글 제목은 `우클릭 후 던지기`, 설명은 `끄면 친구 캐릭터를 바로 클릭할 수 있고, 켜면 내 캐릭터를 우클릭한 뒤 10초 동안만 클릭할 수 있습니다.`다. 기본값은 OFF다. 따라서 OFF에서는 친구 캐릭터 52×52 영역이 뒤 앱 클릭을 가로채지만 월드의 나머지 투명 영역은 계속 클릭을 통과시킨다.

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

- 설정과 메뉴바의 `꾸미기·상점`은 같은 화면을 열고 우파루파·기니피그·원숭이·친칠라 4종을 등록 순서대로 2열 그리드에 표시한다. 구매 완료 상품도 목록에서 제거하지 않고 `보유 중` 상태로 표시한다.
- `StoreAvailability`는 번들 배포 채널에서 결정한다. production은 `.comingSoon`, development는 `.enabled`이며 런타임 설정이나 원격 응답으로 production 잠금을 풀 수 없다.
- production은 각 상품 카드 전체를 `Color.black.opacity(0.68)`로 덮고 흰 픽셀 자물쇠와 `추후 오픈 예정입니다.`만 접근성에 노출한다. 카드의 인터랙티브 콘텐츠는 접근성 트리에서 숨긴다.
- production 잠금 경로는 구매 버튼, 상태 새로고침, Google 연결, 반응 미리보기, `TimelineView`, 별 애니메이션 Task를 생성하지 않는다. `AppCoordinator.purchase`도 production 채널 요청을 거부하고 운영 서버는 `sales_enabled=false`를 유지한다.
- development는 오버레이 없이 실제 카드·상태 조회·Google 연결·PortOne 테스트 결제·반응 미리보기를 활성화한다. 상품별 상태와 구매 action은 `AppModel`·`AppCoordinator`·`SideyBackend`가 소유한다.

### 6.5 Windows 창과 트레이

- 설정 창은 화면 크기와 DPI에 맞춰 1000×760 DIP 안팎의 권장 크기로 열고 860×640 DIP까지 줄일 수 있다. 창 너비가 960 DIP 미만이 되면 왼쪽 탐색은 210 DIP의 제목·아이콘 보기에서 48 DIP 아이콘 레일로 자동 전환하며, 최소 폭에서도 아이콘 레일을 없애지 않는다. 너비가 다시 확보되면 자동으로 펼치고 전환에는 WinUI `NavigationView`의 표준 애니메이션을 사용한다. WinUI `TitleBar`가 앱 아이콘·이름과 실제 방문 이력 기반 뒤로가기·탐색 열기 버튼을 시스템 caption 버튼 왼쪽에 배치한다. 최소 크기는 리사이즈 뒤 창을 되돌리지 않고 Win32 `WM_GETMINMAXINFO`에서 tracking size로 제한해 경계 드래그가 깜빡이지 않게 한다.
- Windows 최근 기록의 40 DIP 캐릭터 슬롯은 시스템 accent 10% 배경과 12 DIP 모서리를 사용한다. 최근 기록과 그룹 설정의 현재 사용자 `나` 표식은 모두 accent 글자와 accent 12% 배경을 사용하며 라이트·다크 테마에 맞춰 갱신한다.
- Windows 그룹 설정의 펼친 각 카드에는 `그룹 나가기`를 이름 변경·삭제와 같은 하단 작업 영역에 표시한다. 나가기·이름 변경·삭제·추방은 다른 그룹 mutation 중 함께 비활성화한다.
- 월드는 WinUI XAML 창에 투명 표현을 위임하지 않고 `WS_POPUP` 기반 전용 Win32 HWND가 소유한다. 무료 5종과 유료 4종은 24px 원본에서 정수 nearest-neighbor로 만든 premultiplied BGRA frame을 같은 `UpdateLayeredWindow` 렌더러로 표시하며 tick마다 bitmap이나 surface를 새로 할당하지 않는다.
- 월드 HWND는 작업 표시줄·Alt-Tab에 나타나지 않고 활성화되지 않으며 외부 앱으로 포인터를 통과시킨다.
- 내 캐릭터 상호작용 52×52 hotspot은 별도 HWND가 소유하고 최대 15Hz·1 DIP 임계값으로 위치를 갱신한다. `우클릭 후 던지기`가 OFF이면 화면에 표시되는 친구별 hotspot HWND를 Presence 상태와 무관하게 계속 유지하고, ON이면 내 캐릭터 우클릭 뒤 10초 동안만 만든다. 전역 마우스 hook·전역 좌표 수집은 금지한다.
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
- 캐릭터별 throw/hit frame, 비행·충돌 이펙트, 최근 throw 이벤트 UUID 256개와 활성 투사체 최대 32개
- hit 중 이동 정지와 기존 산책 목적지 보존
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

`OverlayWindowGroup`은 composer 표시 상태, 내 캐릭터 단일·더블·우클릭 패널, `우클릭 후 던지기` 설정에 따른 10초 타이머와 최대 11개 친구 hotspot 생명주기를 소유한다. `AppCoordinator`는 `character_pulse` 송수신과 캐릭터별 1초 쿨타임, throw 대상 검증·0.5초 쿨타임·이벤트 생성·로컬 재생·서버 호출을 소유한다. `AppModel`에는 영구 `requiresRightClickToThrow`만 저장하고 화면 좌표, 활성화 타이머나 애니메이션 frame을 저장하지 않는다.

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

환경설정 schema 8은 `requiresRightClickToThrow`를 추가하며 새 설치와 schema 7 이하 migration 기본값은 `false`다. 기존 Keychain 전환 완료 여부와 닉네임·방·오버레이 값은 그대로 유지한다. 과거 frame, lock, scale, screen 값은 디코딩만 지원하며 마이그레이션 결과는 기존 화면 식별자를 가능한 경우 유지한 `하단·전체`다.

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
- `Sidey.Overlay`는 전용 Win32 message-loop thread와 30FPS 고정 step을 소유하고 불변 `WorldSnapshot`을 UUID diff로 반영한다. 위치·속도·animation frame은 앱 세션 상태에 저장하지 않는다. 무료 5종과 유료 4종 기본 시트, 승인된 throw/hit·물체 PNG를 BGRA frame으로 시작할 때만 변환·캐시하고 종료 시 모두 해제하며 tick마다 bitmap·surface·projectile buffer를 새로 할당하지 않는다. Debug 검증 모드는 같은 렌더러의 캐릭터 목록만 햄스터로 제한한다. 유료 source character 이벤트는 해당 캐릭터의 action과 서버 source character ID에 맞는 고유 물체를 표시하고, 알 수 없는 ID만 햄스터와 패치 말랑공으로 fallback한다.
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

적용 완료된 과거 commerce migration과 Toss 거래는 감사 이력으로 보존하고 수정하지 않는다. 신규 forward-only `20260902050000_paid_characters_portone_v2.sql`은 다음 계약을 추가한다.

- migration 시작 단계에서 운영 판매를 `false`로 잠그고 legacy pending 주문을 취소한다.
- 우파루파의 990원 가격은 비활성 이력으로 남기고 1,900원 활성 가격을 추가한다. 기니피그·원숭이·친칠라 상품과 각 990원 가격을 추가한다.
- `commerce_entitlements.grant_kind`는 `purchase | complimentary`, `grant_reference`는 주문 없는 지급 근거를 기록한다. `upsert_profile`은 상품 등록된 4종 모두 활성 entitlement를 검사한다.
- PortOne V2 결제 상태에는 payment ID, Store ID, Channel Key, V2, TEST/LIVE, 상태, KRW, 서버 주문 금액, `EASY_PAY` 일치를 요구한다. event ID와 payload hash를 함께 저장해 중복 웹훅과 상충 payload를 분리한다.
- 직접 Toss 실행 RPC 권한, Edge Function, 웹 SDK·CSP·문구·시크릿을 제거한다. 과거 Toss payment row는 삭제하지 않는다.

forward-only `20260903000000_commerce_refund_policy_v2.sql`은 기존 주문에 저장된 결제 당시 동의 원문을 바꾸지 않고, 새 checkout의 정책 버전을 `2026-09-03-portone-v2`로 올려 제공 시작 뒤 단순 변심 환불 불가와 관련 법령상 환불 사유를 명시한다.

forward-only `20260903010000_character_throw.sql`은 `broadcast_character_throw(p_room_id, p_realtime_epoch, p_event_id, p_target_user_id)` 전용 RPC를 추가한다. 서버는 인증, 최신 room epoch, 송신자·대상 멤버십, 자기 자신 대상 금지와 필수 UUID를 검증하고 송신자 프로필에서 `source_character_id`를 읽는다. 송신자당 10초 20회 제한을 적용한 뒤 schema version, room/event/actor/target UUID와 source character ID만 현재 private ephemeral topic의 `character_throw`로 발행한다. 이벤트는 Postgres 메시지나 기록에 저장하지 않고 재접속 뒤 재생하지 않는다.

Edge Functions는 책임을 다음처럼 분리한다.

- `commerce-order`: 인증·Google 연결·상품·소유 여부를 확인하고 서버 가격의 PortOne `paymentId`와 256-bit checkout token hash를 생성한다.
- `commerce-checkout`: token과 정책 동의를 확인한 뒤 `store_id`, `channel_key`, `payment_id`, 서버 가격, `CURRENCY_KRW`, `EASY_PAY`, redirect URL을 반환한다.
- `commerce-complete`: PortOne API에서 결제를 재조회하고 모든 결제 사실이 일치할 때만 entitlement를 지급한다.
- `commerce-webhook`: `jsr:@portone/server-sdk@0.19.0`으로 raw body 서명을 검증한 뒤 PortOne API를 다시 조회한다.
- `commerce-refund`: 별도 운영 키와 멱등키를 요구하고 PortOne 전액 취소·재조회가 확인된 뒤 purchase entitlement만 회수한다.
- `download-metrics-ingest`: GitHub Actions 전용 ingest key를 검사한 뒤 service role로 누적 asset snapshot을 기록한다. 15분 수집 실패는 GitHub 설치 자산 제공과 완전히 분리한다.

`20260903010000_admin_observability.sql`은 private download snapshot과 service role 전용 `admin_overview`, `admin_rooms`, `admin_room_members`, `admin_users`, `admin_downloads`, `admin_payments`, `admin_ingest_download_metrics`를 추가한다. `anon`과 일반 `authenticated`에는 모든 함수 실행 권한을 명시적으로 회수한다. 검색·상태·기간·정렬·page size는 Node API와 SQL 양쪽에서 allowlist 검증한다.

GitHub download collector는 정식 Release만 읽고 `SIDEY-macOS-arm64-v<version>.dmg`, `SIDEY-macOS-arm64-v<version>-homebrew.dmg`, `SIDEY-Windows-x64-v<version>.msi`만 집계한다. 같은 macOS Release에 Homebrew 전용 자산이 없으면 해당 DMG의 기존 누적 수는 직접·Homebrew가 섞인 `legacy_unclassified`로 보존한다. 자산별 최초 snapshot은 누적 총계 baseline으로만 사용하고 관측 전 다운로드를 수집 당일 증가량으로 재분류하지 않는다. 이후 일별·오늘 수치는 Asia/Seoul 자정 전후 snapshot 차이이며 최대 약 15분의 경계 오차와 마지막 수집 시각을 함께 보여준다. 현재 `sidey-app/tap`은 third-party tap이므로 `homebrew/homebrew-cask` 공식 30/90/365일 익명 통계를 제공받지 못하며, 공식 Cask 편입 전에는 교차 확인 수치를 비워 둔다.

공개 웹사이트는 4종·가격·macOS 앱 내 구매 경로·구매와 환불 조건을 `store.html`에 고정형 사용자 문구로 표시한다. 상점은 결제·개인정보 설명 카드와 랜딩 하단에 이미 있는 판매자 정보를 반복하지 않고 관련 정책 링크만 제공한다. 한국어 제목과 본문에는 적절한 폭과 `word-break: keep-all`, `text-wrap`을 적용해 한 글자만 다음 줄에 남는 줄바꿈을 막고, 상점 타이포그래피는 홈 랜딩보다 작은 페이지 전용 크기를 사용한다. 상품 소개에는 production·staging·Sidey-dev·테스트 채널·출시 준비 상태 같은 내부 운영 정보를 노출하지 않는다. `checkout.html`과 `checkout-result.html`은 상품 ID별 이름·가격·이미지를 사용하고 공개 구매 링크로 노출하지 않으며 staging/dev 주문 token으로만 접근한다. 결제 카드 정보는 SIDEY가 수집하지 않고 PortOne을 통해 열린 실제 PG 결제창이 처리한다.

기존 짧은 초대 코드는 migration에서 비활성화한다. 방장은 새 macOS 클라이언트에서 한 번 재발급해야 하며 public room 조회와 Realtime payload 어디에도 invite hash·version이 포함되지 않는다. macOS hotfix와 migration은 호환 순서로 배포하고 구버전의 기존 topic 계약은 유지하지 않는다.

임시로 방 정원을 20명으로 늘렸던 staging migration은 운영에 적용되지 않았고 `main`에서도 제거한다. 20명 조건은 렌더러 합성 부하 테스트에만 사용하며 제품 정원은 12명이다.

`SIDEY-staging`에는 production과 같은 migration·RLS·private Realtime 정책을 적용하되 별도 후속 SQL로 `sales_enabled=true`, `payment_environment=test`만 설정한다. PortOne test Store·Channel·Webhook은 staging 함수에만 연결한다. production은 판매 `false`와 PortOne 시크릿 미설정을 유지한다. 익명 사용자도 기존 `auth.users` UUID를 사용하므로 신규 membership schema는 추가하지 않는다.

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

macOS commerce 로그와 공개 URL에는 Google OAuth token, 결제사 비밀키, service-role key, 일회용 주문 token, 전체 결제 식별자를 남기지 않는다. 결제 성공 redirect만으로 소유권을 지급하지 않고 PortOne V2 재조회, 결제 당시 정책 동의와 Postgres 기록이 모두 일치해야 한다. 카드 번호·결제 비밀번호는 SIDEY가 수집하지 않는다.

## 10. 검증과 승격 기준

### 10.1 자동화 테스트

- 영역: 4개 가장자리 × 3개 길이의 240pt activity frame과 최대 360pt render frame, 접선 144pt 여유, 중앙 정렬, 회전, visible frame, 깊이 제한, hotspot 원점 변환, 모니터 fallback
- 이동: 20개 합성 노드가 3,000 tick 동안 1차원 track과 발 기준선을 유지하고 finite 좌표, 입력창·상호 회피, 겹침 시 idle 해제·가속 통과, 실제 메시지 말풍선의 240pt/s² 분리 가속·72pt/s 상한·8pt 해소·경계 힘 재배분·혼잡 시 안정적인 겹침·일반 목표 복귀
- 상태: 온라인·자리 비움 doze와 고정 `Zzz`의 부유·alpha 반복·해제 시 action 정리, 오프라인 curled sleep·재연결·타이핑, 내 캐릭터 항상 표시, 오프라인 숨김, 방 전환 UUID diff, 최대 8자 닉네임·반투명 배경과 상태 점 5pt 간격, 발 기준 7배·0.8초 리액션과 이벤트 UUID 중복 제거
- Realtime: current epoch topic 접근, client DB형 Broadcast 거부, 다른 사용자·방 transient event 거부, bounded stream overflow 재동기화, backoff와 generation 기반 snapshot reconciliation, Presence publication 최대 동시 실행 수 1, 활성 방 transport 복구 뒤 다른 방·후속 보정 중 자기 캐릭터의 회색 상태와 던지기 비활성 해제를 검증한다. `character_throw`는 미인증·누락 UUID·stale epoch·송신자/대상 비멤버·자기 자신 대상·10초 20회 초과를 거부하고 payload에 좌표나 클라이언트 지정 source character가 없는지 확인한다. 실서버 2클라이언트에서는 프로필을 즉시·10초·30초 간격으로 연속 변경해 transport 단절 이벤트가 생기지 않는지 확인하고, 별도로 강제 단절과 추방 뒤 자동 재구독·메시지·Presence·`character_pulse`·`character_throw` 격리를 확인한다.
- 메시지: 발신자별 교체, 최대 4개 eviction, 10초 만료, 이동 중 말풍선 추적, 방별 outbox 낙관적 성공·실패, 응답 유실 시 동일 UUID 멱등성, 방 A 실패가 방 B draft를 건드리지 않음, confirmed ledger의 방별 50개·7일 cutoff, 최근 기록 0·1·20·50·51·120개 및 동일 timestamp keyset·페이지 중복 제거·실시간/pending/failed 병합·탈퇴 발신자 fallback·방 전환 취소·창 닫기 해제·추가 조회 실패와 재시도, 기록 캐릭터의 accent 10% 배경과 현재 사용자 표식의 accent 글자·12% 배경, 조용히 모드, 미확인 수, 엄격한 서버 시각 해석
- 말풍선: 1자·200자·3줄·프리셋 양 끝·4방향에서 본문과 꼬리 누적 frame이 캔버스 안에 유지하고 실제 메시지 본문만 접선 충돌 범위에 포함하며 타이핑 말풍선은 제외
- 창: 월드 항상 위·나머지 영역 클릭 통과, 내 캐릭터 52×52 hotspot, 기본 OFF에서 화면에 표시되는 친구별 Presence 상태 무관 52×52 상시 hotspot, ON에서 우클릭 전 통과·우클릭 뒤 10초 활성화·재우클릭 갱신·만료, 설정 전환·숨김·방 전환·단절 시 즉시 재구성, composer의 선택 모니터 상단 중앙·노치 아래 10pt 배치와 멀티 데스크탑 현재 Space 이동, 왼쪽 `×`·Esc·외부 클릭 닫기, 단일·더블클릭 회귀와 throw 0.5초 쿨타임, composer 초기 숨김·열기·마지막 전송 뒤 5초 자동 닫힘·타이머 갱신·실패 복구, 기록 일반 창
- 업데이트: production 채널에 Sparkle `2.9.6` 프레임워크·메뉴 항목·피드 URL·EdDSA 공개키가 번들에 포함되고 signed feed와 압축 해제 전 검증을 강제하며, 업데이트 진행 중에는 수동 확인 메뉴를 비활성화. development 채널은 Sparkle을 시작하지 않고 수동 확인 메뉴도 항상 비활성화
- 에셋: 무료 5종과 유료 4종 기본 시트의 240×24 RGBA·10프레임, throw/hit 시트 9개의 192×24 RGBA·8프레임, 물체 시트 5개의 192×16 RGBA·12프레임, 공통 발 기준선·회전 중심·hard alpha·결정적 SHA-256·Release 번들 포함과 캐릭터→물체/fallback 매핑, 메뉴 아이콘 1x·2x template/unread variant
- 던지기 렌더링: 9종 throw/hit, 5종 물체 매핑, 4개 화면 가장자리, 이동 목표 추적, 다중 피격 재시작, 대상 상태 전환, 방 전환 중 stale 이벤트를 검증한다. 12명이 0.5초마다 던지는 초당 24개 부하에서 활성 투사체 32개 이하, p95 frame time 40ms 이하, 100ms 이상 UI hang과 지속 메모리·handle 증가가 없어야 한다.
- 설정: schema 7 이하에서 `requiresRightClickToThrow=false` migration과 저장·복원·즉시 ON/OFF 전환, 860×640 최소 크기와 1000×760 안팎 권장 크기의 라이트·다크 렌더, 960 DIP 경계의 210→48 DIP 자동 탐색 전환과 최소 폭 아이콘 레일 유지, 상단바의 뒤로가기·탐색 열기와 방문 이력, native 최소 tracking size에서 반복 resize·깜빡임 없음, 옅은 카드 명도, 240pt 컨트롤 영역과 Picker·버튼·토글 오른쪽 정렬, `동작 정보` 제거, 두 사람 그룹 아이콘, 그룹 현재 사용자 표식의 accent 글자·12% 배경, 활성·비활성 그룹별 나가기 확인과 방장 영향 안내·mutation 중 비활성화, 한글 IME 조합 확정 후 닉네임 저장
- 입력 필드: 200자 끝, 한글 조합, 영문 긴 단어, 이모지, Shift+Enter 3줄, 중간 커서 이동·전체 선택, undo·redo, 외부 draft와 잘못된 입력 복구에서 마지막 글자와 커서가 보이고 텍스트 손실·IME 중복 확정·가로 스크롤이 없는지 검증한다.
- 상점: 2열 4종 카드의 독립 상태·정렬과 `보유 중` 유지, entitlement 선택 목록, Google callback·저장소 분리, 860×640·1000×760 라이트·다크 렌더를 검증한다. production은 action 호출과 animation Task가 0개이고 검정 68%·픽셀 자물쇠·잠금 안내만 접근성에 노출되어야 한다.
- commerce 서버·웹: 활성 가격 1,900/990/990/990, 4종 프로필 소유권 검사, complimentary grant·RLS, 판매 기본 잠금, 만료 token, 최신 정책 버전과 단순 변심 환불 불가 동의, PortOne Store·Channel·V2·환경·상태·금액·통화·수단 불일치, 중복 웹훅·서명 오류, 법정 사유 전액 환불과 purchase/complimentary 격리를 검증한다.
- 그룹 설정: 0·1·12명 멤버 목록, 기본 접힘·제목 영역 및 오른쪽 단일 화살표 펼침, `그룹 참가` 문구, 생성·참여·전환별 진행 문구와 라이트·다크 대상 카드 강조, A→B→C 연속 선택에서 C만 commit, UUID 기반 방장 왕관과 펼친 목록 아래 방장 전용 이름 변경·삭제 버튼, 이름 변경 저장·취소, 대상 명시 추방 확인, 영구 삭제 2단계 확인, 활성·비활성·마지막 그룹 삭제 fallback, 초대 코드 복사 성공·실패와 3초 표시·재클릭 갱신·행 제거 취소
- DMG: 660×420 배경, `SIDEY.app`, `/Applications` 심볼릭 링크, 기존 5종 idle 프레임, `.DS_Store`를 자동 생성·마운트 검증하고 Finder에서 아이콘 위치·안내 문구·nearest-neighbor 픽셀 선명도를 수동 확인
- Keychain: schema 6에서 7로 값 보존, 신규 설치 안내 생략, 실행 중 `LAContext` 재사용, 동일 키 읽기 캐시, 동일 데이터 저장 생략, 거부 콜백 1회와 거부 후 추가 Security API 호출 차단
- 서버: 실제 anon/authenticated role의 RLS, 12번째 성공·13번째 거부와 여섯 번째 방 경합, 병렬 초대 제한, invite hash API 비노출, current epoch topic 권한, client Broadcast INSERT 봉쇄, transient event whitelist·rate, `broadcast_character_throw`의 인증·epoch·양쪽 membership·자기 대상·필수 UUID·20회/10초 제한과 서버 source character, 메시지 멱등성·rate, 7일 retention, 비방장 관리 거부와 cascade를 SQL 테스트한다.
- 운영 어드민: 모든 `admin_*` 조회·수집 RPC의 anon·authenticated 거부와 service role 허용, 다운로드 baseline·분리 경로·KST 경계·카운터 증가·정체·역행 거부·수집 지연을 SQL 테스트한다. 로컬 API는 환경변수 누락·잘못된 production ref·LAN Host·외부 Origin·잘못된 query와 upstream 응답을 거부해야 하며 lint·typecheck·unit·production build·Secret 번들 scan과 1280×800·1440×900의 두 테마 Playwright 검증을 통과해야 한다.
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

1. 무료 5종과 원격 유료 4종을 `PixelCharacterCatalog`와 하나의 `UpdateLayeredWindow` 렌더러로 제공하고 asset·frame·발 기준선·방향·fallback 계약을 자동 검증한다. 선택 목록은 무료 5종만 유지한다.
2. 같은 렌더러를 햄스터 1종으로 제한하는 Debug 내부 모드에서 투명·최상위·외부 앱 클릭 통과·52×52 hotspot·composer 포커스·100/125/150/200% DPI를 Windows 11 25H2 x64 실기에서 통과한다. 이 모드는 Release에 노출하지 않는다.
3. 연결형 검증에서 익명 세션 복구·생성, 프로필, 방, 메시지, Presence, typing lease, `character_pulse`, `character_throw`를 staging의 기존 macOS 클라이언트와 양방향 확인한다.
4. 최종 12명 월드를 2시간, 20노드 합성 부하를 30분 실행해 p95 frame time 40ms 이하, 100ms 이상 UI-thread hang 없음, warm-up 후 working set 20MB 초과 증가 없음, GDI/USER handle·COM surface 지속 증가 없음을 확인한다.
5. 보조 모니터의 mixed-DPI와 연결 해제를 실기에서 계속 회귀 검증하고 합성 모니터 geometry 테스트도 유지한다.

### 10.4 macOS 배포 절차

1. 운영 DB에 forward-only commerce migration을 먼저 적용해 `sales_enabled=false`, legacy pending 0건, 활성 가격 4개와 complimentary 15개를 확인한다.
2. production에는 PortOne V2 Edge Functions를 배포하되 PortOne 시크릿은 설정하지 않고 실패 폐쇄를 확인한다. 예전 `commerce-return`과 Toss 시크릿은 제거한다.
3. 전체 Swift 테스트, 로컬 2클라이언트 Realtime 통합 테스트, pgTAP, 웹 계약 테스트와 Release 빌드를 통과한다.
4. Developer ID Application과 Hardened Runtime으로 앱·로그인 항목·Sparkle 중첩 코드를 서명하고 Apple 공증 뒤 ticket을 staple한다.
5. `scripts/package_macos_release.sh`로 arm64·production 메타데이터, DMG·ZIP·SHA-256을 검증한다. production 카드 잠금과 구매 action 0회를 최종 확인한다.
6. 검증된 동일 커밋에 릴리스 태그와 GitHub Release를 만든 뒤 DMG와 ZIP을 업로드하고, 다시 받은 파일이 로컬 SHA-256과 같은지 확인한다.
7. Release ZIP이 실제 다운로드된 뒤에만 `scripts/macos/prepare_sparkle_appcast.sh`로 signed appcast를 게시한다. 이어 웹 다운로드 링크와 `sidey-app/homebrew-tap` Cask를 같은 DMG URL·SHA-256으로 갱신한다.
8. `SIDEY-staging`이 준비되면 같은 migration·Google OAuth·PortOne test Store/Channel/Webhook을 구성하고 Sidey-dev로 주문→결제→지급→프로필 선택→전액 환불→회수를 실제 검증한다.
9. 추후 실판매는 별도 결정과 법률·운영 검증 뒤 production 앱의 `StoreAvailability`를 여는 새 버전을 먼저 배포하고, 마지막 단계에서만 운영 `sales_enabled=true`와 live 시크릿을 설정한다.

Sparkle `2.9.6`이 production 앱에 내장되며 메뉴바 `업데이트 확인…`과 설정의 업데이트 카드에서 수동 확인할 수 있다. 설정 버튼은 production updater가 사용 가능한 동안에만 활성화한다. 자동 확인은 Sparkle의 사용자 동의 흐름을 사용하고, 익명 system profiling은 활성화하지 않는다. appcast와 ZIP은 서로 다른 검증 대상이므로 둘 다 `sidey-app` EdDSA 키로 서명하며 `SURequireSignedFeed`와 `SUVerifyUpdateBeforeExtraction`을 강제한다. 피드는 GitHub raw HTTPS URL, 설치 파일은 GitHub Releases를 사용한다.

Sparkle이 없는 기존 alpha 사용자는 최신 공증 DMG로 한 번 수동 교체해야 하며, 이후 앱 내부 업데이트를 사용한다. 사용자 세션과 설정은 앱 번들 외부에 있어 교체·업데이트 후에도 유지된다. Sparkle 개인키는 저장소나 CI 로그에 넣지 않고 release operator의 로그인 Keychain과 암호화한 오프라인 백업에만 둔다.

공개 배포본은 표시명 `SIDEY`, 채널 `production`, bundle ID `app.sidey.desktop`, OAuth callback `sidey`를 사용한다. 로컬 개발본은 `Sidey-dev`, 채널 `development`, bundle ID `app.sidey.desktop.dev`, callback `sidey-dev`를 사용하고 login item ID·Keychain service·UserDefaults suite·Supabase 세션을 모두 production과 분리한다. dev 앱은 `SIDEY-staging` URL과 publishable key가 없거나 운영 ref `whtejsviizgejauasqqt`를 가리키면 빌드하지 않으며 Sparkle controller도 생성하지 않는다.

schema 6 이하 기존 설치가 alpha.6에서 처음 Keychain 정보를 읽기 전에는 SIDEY 자체 안내창을 먼저 표시한다. 안내창은 로그인 상태와 그룹 초대 코드를 macOS 키체인에 안전하게 보관·조회한다는 목적, 이전 버전 정보를 처음 불러올 때 Mac 로그인 암호를 요청할 수 있다는 점, 다음부터 묻지 않게 하려면 macOS 창에서 `항상 허용`을 선택해야 한다는 점, `허용`은 같은 실행이나 다음 실행에서 창을 반복시킬 수 있다는 점, SIDEY가 암호를 확인하거나 저장하지 않는다는 점을 설명한다. 버튼은 `계속`과 `SIDEY 종료`다. 신규 설치는 안내를 생략하고 새 항목을 만든다.

Keychain 접근은 앱 실행 동안 하나의 `LAContext`를 공유하고 `localizedReason`은 앱 이름을 제외한 `로그인 상태와 그룹 초대 코드를 안전하게 불러옵니다.`로 고정한다. 같은 service/account 읽기는 성공과 없음 결과를 메모리에 캐시하고, 캐시된 데이터와 같은 저장은 Security API 호출을 생략한다. `errSecUserCanceled` 또는 `errSecAuthFailed`가 한 번 발생하거나 자체 안내창에서 종료를 선택하면 프로세스 전역 거부 상태를 기록하고 후속 Security API를 호출하지 않은 채 앱을 종료한다. 기존 설치는 세션 복구에 성공한 뒤에만 schema 7 전환 완료 상태를 저장한다.

신규 설치 기본 파일은 공증 DMG다. Homebrew third-party tap은 같은 DMG의 고정 URL·SHA-256, arm64·macOS 26+ 조건, `auto_updates true`, `SIDEY.app`과 안전한 종료 규칙을 사용하고 사용자 데이터 삭제용 `zap`은 선언하지 않는다. ZIP은 Sparkle 전용으로 유지한다.

자동화 테스트와 공개 배포는 장시간 수동 기준을 대신하지 않는다. 수행하지 않은 장시간 항목을 통과했다고 기록하지 않고 정식판에서도 지속 검증한다.

### 10.5 Windows v1.0.5 정식 배포 절차

1. Windows 전체 단위·계약·창 정책·업데이트·배포 source 테스트와 10.3의 실기·장시간 기준을 통과한다.
2. staging에서 익명 세션·RLS·private Realtime을 통과한 뒤 production publishable 구성에서도 다시 확인한다. service-role·secret key는 클라이언트·저장소·CI 산출물에 넣지 않는다.
3. CI에서 `win-x64` unpackaged·multi-file self-contained 앱을 `PublishSingleFile=false`로 게시한다. 루트 `SIDEY.exe` 런처가 인수를 `Runtime\SIDEY.Host.exe`로 전달하고, 앱·.NET·Windows App SDK 런타임은 `Runtime`, 사용자 콘텐츠는 `Assets`, SIDEY 번역은 `Langs`에 둔다. 게시한 런처와 호스트를 실제 시작해 main 또는 미지원 OS 창 활성화 로그가 남고 프로세스가 유지되는지 확인한다.
4. WiX Toolset `6.0.2`로 전체 payload와 내부 cabinet을 포함한 머신 단위 `SIDEY-Windows-x64-v1.0.5.msi`를 만든다. Burn Setup EXE·ZIP·MSIX는 만들거나 공개하지 않는다.
5. 자체 서명 인증서·임시 PFX·공개 CER를 만들지 않고 Release용 MSI와 내부 검증용 SHA-256만 생성한다. `.sha256` 파일은 Release 자산으로 게시하지 않는다.
6. clean install·공용 시작 메뉴·아이콘이 포함된 `Uninstall.exe`·repair·실행 중 upgrade·downgrade 차단을 확인한다. Windows 설정·MSI·`Uninstall.exe`의 일반 제거에서 데이터 삭제 옵션이 기본 미선택이고, 선택 시에만 현재 사용자의 설정·로그·로그인 정보를 삭제하며 upgrade·repair에는 삭제하지 않는지 검증한 뒤, 검증된 커밋에 `windows-v1.0.5` 태그와 GitHub 정식 Release를 만든다. Release에는 MSI 하나만 게시하고 제거 옵션의 영향을 명시한다.
7. Windows Actions가 성공하면 Pages Actions가 GitHub 정식 Release의 단일 MSI를 다시 내려받아 SHA-256을 계산한다. 태그·고정 MSI URL·자산 구성이 모두 맞을 때 배포 아티팩트의 `website/windows-latest.json`과 호환 경로 `website/windows/update.json`에 64자리 SHA-256을 기록하고 Windows 다운로드 버튼을 활성화한다. 앱은 시작 시 한 번 새 버전을 확인하고 트레이·설정에서 수동 확인하며, 사용자 승인 뒤 다운로드·hash 검증을 통과한 설치기만 실행한다.

공개 MSI는 관리자 승인 뒤 모든 사용자용으로 `C:\Program Files\SIDEY`에 설치하고 공용 시작 메뉴에 앱과 제거 바로가기를 만든다. 설치 폴더에는 앱 아이콘을 포함한 `Uninstall.exe`를 두고, MSI 제품 정보에는 같은 아이콘을 등록한다. 기존 per-user·Burn 테스트 설치는 등록 방식이 달라 자동 전환하지 않으며 먼저 Windows 설정에서 제거하도록 안내한다. `Uninstall.exe`를 직접 실행하면 Windows Installer 제거를 시작하고, Windows 설정과 MSI 유지 관리 화면을 포함한 일반 제거에는 `설정, 로그 및 로그인 정보도 삭제` 체크박스를 기본 미선택으로 표시한다. 선택하면 MSI가 `Uninstall.exe --cleanup`을 실행해 현재 사용자의 `%LOCALAPPDATA%\SIDEY`와 Credential Manager의 `SIDEY/` 자격 증명을 삭제한다. 선택하지 않으면 사용자 데이터를 보존하며 major upgrade와 repair에서는 이 정리를 실행하지 않는다.

v1.0.3·v1.0.4의 앱 내 업데이트는 SHA-256 검사에 사용한 파일 스트림이 열린 상태에서 설치 파일 이름을 바꾸려 해 Windows 파일 잠금 오류로 실패한다. 따라서 기존 사용자는 v1.0.5 MSI를 한 번 수동 설치해야 하며, 설정·로그인 정보는 major upgrade에서 보존한다. v1.0.5는 검사 스트림을 닫은 뒤 검증된 MSI를 게시하고 설치기를 실행한다.

SHA-256은 PowerShell에서 `Get-FileHash .\SIDEY-Windows-x64-v1.0.5.msi -Algorithm SHA256`으로 계산한다. GitHub에서 다시 내려받은 MSI와 CI 후보가 같은지 검증하고 이 값을 업데이트 manifest에 기록하되 별도 `.sha256` Release 자산은 만들지 않는다.
