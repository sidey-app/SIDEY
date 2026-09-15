# 백엔드 개발 안내

SIDEY 백엔드의 구현 저장소는 조직의 비공개 [sidey-app/sidey-backend](https://github.com/sidey-app/sidey-backend)다. 접근 권한이 있는 계정으로 해당 저장소를 clone하고 현재 브랜치·변경 상태·`AGENTS.md`를 확인한 뒤 작업한다.

## 저장소별 책임

| 공개 SIDEY | 비공개 sidey-backend |
|---|---|
| macOS·Windows 앱과 Supabase 클라이언트 | Supabase schema·migration·RLS·Edge Functions |
| 공개 웹·checkout 브라우저 코드 | 결제·App Store 검증·서버 전용 운영 조회 |
| 상품·자산 원본과 공개 웹·native mirror 생성 | 서버용 상품 매핑·검증용 catalog snapshot |
| 앱·웹·자산·클라이언트 계약 검증 | DB·검증 서비스 테스트·수집·staging·배포 도구 |

독립 로컬 운영 어드민의 화면·API 코드는 `sidey-admin` 저장소에서 관리한다. 어드민이 사용하는 DB 조회와 가격 검증 계약은 backend가 소유한다.

## 상품 변경 전달

1. 공개 SIDEY의 `assets/v1/commerce-catalog.json`과 필요한 자산·manifest를 변경하고 검토·통합한다.
2. 공개 웹과 native mirror는 이 저장소의 `scripts/commerce_catalog.py`로 각각 생성·검증한다.
3. 서버 상품 변경이 필요하면 backend의 현재 clone에서 검토한 공개 커밋의 catalog·manifest snapshot을 반영하고 출처 커밋을 기록한다.
4. backend의 생성기·테스트로 verifier 매핑·Edge Function 허용 목록과 DB catalog의 일치를 검증한다. 서버 배포와 운영 migration은 backend의 배포 절차를 따른다.

공개 상품 JSON을 변경한 것만으로 서버 상품이 자동 변경되지는 않는다. backend의 기존 상품 snapshot을 새 상품 원본으로 독립 편집하지 않는다.

## 서버 문서와 이전 이력

- [서버 계약·변경 이력](https://github.com/sidey-app/sidey-backend/blob/main/docs/SERVER_CONTRACT.md)
- [운영 어드민·결제 조회 계약](https://github.com/sidey-app/sidey-backend/blob/main/docs/ADMIN_OPERATIONS.md)
- [App Store 검증 서비스 운영 안내](https://github.com/sidey-app/sidey-backend/blob/main/services/app-store-verifier/README.md)

2026-09-15 분리 기준은 CI를 통과한 공개 SIDEY main `f37cfc6b9544e4ac079fb7d9cec13039bdd21662`다. 이전 원본 `0cfe9af6ad546d529a3495eff692f1d2c5e0a074` 이후 백엔드 소스 변경이 없음을 대조했다. 이후 backend 작업·검증·배포는 비공개 저장소에서 진행한다. 공개 저장소의 과거 커밋에는 이전 서버 소스가 남아 있을 수 있으며, 이번 파일 이관은 과거 Git 이력이나 이미 배포된 사본의 삭제를 의미하지 않는다.
