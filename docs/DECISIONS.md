# SIDEY 결정 기록

- 최종 갱신: 2026-09-02
- 관련 문서: [제품 기획서](PRODUCT_SPEC.md)
- 통합 브랜치: `main`; 작업 브랜치: `macos/*`, `windows/*`, `shared/*`

이 문서는 SIDEY의 제품·기술 결정을 추적한다. 구현이나 다른 문서와 충돌하면 여기서 `확정`으로 기록한 결정을 우선한다.

## 확정된 결정

| 항목 | 결정 | 이유 |
| --- | --- | --- |
| 제품명 | `SIDEY` | 공식 제품명이다. `같이온`·`같이ON`은 제품 문구, 코드, 식별자에 사용하지 않는다. |
| 제품 형태 | 최대 12명의 실제 친구가 2D 픽셀 동물로 화면 가장자리에서 함께 움직이는 초대 전용 데스크톱 ambient messenger | 고정형 채팅 목록보다 친구의 존재와 짧은 대화가 자연스럽게 보이는 경험에 집중한다. AI 동료나 가상 반려동물 제품은 아니다. |
| 공개 업데이트 문서 | README는 제품 소개 뒤 macOS·Windows 설치, 플랫폼별 최신 업데이트, 공통 향후 계획만 제공한다. GitHub Release와 `docs/releases/*`는 사용자에게 보이는 변화와 필요한 설치·제한 안내만 짧게 적고 DB·백엔드·클래스·빌드 구현 세부는 싣지 않는다 | README와 Release는 일반 사용자가 보는 문서다. 내부 변경이 사용자 경험을 뒷받침하면 `내부 안정성 개선` 또는 `내부 운영 구조 개선`처럼 결과만 설명한다. |
| 공개 향후 계획 | 새로운 말풍선 디자인, Windows 기능 안정화, 캐릭터 드래그 앤 드롭, 캐릭터 효과음, macOS 이모지 입력 버그 개선, 다른 사람 캐릭터 클릭 이펙트를 향후 개선 후보로 공개한다 | 계획 항목은 구현 완료나 일정 약속이 아니며 현재 MVP 범위를 즉시 확장하지 않는다. 드래그 앤 드롭은 기본 클릭 통과 정책을 깨지 않는 별도 상호작용 설계가 확정된 뒤 구현한다. |
| 공식 다운로드 웹사이트 | GitHub 프로젝트 Pages `https://sidey-app.github.io/SIDEY/`를 한국어 기본·`/en/` 영어 정적 랜딩으로 운영하고 `website/`만 GitHub Actions로 배포. macOS는 현재 공증 DMG와 `sidey-app/tap/sidey` Homebrew Cask를 제공하고 Windows는 공개 파일이 생길 때까지 링크 없는 비활성 버튼으로 표시 | 앱 클라이언트나 별도 웹 기능을 추가하지 않고 공식 설치 경로·지원 환경·개인정보 경계·플랫폼 제한을 한곳에서 정확히 안내한다. 릴리스가 바뀌면 고정 DMG URL과 웹사이트 버전을 같은 배포 작업에서 갱신한다. |
| 현재 구현 범위 | macOS 네이티브 정식판에 첫 유료 캐릭터 상점을 추가하고 Windows 네이티브판을 별도 개발 | macOS Swift/SpriteKit 기준 구현 위에 승인된 상점 범위만 확장하며 Windows 작업은 `windows/*`에서 독립적으로 진행한다. |
| 플랫폼 순서 | macOS 정식판을 기준 구현으로 유지하고 Windows 11 25H2+ x64를 후속 개발 | 이미 배포된 macOS 코드를 재작성하지 않고 Windows 고유 창·DPI·전원·IME 리스크를 별도로 검증한다. |
| 플랫폼 브랜치 격리 | macOS 구현은 `macos/*`, Windows 구현은 `windows/*`, 문서·백엔드·웹·공통 계약은 `shared/*`에서 작업하고 `main`은 검증된 변경의 통합·배포에만 사용 | 한 플랫폼 작업이 다른 플랫폼 파일이나 다른 작업자의 dirty worktree를 건드리는 사고를 막는다. 공용 변경은 독립 커밋으로 만든 뒤 필요한 플랫폼 브랜치가 가져가며 반대 플랫폼 대응은 별도 후속 작업으로 남긴다. |
| macOS 클라이언트 | SwiftUI + AppKit + SpriteKit | 일반 창은 SwiftUI/AppKit, 창 정책은 AppKit, 픽셀 월드는 SpriteKit이 담당한다. |
| Windows 클라이언트 | Windows 11 25H2(build 26200)+ x64, C#/.NET 10 LTS + WinUI 3/Windows App SDK 2.4.0 + Win32 | 일반 창은 WinUI 3, 투명 월드는 전용 Win32 HWND가 담당한다. 첫 햄스터 local slice는 사전 생성한 BGRA frame과 `UpdateLayeredWindow`로 창·DPI·클릭 통과·GDI handle 안정성을 먼저 검증한다. 트레이·모니터·활동 감지는 Win32 플랫폼 서비스가 담당하며 WPF·Electron·WebView·Godot은 사용하지 않는다. |
| 클라이언트 공통화 | 플랫폼별 네이티브 코드베이스와 공통 서버 계약 | Godot 공통 런타임은 폐기하고 서버 schema·Realtime payload·제품 행동 규칙을 동등성 계약으로 삼는다. |
| 백엔드 | Supabase Auth, Postgres, Realtime Presence·Broadcast, Edge Functions commerce | 메시지·주문·소유권은 Postgres가 원본이며 Presence는 연결 상태, Broadcast는 typing·리액션 같은 일시 이벤트에만 사용한다. 결제 식별자와 결제사 비밀키는 클라이언트에 두지 않는다. |
| 그룹 인원 | 방당 최대 12명, 서버에서 강제 | 12번째 가입은 허용하고 13번째는 `member_limit_reached`로 거부한다. 클라이언트 검증만으로 대체하지 않는다. |
| 사용자당 그룹 | 최대 5개, 한 번에 활성 그룹 하나만 표시 | 그룹 수 제한은 기존 서버 계약을 유지하고 화면에는 선택한 월드 하나만 노출한다. |
| 그룹 공개 범위 | 초대 전용 비공개 그룹 | 공개 검색·추천·발견 기능은 범위 밖이다. |
| 그룹 관리 | macOS 그룹 설정의 각 카드는 기본 접힘이며 제목 영역 또는 오른쪽 여백을 둔 단일 화살표로 펼친다. 모든 멤버가 구성원을 볼 수 있고, 현재 `owner_id` 방장만 멤버 목록 아래의 1~20자 이름 변경·그룹 hard delete 버튼과 본인 외 멤버 추방을 사용한다. 비활성 방 전환 문구는 `그룹 참가`이고 방장은 설정 멤버 닉네임 왼쪽의 금색 왕관으로만 표시 | 카드 헤더의 왼쪽 기본 disclosure 표시와 별도 `…` 관리 메뉴를 두지 않는다. 관리 UI와 서버 RPC가 UUID 기반 방장 권한을 각각 검증한다. 그룹 삭제는 멤버십과 메시지를 cascade 삭제하며, 활성 그룹이 사라지면 가장 오래된 남은 그룹으로 전환하고 마지막 그룹이면 프로필을 유지한 참여 화면으로 돌아간다. |
| 그룹 작업·전환 | macOS는 `idle / creating / joining / switching(UUID)` 그룹 작업 상태를 연결 상태와 분리한다. 생성은 `만드는 중…`, 참여는 `참여 중…`, 전환 대상 카드는 스피너·`연결 중…`과 강조 배경·테두리를 표시한다. 전환 중 다른 그룹 선택은 허용하고 150ms 동안 마지막 선택만 남기되 네트워크 작업은 직렬 실행한다. 최종 대상의 전체 방 Presence 게시와 명시적 방 메시지 조회가 모두 성공한 뒤에만 활성 그룹·기록을 교체하며, stale 결과·오류는 적용하지 않는다. 최종 실패는 이전 활성 그룹 Presence를 복구하고 복구 실패만 실제 Realtime 연결 오류로 처리한다. | 빠른 연속 선택이 이미 완료된 이전 요청으로 되돌아가거나 서로 다른 Presence `track` 호출이 경합하는 문제를 막는다. 전환 중 생성·삭제·이름 변경·추방 mutation은 차단한다. |
| 표시 이름과 캐릭터 | 닉네임은 줄바꿈 없는 2~8자로 제한하고 캐릭터 선택과 함께 중복 허용, UUID로 식별. macOS에서 저장할 때는 한글 IME의 미확정 조합을 먼저 확정하고 다음 메인 런루프에서 저장한다 | 긴 이름으로 상태 점·가장자리 UI가 충돌하는 문제를 막되 표시 속성의 중복은 권한 판단에 영향을 주지 않게 한다. 기존 9~12자 닉네임은 서버 migration에서 앞 8자로 줄이고, 사용자가 방향키로 조합을 끝내지 않아도 마지막 글자를 잃지 않게 한다. |
| 활동·렌더 영역 | 이동 track·프리셋·말풍선 보정은 기존 최대 240pt `activityFrame`을 유지하고, SpriteKit과 투명 패널은 리액션 잘림 방지용 최대 360pt `renderFrame`을 사용. 렌더 영역은 접선 양쪽에 최대 144pt를 더하되 visible frame을 넘지 않음 | 7배 스프라이트가 기존 앱 창 경계에 잘리지 않게 하면서 이동 범위와 프리셋 체감은 바꾸지 않는다. 렌더 패널은 상시 고정하고 캐릭터 발은 실제 화면 경계에 유지한다. |
| 영역 프리셋 | 가장자리 `하단·좌측·우측·상단` × 길이 `1/3·1/2·전체`의 12개 조합, 짧은 띠는 중앙 정렬, 기본 `하단·전체` | 자유 이동·크기 조절 대신 예측 가능하고 복원 가능한 배치를 사용한다. |
| 방향 | 캐릭터의 발이 선택한 가장자리를 향하며 닉네임·상태 점·말풍선도 같은 각도로 회전 | 하단 0°, 좌우 ±90°, 상단 180°로 월드 자체의 방향을 일관되게 유지한다. |
| 모니터 | 월드와 입력창은 선택한 모니터 한 대에만 표시하며, 제거되면 주 화면으로 복귀하고 설정도 갱신 | 사라진 화면 좌표를 계속 복원하는 오류를 막는다. |
| 멤버 표시 | 내 캐릭터를 포함한 활성 그룹 전체를 기본 표시 | 오프라인 멤버는 수면·빨간 점으로 남기며 `오프라인 멤버 표시` 설정을 끄면 숨긴다. |
| 상태 표현 | 온라인=`산책/idle + 초록`, 자리 비움=`선 채 졸기 + 주황 점 + 고정 14pt 주황 Zzz·약 2pt 어두운 외곽선·0.55↔1 alpha·3pt 부유`, 오프라인=`웅크린 잠 + 빨강 + 저채도·75% alpha`, 재연결=`정지 + 회색` | 자리 비움과 오프라인을 포즈·채도·보조 효과까지 다르게 표시한다. `Zzz` 글자 수는 순환시키지 않고 라벨 전체의 부유·alpha만 반복한다. |
| 타이핑 표현 | 현재 행동을 유지하고 `.`→`..`→`...`을 0.35초마다 순환하는 말풍선 표시 | 점 애니메이션은 로컬 SpriteKit action이며 Broadcast 빈도·schema는 바꾸지 않는다. 실제 메시지가 우선하고 만료 뒤 타이핑 중이면 다시 나타난다. |
| 캐릭터 리액션 | 내 캐릭터를 더블클릭하면 스프라이트가 발 위치를 기준으로 0.20초 동안 7배까지 커지고 0.60초 동안 복귀하며, 같은 방에 `character_pulse` Broadcast로 공유. 캐릭터별 1초 쿨타임 | 저장할 필요 없는 가벼운 상호작용이므로 Postgres나 Presence가 아니라 transient Broadcast가 맡는다. 이벤트 UUID로 중복 재생을 막고 수신 측도 1초 제한을 적용한다. 닉네임·상태 점·말풍선은 확대하지 않는다. |
| 이동 | 선택한 가장자리와 평행한 1차원 track에서 로컬 랜덤 산책, 간헐적 idle, 부드러운 상호 회피. 캐릭터가 겹치면 목표 방향으로 빠르게 통과하고, 실제 메시지 말풍선 본문이 겹치면 idle을 즉시 끝내고 반대 방향으로 분리 이동 | 일반 이동은 최대 22pt/s다. 메시지 말풍선 분리는 240pt/s² 가속·최대 72pt/s로 본문 사이 8pt 여유까지 유지하고, 해소 뒤 기존 목표와 일반 속도 제한으로 복귀한다. 타이핑 말풍선은 제외하며, 막힌 쪽 힘은 가능한 상대에게 배분하고 다중 충돌은 진입 순서를 유지한 채 쌍별 힘을 합산한다. 발 기준선·track 범위·finite 좌표를 지키고 순간이동이나 위치 전송은 하지 않으며 혼잡 시 겹침을 허용한다. |
| 닉네임 대비 | 흰색 닉네임 뒤에 여백이 있는 반투명 검정 캡슐을 표시 | 뒤 앱의 화면 픽셀을 수집하지 않고도 밝고 어두운 배경 모두에서 가독성을 유지한다. |
| 안정적 배치 | 설치별 로컬 seed와 room/user UUID를 조합해 초기 위치를 결정하고 UUID diff로 노드를 갱신 | 앱 재실행 시 배치를 안정화하고 Presence·스냅샷 갱신 때 기존 위치가 초기화되지 않게 한다. |
| 말풍선 | 발신자별 최신 1개, 전체 최대 4개, 기본 10초, 실측 최대 폭 220pt, 삼각형 꼬리 | 최대 200자·3줄 입력을 생략하지 않고 렌더하며 끝에서는 말풍선만 접선 보정한다. 실제 메시지 본문 충돌은 캐릭터 이동으로 완화하되 줄 올림·축약·조기 제거를 최후 처리로 사용하지 않으며, 이동 중 본문과 꼬리는 발신자를 매 frame 추적한다. |
| 메시지 전송 | 방별 `OutgoingMessage(id, roomID, body, state)` outbox에서 UUID 기반 낙관적 표시 후 Postgres 저장과 조정. 실패 항목은 원래 방에만 남기고 현재 방 draft를 덮지 않으며, 응답이 애매하면 같은 UUID를 조회·재시도 | 방 전환과 늦은 실패가 다른 방의 비공개 본문을 draft로 옮기는 일을 막고, commit 뒤 응답 유실에도 중복 메시지를 만들지 않는다. confirmed ledger는 방별 최근 50개·7일만 유지한다. |
| 메시지 서버 시각 | Postgres `created_at`은 소수 초 유무와 `Z`·UTC offset이 있는 ISO-8601을 엄격히 해석하고 사용자 로컬 시간으로 표시한다. 해석할 수 없는 값은 현재 시각으로 대체하지 않고 기술 오류로 처리한다. | 잘못된 서버 시각을 정상 메시지처럼 숨기면 기록 정렬과 장애 원인 추적이 깨진다. |
| 메시지 보관 | Postgres 메시지는 생성 후 7일이 지나면 서버의 일일 정리 작업으로 영구 삭제한다. 정원·보관 변경 migration을 적용할 때 이미 7일을 넘긴 메시지도 즉시 정리한다. | 사적인 짧은 대화의 불필요한 장기 보관을 줄이고 서버 기록 정책을 제품 UI에 명확히 알린다. |
| 조용히 모드 | 메시지 본문 말풍선은 숨기고 미확인 수는 유지하며, 타이핑 순환 점은 표시 | 화면 공유 중 본문 노출을 막되 상대가 입력 중이라는 신호는 유지한다. |
| 입력창 | 기본 숨김인 400×56 입력창을 선택 모니터의 상단 중앙, 노치·메뉴바 아래 10pt에 고정하고 `메시지를 입력해 주세요` 안내를 표시한다. 최대 200자·명시적 줄바꿈 3줄과 입력 폭 자동 줄바꿈을 유지하며 `NativeMessageField` 내부 문서 높이를 실제 내용만큼 확장하고 선택·삽입 커서를 자동 세로 스크롤해 계속 표시한다. 내 캐릭터 단일 클릭 또는 메뉴바 `메시지 작성`으로 열며, 왼쪽 `×`·Esc·캐릭터 재클릭·입력창 외부 클릭으로 닫고 유효한 전송 뒤 마지막 전송 시점부터 5초간 유지한 뒤 자동으로 닫기 | 스크롤 위치는 전역 draft 상태가 아니라 AppKit 입력 뷰가 소유한다. 일반 입력·삭제, IME 확정, Shift+Enter, 키보드·마우스 선택, 외부 draft 복원과 유효성 실패 복구 뒤에도 현재 커서를 보이게 한다. 한 시각 줄은 세로 중앙, 여러 시각 줄은 상단 inset을 사용하고 가로 무한 확장은 금지한다. 외부 클릭은 전역 마우스 감시가 아니라 입력 패널의 키 포커스 상실로 판정하며 모든 닫기 경로는 draft를 보존하고 `typing_stop`을 보낸다. |
| 제거하는 오버레이 조작 | 오버레이 영역의 자유 이동·크기 조절·잠금, 캐릭터 직접 드래그, 오버레이 내부의 기록·설정 버튼 제거 | 월드는 항상 클릭 통과하고 내 캐릭터의 52×52 메시지·리액션 hotspot만 포인터를 받는다. 프리셋 기반 영역과 자동 산책을 방해하는 직접 위치 조작 계약은 남기지 않는다. |
| 최근 기록 | 메뉴바에서 여는 일반 macOS 창에서 최신순 메시지 카드를 표시한다. 각 카드는 40pt 슬롯의 24×24 무배율 픽셀 캐릭터, 닉네임·`나` 표식, 로컬 시각, 본문과 전송 상태를 보여주며 현재 방 멤버 snapshot에 발신자가 없으면 햄스터와 `알 수 없는 친구`를 사용한다. 최초 50개 뒤 목록 하단에서 `(created_at, id)` keyset cursor로 50개씩 자동 조회하고 Postgres의 최근 7일 범위까지만 탐색한다. 페이지는 기록 전용 상태가 소유하고 bounded Realtime ledger와 pending·failed outbox를 UUID로 병합하며, 방 전환 즉시 초기화하고 창을 닫으면 요청 취소와 적재 페이지 해제를 수행한다. | 클릭 통과 오버레이와 키보드·스크롤 입력을 분리하면서 발신자 맥락과 긴 기록 탐색을 제공한다. 기존 방별 50개 ledger 제한은 Realtime·말풍선 안정성을 위해 유지하고 기록 조회가 그 전역 상태를 무제한으로 키우지 않게 한다. 정확한 서버 timestamp 문자열과 UUID를 cursor로 사용해 같은 시각 메시지의 중복·누락을 막는다. |
| 메뉴바 | 픽셀 햄스터 얼굴 template icon과 unread variant를 사용하고, 메뉴는 오버레이 표시, 메시지 작성, 활성 그룹·미확인 수, 조용히 모드, 최근 기록, 그룹 설정, 로그인 실행, 업데이트 확인, 설정, 종료만 제공 | 밝고 어두운 메뉴바에 자동 대응하며 이미지 로딩 실패 시에만 `pawprint.fill`을 사용한다. |
| macOS 설정 화면 | 설정창은 `fullSizeContentView`를 유지하되 투명 커스텀 타이틀바 대신 AppKit 네이티브 타이틀바 머티리얼과 자동 구분선을 사용해 스크롤 콘텐츠가 겹칠 때 블러 처리한다. 온보딩 캐릭터 선택은 4열이며 다섯 번째 항목부터 다음 줄에 둔다. 각 설정 섹션은 아이콘·제목·설명을 카드 위에 두고 `Color.primary.opacity(0.025)` 기반의 옅은 적응형 카드 안에서 제목 아래 설명과 오른쪽 컨트롤을 대응시킨다. 컨트롤 영역은 240pt와 오른쪽 끝을 공유하고 `동작 정보`는 제거한다. 상세 영역은 가로 44pt·세로 40pt 바깥 여백과 카드 안 24pt 여백을 유지하며 그룹 아이콘은 `person.2`, 그룹 목록·새 그룹 만들기·초대 코드 참여는 각각 독립 카드로 구분한다 | 상단 콘텐츠의 겹침을 macOS 표준 재질로 구분하고 온보딩의 가용 폭을 낭비하지 않으면서, 설정 효과를 조작 전에 이해할 수 있게 한다. 개발 세부 정보를 사용자 설정처럼 노출하지 않으며 상태와 action 소유권은 기존 `AppModel`·`SettingsActions`에 유지한다. |
| macOS 상점 카드 | `꾸미기·상점`은 2열 상품 그리드를 사용하고 공통 구매 안내를 그리드 아래 가로 중앙에 둔다. 상품이 짧으면 가변 여백이 안내를 상세 영역 하단으로 밀고, 창이 작으면 카드와 겹치지 않은 채 스크롤 끝에 둔다. 안내는 부가세 포함·Google 연결·서버 승인과 소유권 확인·승인 즉시 사용권 제공·제공 시작 뒤 단순 변심 철회 제한·법정 사유 전액 환불을 한 번만 알린다 | 상품 상태·결제 action은 기존 `AppModel`·`SettingsActions`에 유지하고 반복되는 `StoreProductCard`는 카드별 미리보기 animation과 취소 가능한 Task만 소유한다. 푸터 배치는 설정 상세 영역 높이만 사용하고 별도 전역 상태를 만들지 않는다. |
| macOS 결제 | Google identity가 연결된 기존 SIDEY 계정만 시스템 브라우저의 토스페이먼츠 결제를 시작한다. 체크아웃은 기본 미선택 동의 뒤 정책 `2026-09-02-v1`의 결제 당시 고지 원문·버전·동의 시각을 서버에 기록하고, 기록 성공 뒤에만 결제창 설정을 반환한다. 주문 token은 일회용이며 서버 가격과 토스 승인·재조회 결과를 원본으로 사용한다 | 클라이언트 금액·success URL·체크박스 비활성화 UI만 소유권 증거로 신뢰하지 않는다. checkout은 명시적 동의 값과 현재 정책 버전을 서버에 기록하고, 반환 URL·승인 RPC·웹훅은 동의 없는 주문의 활성 소유권 생성을 DB에서 차단한다. Toss test/live 키와 client/secret 세트 혼용은 모든 결제사 API 호출 전에 거부한다. |
| 청약철회·환불 | 서버 승인과 소유권 확인 즉시 디지털 사용권 제공을 시작하며, 구매자가 결제 전에 즉시 제공과 제공 시작 뒤 단순 변심 청약철회 제한에 명시적으로 동의한다. 미제공·계약 불일치·중복 결제·무단 결제·법정대리인 미동의 등 허용된 법정 사유는 전액 환불한다 | 운영 환불 endpoint는 별도 ops 인증, 운영자 식별자와 허용 사유 코드를 요구한다. 사유·요청·결제사 처리·최종 결과는 private commerce 감사 기록에 남기며, 전액 취소 검증 뒤 소유권을 회수하고 사용 중인 프로필을 햄스터로 되돌린다. |
| 유료 캐릭터 소유권 | 첫 상품은 `pixel_starlight_upalupa` 별빛 우파루파다. macOS 선택 목록은 무료 5종과 현재 계정의 활성 소유권만 보여주며 환불되면 햄스터로 복귀한다. 이번 Windows 릴리스는 구매와 별빛 우파루파 원격 렌더링을 지원하지 않는다 | 미구매 상품을 선택 화면에 광고처럼 노출하지 않고 서버 소유권을 선택 가능 여부의 원본으로 사용한다. Windows 코드·에셋·테스트는 macOS 실판매 준비와 분리한다. |
| 공개 판매자 정보 | 고정 URL `store.html`, `terms.html`, `privacy.html`, `refund.html`에 상호 `싸이디(SIDEY)`, 대표자 `류태현`, 사업자등록번호 `388-53-01259`, 주소 `경기도 용인시 기흥구 서천동로21번길 20-6`, 고객지원 `ryu200112@gmail.com`·`010-9270-2973`, 통신판매업 `신고 면제(간이과세자)`를 게시한다 | 사업자등록증의 생년월일·QR·동호수는 저장소와 웹사이트에 넣지 않는다. 통신판매업 신고 면제 표시는 현재 간이과세자 지위를 전제로 하며 과세유형 변경 시 재검토한다. |
| 초대 코드 복사 피드백 | macOS 설정에서 복사가 성공하면 해당 그룹 행만 초록 체크와 `복사 완료`를 3초간 표시한다. 재클릭은 타이머를 갱신하고 행 제거 시 취소하며, 성공 전역 배너는 사용하지 않고 실패만 오류 배너로 알린다 | 행에 종속된 일시 상태는 `RoomRow`가 소유하고 실제 Keychain 읽기·클립보드 처리는 `AppCoordinator`가 소유해 서버 상태와 UI 피드백을 섞지 않는다. |
| 렌더링 소유권 | `PixelWorld`가 캐릭터 노드, 이동, 닉네임, 상태 점, 말풍선을 단독 소유 | `AppModel`은 방·Presence·메시지·설정 상태만 소유해 서버 상태와 화면 렌더링을 분리한다. |
| 환경설정 계약 | `OverlayEdge`, `OverlaySpan`, `OverlayRegionPreference(edge, span, screenIdentifier)`를 Codable로 저장 | 스키마를 올리고 과거 frame·lock·scale 값은 읽기 호환만 제공한 뒤 `하단·전체` 영역으로 이전한다. |
| 내장 캐릭터 | `pixel_hamster`, `pixel_cat`, `pixel_puppy`, `pixel_rabbit`, `pixel_penguin`; 각 24×24×10프레임, 2배 정수 확대 약 48pt, nearest-neighbor | idle 2, walk 4, doze 2, offline 2 프레임과 공통 발 기준선을 결정적 Swift 생성기로 보장한다. 캐릭터 선택과 닉네임은 그룹에서 중복 가능하다. |
| 과거 캐릭터 호환 | 클라이언트에서 `minty_pup`을 `pixel_hamster`로 표시하는 alias 제공 | DB 프로필을 즉시 일괄 수정하지 않아도 새 런타임이 안전하게 표시할 수 있다. |
| 메시지·Realtime 스키마 | Postgres 메시지가 원본이다. 방마다 `realtime_epoch`을 두고 `room:<id>:<epoch>:db`와 `room:<id>:<epoch>:ephemeral` private topic을 분리한다. DB topic은 서버만 발행하고 message UUID·operation만 전달하며 클라이언트는 RLS 재조회 후 확정한다. typing·`character_pulse`도 직접 Broadcast하지 않고 인증 RPC가 방·epoch·사용자·event·rate를 검증한 뒤 서버 발행한다 | Realtime 연결 시 평가된 권한은 연결 동안 캐시되므로 client Broadcast payload를 신뢰할 수 없다. 멤버 변경 때 epoch을 올려 추방된 기존 WebSocket을 새 채널에서 격리하고, 픽셀 위치나 애니메이션 frame은 계속 전송하지 않는다. |
| Realtime 자동 복구 | macOS 클라이언트가 5초마다 실제 WebSocket·두 채널의 구독 상태를 검사한다. 비정상이 8초 이상 지속되면 generation을 올려 재생성하고, 실패 시 8→16→30초 backoff로 snapshot·활성 방 최근 메시지를 함께 재조정한 뒤에만 online으로 확정한다. 이벤트 stream은 최근 256개로 제한하고 overflow는 snapshot 재동기화로 복구한다 | 구독 객체만 살아 있는 stale 상태, reconnect 전의 과거 Presence, 누락 메시지·가입·추방·삭제를 앱 재실행 없이 교정한다. 무제한 task와 stream 축적도 막는다. |
| 초대 코드 보안 | 128-bit 난수를 32자리 hex로 만들고 API 비노출 `private.room_invites`에 Vault pepper 기반 HMAC-SHA256만 저장한다. 기존 짧은 코드는 migration에서 모두 비활성화하고 방장에게 1회 재발급을 요구한다 | public `rooms` 조회·Realtime row에 hash를 노출하면 짧은 코드가 오프라인 대입으로 복구될 수 있다. pepper와 hash는 Data API role에 공개하지 않는다. |
| 데이터 보안 | Supabase RLS 적용, 방 멤버십·12명·사용자당 5개 방 제한과 메시지·transient event rate limit을 서버에서 강제한다. 오래된 익명 계정 정리는 7일 초과·프로필 없음·방 없음인 미완성 가입만 삭제한다 | 클라이언트 우회, 메시지 폭주, 정상 사용자의 계정·세션 유실을 막는다. 초대 시도 제한은 사용자 advisory lock으로 직렬화하고 오래된 attempt 정리는 별도 cron에서 수행한다. |
| 개인정보 | 전역 활동은 마지막 시스템 입력 후 경과 시간과 화면 잠금만 사용. 화면 내용, 활성 앱 목록, 다른 앱의 키, 마우스 좌표, 파일, 마이크, 카메라는 수집하지 않음 | 오버레이 편의를 이유로 불필요한 민감 정보를 수집하지 않는다. |
| 보안 표현 | 설계·구현·검증 전에는 E2EE라고 주장하지 않음 | 전송 암호화와 RLS는 종단간 암호화가 아니다. |
| 창 보장 범위 | 보안 화면, DRM 앱, 권한이 높은 앱, 모든 독점 전체화면 게임 위 표시를 보장하지 않음 | OS 보안 정책을 제품 약속으로 우회할 수 없다. |
| 코드베이스 기준 | `main`에 macOS SwiftUI·AppKit·SpriteKit와 Windows C#·WinUI 3·Win32 네이티브 앱을 함께 유지하되 Godot·3D 런타임은 재도입하지 않음 | 플랫폼 구현은 분리하고 Postgres·Realtime 계약과 자동화 테스트로 동등성을 관리한다. 기존 macOS 세션·설정 migration 계층은 유지한다. |
| 서버 계약 | 운영에 적용한 기존 migration은 수정하지 않는다. `20260901000000_security_hardening.sql` 뒤 `20260902000000_commerce_policy_consent_and_refunds.sql`을 forward-only로 적용해 판매 잠금, 정책 동의 원문·시각, 동의 없는 소유권 차단, 사유 기반 private 환불 감사를 강제한다 | forward-only migration으로 로컬 초기화와 운영 DB가 같은 최종 schema에 도달하게 한다. 새 commerce migration과 Edge Functions는 판매 스위치를 끈 상태로 먼저 배포하고 라이브 키·실결제·법률 검토·공증을 모두 통과하기 전에는 판매를 열지 않는다. |
| macOS 업데이트 | Sparkle `2.9.6`을 production 채널 앱에만 시작하고 GitHub의 HTTPS appcast와 Release ZIP을 사용. ZIP과 appcast는 `sidey-app` 전용 EdDSA 키로 서명하고 다운로드 압축 해제 전 검증과 signed feed 검증을 강제. production 메뉴와 설정의 업데이트 카드에서 수동 확인을 제공하고 자동 확인은 Sparkle의 사용자 동의 흐름을 따름 | 실행 코드를 바꾸는 공급망이므로 공개키만 앱과 저장소에 두고 개인키는 release operator의 Keychain·암호화 오프라인 백업에만 둔다. Developer ID 서명, Hardened Runtime, 공증·staple과 `SIDEY`·`production` 메타데이터를 통과하지 않은 ZIP은 appcast에 게시하지 않는다. |
| macOS 직접 배포 | Developer ID Application으로 서명하고 Hardened Runtime·Apple 공증·ticket staple을 통과한 DMG를 신규 설치 기본 파일로 사용. 660×420 Finder 창은 toolbar·sidebar·status bar를 숨기고 왼쪽 `SIDEY.app`, 오른쪽 `/Applications` 바로가기, `SIDEY 설치` 제목·드래그 안내·좌→우 픽셀 화살표와 하단의 기존 5종 idle 프레임을 배치한다. 쓰기 가능한 DMG에서 배경·아이콘 위치·`.DS_Store`를 만든 뒤 UDZO로 변환하고 자동 마운트 검증한다. Sparkle에는 같은 공증 앱의 서명된 ZIP을 제공한다. | 브라우저 설치에서 Gatekeeper 우회를 요구하지 않고, 최초 설치용 컨테이너와 자동 업데이트용 아카이브의 역할을 분리한다. 배경은 기존 24×24 에셋을 정수 nearest-neighbor로 재사용하며 ad-hoc 빌드에는 배포용 DMG를 생성하지 않는다. |
| macOS Keychain 전환 | schema 6 이하 기존 설치는 alpha.6 최초 실행에서 macOS 인증창보다 먼저 SIDEY 안내창을 표시하고, 성공적으로 세션을 복구한 뒤 schema 7의 전환 완료 상태를 저장한다. 신규 설치는 안내를 생략한다. 실행 중 하나의 `LAContext`와 동일 키 읽기 캐시를 공유하고 동일 데이터 재저장은 생략한다. 시스템 이유는 `로그인 상태와 그룹 초대 코드를 안전하게 불러옵니다.`이며 안내창 또는 시스템 인증에서 거부하면 후속 Security API 호출을 차단하고 앱을 종료한다 | macOS 시스템 창 본문은 앱이 완전히 제어할 수 없으므로 사용 목적과 `항상 허용`·`허용`의 차이를 자체 안내로 확실히 설명한다. 인증 재사용과 캐시로 반복 요청을 줄이고, 한 번 거부한 뒤 인증창이 다시 뜨는 루프를 막는다. SIDEY는 Mac 로그인 암호를 확인하거나 저장하지 않는다. |
| Homebrew 배포 | 공개 third-party tap `sidey-app/homebrew-tap`의 `sidey` Cask가 버전 고정 공증 DMG와 SHA-256을 사용. arm64·macOS 26+만 허용하고 `auto_updates true`, 안전한 앱 종료, `SIDEY.app` 설치를 선언하며 사용자 데이터 `zap`은 두지 않음 | `brew install --cask sidey-app/tap/sidey`를 재현 가능하게 제공하면서 uninstall이 계정·설정을 임의 삭제하지 않게 한다. 공식 `homebrew/cask` 등록은 별도 결정 전까지 범위 밖이다. |
| macOS 로컬 개발 설치 | 최신 Release 구성의 ad-hoc 앱을 `Sidey-dev`·`development`로 빌드해 `/Applications/Sidey-dev.app`에만 설치. bundle ID `app.sidey.desktop`, login item ID, `com.sidey.desktop` Keychain service는 배포본과 공유하고 development 채널은 Sparkle을 시작하지 않으며 업데이트 메뉴를 비활성화 | 운영 데이터와 설정을 이어 쓰되 로컬 빌드가 공개 업데이트를 받거나 배포본으로 오인되는 것을 막는다. 설치 스크립트는 정확한 dev 경로만 교체한다. |
| 업데이트 전환 | Sparkle이 없는 기존 alpha는 최신 공증 DMG로 한 번 수동 교체하고, Sparkle 내장 production 빌드부터 앱 내부 업데이트를 사용 | 기존 설치에 프레임워크를 원격으로 소급 탑재할 수 없고, ad-hoc development 자동 업데이트는 Gatekeeper·코드 서명 연속성을 깨뜨릴 수 있다. |
| 배포 채널 | 현재 공개본은 버전 `1.0.3`, 빌드 `14`의 `v1.0.3` GitHub 정식 stable release다 | macOS 최근 기록에 캐릭터·닉네임 발신자 카드와 50개 단위 자동 페이지네이션을 추가한다. 최대 7일의 기존 서버 보존 정책과 RLS 계약은 유지하며 Windows·Supabase schema는 바꾸지 않는다. 12명 실제 방의 30분 장시간 계측은 지속 검증한다. |
| Windows 인증 | Google OAuth + PKCE, `sidey://auth/callback`, Credential Locker | Windows에서는 시스템 브라우저로 로그인하고 callback·refresh token·평문 초대 코드를 로컬 일반 설정이 아닌 보안 저장소에 보관한다. Google 이름·사진은 SIDEY 닉네임으로 복사하지 않는다. |
| Windows alpha 배포 | 다음 후보는 `v0.3.0-alpha.2`, WiX Toolset `6.0.2`의 머신 단위 MSI를 내장한 오프라인 `SIDEY-Windows-x64-v0.3.0-alpha.2-Setup.exe` + SHA-256, GitHub pre-release | 관리자 승인 뒤 `C:\Program Files\SIDEY`에 설치한다. unpackaged·self-contained WinUI 3 단일 파일 게시로 런타임과 앱 코드를 `SIDEY.exe`에 묶고, 캐릭터 PNG·BGRA·manifest 15개만 `Assets\Characters`에 외부 유지한다. ZIP·직접 MSI·MSIX는 공개하지 않으며 미서명 alpha의 SmartScreen·Smart App Control 제한은 그대로 밝힌다. |
| Windows 설치·업데이트 | alpha.2부터 머신 단위 major upgrade·repair와 downgrade 차단을 지원. per-user alpha.1은 Windows Installer가 설치 context를 가로질러 major upgrade할 수 없으므로 새 설치기가 감지·중단하고 사용자가 먼저 제거함 | 제거와 재설치 중에도 `%LOCALAPPDATA%\SIDEY` 설정과 Credential Manager 세션은 보존한다. 시작 메뉴와 Burn 성공 화면은 `C:\Program Files\SIDEY\SIDEY.exe`를 실행하고, 실행 중 upgrade는 Restart Manager로 정상 종료만 요청한다. |
| Windows 시작 안정성 | 앱 시작 단계를 `%LOCALAPPDATA%\SIDEY\Logs\startup.log`에 본문·token·초대 코드 없이 기록하고, WinUI 초기화 예외는 사용자에게 로그 경로를 표시. 트레이 초기화 실패만으로 프로세스를 종료하지 않고 이때는 창 닫기가 앱 종료로 동작하며 CI가 게시된 `SIDEY.exe`를 실제 시작해 창 활성화 단계까지 확인 | 기존 CI는 파일 존재만 검사해 시작 직후 예외와 누락된 런타임을 잡지 못했다. 사용자에게 아무 반응도 없는 종료를 없애고 설치 후보 자체를 실행 검증한다. |

