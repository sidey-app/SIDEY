# SIDEY 아키텍처

이 문서는 SIDEY 저장소와 실행 시스템의 현재 책임 경계를 설명한다. 제품 동작은
[`product/`](product/overview.md), 선택 이유는 [`decisions/`](decisions/README.md),
반복 가능한 릴리스 절차는 [`operations/`](operations/release.md)에서 다룬다.

## 시스템 구성

- macOS 클라이언트는 SwiftUI·AppKit·SpriteKit으로 만든 네이티브 앱이다. Developer
  ID 직접 배포판과 Mac App Store판은 핵심 제품 코드를 공유하지만 인증, Keychain,
  결제, 업데이트, signing 및 entitlement 경계를 분리한다.
- Windows 클라이언트는 C#/.NET·WinUI 3·Win32로 만든 네이티브 앱이다. 일반 UI와
  투명 overlay surface를 분리하고, Core·Presentation·Infrastructure·Overlay·Platform
  계층의 의존 방향은 [Windows 아키텍처 문서](../windows/docs/architecture.md)가 설명한다.
- 공개 웹사이트는 제품·다운로드·정책·상점 정보를 제공하는 Astro 정적 사이트다.
  메시징 웹 클라이언트가 아니다.
- 이 공개 저장소는 네이티브 클라이언트, 공개 웹, client-facing contract, 승인된
  asset 원본과 commerce catalog를 소유한다.
- 독립 Spring Boot backend의 REST·raw WebSocket·인증 계약과 PostgreSQL schema,
  결제·App Store 검증, 운영 도구는 sibling `sidey-server`가 소유한다.
  서버의 `CONTRACT.md`와 실제 controller·service가 클라이언트 계약의 기준이다.
  공개/비공개 저장소의 작업 경계와 catalog handoff는 [`BACKEND.md`](BACKEND.md)를 따른다.
- 독립 로컬 운영 도구는 `sidey-admin` 저장소가 소유하고, 그 도구가 사용하는 서버
  조회·집계 계약은 backend 저장소가 소유한다.

## 소스 코드와 콘텐츠 권리

이 저장소의 SIDEY 소스 코드는 [GNU AGPLv3](../LICENSE)의 version 3 only 조건을
따른다. 적용 범위, 제3자 구성요소, 브랜드와 비공개 저장소의 경계는
[라이선스 안내](../LICENSING.md)가 설명한다. 유료 에셋의 기존 이용 조건은 코드
라이선스와 별개이며, 외부 에셋 기여는 받지 않는다. 기존 승인 에셋의 유지보수와
플랫폼 mirror 갱신은 계속 저장소의 검증·배포 절차를 따른다.

## 데이터와 실시간 경계

PostgreSQL이 영구 메시지와 계정·방 상태의 원본이다. 일반 요청과 메시지 복구는
REST를, 메시지 전송과 presence·typing·캐릭터 상호작용은 raw WebSocket을 사용한다.
메시지는 DB commit 뒤 ACK와 live event로 전달하며 UUID로 중복을 제거한다.
재연결에서는 live 구독을 먼저 등록하고 서버 checkpoint까지 REST cursor를 끝까지
조회한 뒤 준비 상태로 전환한다. 상세 복구 규칙은 [messaging.md](product/messaging.md)를 따른다.

서버가 SIDEY access/refresh session을 발급한다. Google·Apple은 identity proof이며
email로 계정을 합치지 않는다. 클라이언트는 서버가 확인한 membership, rate limit,
entitlement 및 equipped state를 표현하며 이를 로컬 상태만으로 부여하지 않는다.
Presence·typing·일시 상호작용은 서버 JVM memory에서 관리한다. 기존 Supabase credential은
기존 계정 claim에만 사용하고 일반 통신에는 사용하지 않는다.

클라이언트와 공개 웹에 필요한 계약만 이 저장소에 둔다. 비공개 schema, secret,
운영 데이터 또는 backend 배포 절차를 공개 문서에 복제하지 않는다.

## 콘텐츠와 commerce 흐름

승인된 asset 구조와 플랫폼 지원 범위는
[`assets/v1/manifest.json`](../assets/v1/manifest.json), 판매 상품 metadata와 플랫폼
식별자는 [`assets/v1/commerce-catalog.json`](../assets/v1/commerce-catalog.json)이
소유한다. 생성 스크립트가 이 원본에서 웹과 네이티브 mirror를 만들고 검증한다.
backend가 상품 변경을 필요로 하면 검토된 공개 commit의 snapshot과 provenance를
별도로 받아 서버용 매핑을 생성한다. 공개 catalog 변경만으로 backend가 배포되지는
않는다.

## 배포 산출물

공개 release의 정확한 버전은 [`release/macos.json`](../release/macos.json)과
[`release/windows.json`](../release/windows.json)이 소유한다. 네이티브 project 설정,
업데이트 feed와 웹 metadata는 검증되는 mirror다. Mac App Store 후보의 version/build는
[`macos/SIDEY.xcodeproj/project.pbxproj`](../macos/SIDEY.xcodeproj/project.pbxproj),
Windows build metadata는 해당 project file이 소유한다.

## 권위 순서

1. source code, project settings, manifest와 catalog 같은 machine-readable source
2. 현재 제품 및 아키텍처 문서
3. 장기 decision 문서의 선택 이유
4. 일반 구현 이력을 보존하는 Git commit과 pull request

Decision 문서는 현재 구현이나 현재 제품 명세를 덮어쓰지 않는다. 서로 충돌하면
machine-readable source를 먼저 확인하고 현재 문서를 고친다.
