# 백엔드 개발 안내

현재 클라이언트의 source of truth는 sibling `sidey-server`의 `CONTRACT.md`와
Spring controller·service 구현이다. 기존 `sidey-backend`의 Supabase SQL·function은
데이터 이전과 과거 동작의 reference이며 새 클라이언트의 실행 계약이 아니다.
Backend remote는 조직의 비공개 [sidey-app/sidey-backend](https://github.com/sidey-app/sidey-backend)다.
작업 전 checkout의 branch·변경 상태·지침을 확인하고 서로 다른 구현 이력을 혼동하지 않는다.

## 저장소별 책임

| 공개 SIDEY | 비공개 Spring backend |
|---|---|
| macOS·Windows REST·raw WebSocket·SIDEY session client | Spring Security·provider 검증·session rotation |
| 공개 웹·checkout 브라우저 코드 | 주문·PortOne·App Store 검증·grant ledger |
| 상품·자산 원본과 공개 웹·native mirror 생성 | 서버용 상품 매핑·검증용 catalog snapshot |
| 앱·웹·자산·클라이언트 계약 검증 | PostgreSQL·Flyway·jOOQ·migration·배포 도구 |

클라이언트에 서버 secret이나 provider 우회 검증을 넣지 않는다. 기존 계정 credential은
legacy claim의 ownership proof 용도만 남기며 일반 요청은 SIDEY session을 사용한다.

## 상품 변경 전달

1. 공개 SIDEY의 `assets/v1/commerce-catalog.json`과 필요한 asset·manifest를 검토한다.
2. 웹과 native mirror는 `scripts/commerce_catalog.py`로 생성·검증한다.
3. backend는 검토한 공개 commit의 catalog·manifest snapshot과 provenance를 반영한다.
4. backend의 mapping·catalog·grant·App Store tests로 일치 여부를 검증한다.

공개 catalog 변경만으로 서버 상품이 자동 변경되지는 않는다. 결제 secret, 운영 데이터와
서버 배포 절차는 공개 저장소에 복제하지 않는다. 서버 구현·검증·배포는 비공개 checkout에서
수행하며 클라이언트 commit이나 branch merge가 production cutover를 의미하지 않는다.