## 현재 검증 기준

- 4개 가장자리 × 3개 길이의 activity/render 영역, 중앙 정렬, 회전, visible frame, hotspot 원점 변환, 모니터 제거 fallback이 단위 테스트를 통과해야 한다.
- 제품 방은 12명으로 제한하되 20개 합성 노드가 3,000 tick 동안 track 밖이나 NaN 상태로 빠지지 않는 스트레스 테스트를 통과해야 한다.
- 상태 전환, 주황 `Zzz`, 오프라인 숨김, 방 전환 UUID diff, 최대 8자 닉네임·반투명 배경과 상태 점 간격, 캐릭터 겹침 시 idle 해제·가속 통과, 실제 메시지 말풍선의 8pt 분리·72pt/s 제한·경계 힘 재배분·혼잡 안정성, 타이핑 말풍선 제외, 7배·0.8초 더블클릭 리액션의 1초 제한·Broadcast 중복 제거, 말풍선 교체·eviction·만료·이동 중 추적을 검증한다.
- 실서버 2클라이언트 테스트에서 한쪽 WebSocket을 강제로 끊은 뒤 재실행 없이 자동 재구독하고 메시지·Presence·`character_pulse` 수신을 복구해야 한다.
- 월드는 항상 위이며 전체 영역의 클릭 통과를 유지한다. 내 캐릭터 hotspot과 입력창만 포인터를 받고 입력창만 키보드 포커스 가능하며, 마지막 전송 뒤 5초 유지·타이머 갱신·실패 복구를 지키고 최근 기록은 일반 창이어야 한다.
- Sparkle 프레임워크와 `SUFeedURL`·`SUPublicEDKey`가 Release 번들에 포함되고 signed feed·압축 해제 전 검증이 강제되어야 한다. appcast 게시 도구는 ad-hoc·development 빌드를 기본 거부하고 Developer ID·Hardened Runtime·stapled notarization·production 표시명과 채널을 검증해야 한다. development 채널은 Sparkle을 만들지 않고 업데이트 메뉴를 비활성화해야 한다.
- 12번째 가입 성공, 13번째 거부, 여섯 번째 방 거부, 7일 초과 메시지 삭제, 방장 전용 이름 변경·추방·삭제와 cascade, RLS, 중복 닉네임·캐릭터 허용을 SQL 테스트한다.
- 최대 방 인원 12명으로 30분 실행하고, 별도 20노드 합성 부하에서도 p95 frame time 40ms 이하, 100ms 이상 main-thread hang 없음, 지속 RSS 증가 없음, 숨긴 월드의 SpriteKit 정지를 확인한다.
- Windows는 햄스터 1종의 투명·최상위·클릭 통과·52×52 hotspot·DPI·잠금·절전 복귀를 실기에서 먼저 통과한 후 Google 로그인·방·Presence·타이핑·메시지를 연결한다.
- Windows 공개 alpha는 12명 2시간과 20노드 30분 부하에서 p95 frame time 40ms 이하, 100ms 이상 UI-thread hang 없음, warm-up 후 working set 20MB 초과 증가 없음, handle·surface 지속 증가 없음을 확인한다.

## 아직 결정하지 않은 항목

| ID | 항목 | 현재 권장안 | 결정 시점 |
| --- | --- | --- | --- |
| D-006 | 자리 비움 전환 시간 | 5분 유지 | 실제 장시간 테스트 후 |
| D-007 | 메시지 말풍선 시간 | 10초 유지 | 12명 비공개 UX 테스트 후 |
| D-012 | E2EE 도입 여부와 프로토콜 | MVP 이후 별도 설계 | 보안 로드맵 수립 시 |
| D-013 | Windows 5캐릭터 최종 렌더러 | 1캐릭터 `UpdateLayeredWindow` slice의 frame time·working set·GDI handle 실측 뒤 유지 여부와 System Composition 전환을 결정 | 10.3의 첫 local slice 실기 검증 뒤 |
