# Mac App Store 후보 점검 — 2026-09-12

후보 소스: `macos/tree-right-click-controls`, 마케팅 버전 1.2.0, 임시 build 27.
이 문서는 로컬 구현·검증 상태다. 원격 상품 등록·서버 배포·심사 제출 완료를 뜻하지 않는다.

## 구현 완료

- A안 상세 화면: 한 미리보기 무대 아래 캐릭터와 **애착 물건** 구매 카드를 나란히 표시한다. 두 상품의 가격·보유·처리 상태를 각각 보여주고 별도 판매를 안내한다.
- 캐릭터 7종의 애착 물건을 독립 비소모성 상품으로 분리했다. 투척물 탭과 캐릭터 상세가 같은 상품 상태를 사용한다. 모든 캐릭터에서 사용할 수 있다.
- 기본 투척물은 공통 말랑공이다. 애착 물건 던져 보기는 로컬에서 한 번 재생하고 체험 배지를 표시한다. 서버 호출·장착 변경 없이 승인 효과음을 재생한다.
- 상품 카탈로그 24종을 공통 JSON으로 정의하고 macOS 두 타깃에 같은 자원을 포함한다. 기존 캐릭터 4종은 `_solo` 신규 SKU를 조회하며 기존 SKU도 복원·검증한다. StoreKit 설정과 서버 allowlist는 총 28개다.
- 기존 포함 물건은 부모 지급 출처에 연결한 별도 권리로 보전한다. 환불·회수·계정 연결 해제·지급 삭제는 해당 출처만 제거하고 독립 구매 권리는 유지한다. 전환 전 주문도 기존 구매 내용을 보존한다.
- DB 카탈로그에 관련 캐릭터·렌더링 ID를 추가하고 StoreKit 판매 ID와 논리 상품 ID를 분리했다. 새 migration은 아직 원격에 적용하지 않았다.
- 승인된 수달·돼지·나무, 두쫀쿠 늘어남·왁뿌볼 파편, 왁뿌볼 A·돼지고기 촵 등 기존 승인 이미지·음원을 유지한다.

## 로컬 검증

- macOS 전체 테스트 **285개 실행, 284개 통과, 외부 연동 1개 제외, 실패 0개**. 추가 테스트에서 7종 독립 소유권·공통 기본 공·구매 카드 4가지 보유 상태·일회성 체험·동작 줄이기·종료 정리를 확인했다.
- 마지막 구매 카드 정렬·단독 상세창 높이 수정 후 관련 테스트 **21개 추가 통과**.
- 음원 해시 검증 fixture를 테스트 번들로 옮겨 Documents 접근 권한 없이 승인 음원을 확인한다.
- verifier 테스트 **7개 통과**. PGlite PostgreSQL에서 실제 migration과 주요 원본 제약을 실행했다. 기존 선물·지연 복원·전환 전/후 주문·독립 구매·환불·stale callback·잘못된 ID·권한 거부·최종 출처 삭제, 기본 공·소유 물건의 실제 Broadcast payload와 미소유 장착 거부를 검증했다. 전체 Supabase RLS/Realtime 통합 검증을 대신하지 않는다.
- App Store Release Archive 생성·서명·bundle ID·verifier URL·dSYM 일치·Sparkle 미포함 검사 통과.
- Sidey-dev의 승인 이미지 13개·음원 7개 해시와 코드 서명을 검증하고 로컬 검토 모드로 설치·실행했다. 로그인·프로필 데이터는 초기화하지 않았다.
- 검토 캡처 도구의 배경·SpriteKit 좌표 수정은 별도 개발 빌드로 확인했다. 이 Debug 도구는 App Store Release에 포함되지 않는다.

## 앱에서 확인

Xcode 프로젝트: `_workspace/tree-right-click-controls/macos/SIDEY.xcodeproj`

- `SIDEYStoreReview` scheme → 실행: 로그인 없이 실제 상세 화면의 상품·보유 상태·가격 표시를 검토한다. 실제 결제는 진행하지 않는다.
- 설치된 `/Applications/Sidey-dev.app`도 `--store-review`로 실행 중이다.
- 실제 App Store 경로는 `SIDEYAppStore` scheme이다. 로컬 StoreKit 거래를 운영 계정 권리로 지급하지 않는다.
- `/Applications/SIDEYAppStore.app`에 있던 예전 설치본은 이번 결과물이 아니다. 수정 프로젝트 또는 아래 Archive를 사용한다.

## App Store Connect 및 배포 후속

1. [등록 안내](KEEPSAKE_APP_STORE_REGISTRATION.md)의 추가 11종(애착 물건 7 + 단품 캐릭터 4)을 등록한다. [CSV](keepsake-iap-products.csv)는 한국어 입력용이다.
2. 이전 신규 7종은 사용자가 초안 등록을 보고했다. 돼지의 올바른 ID `character_pig` 재등록 여부, 가격·지역·계약·현지화·심사 정보는 아직 원격 확인하지 않았다.
3. 기존 4개 SKU는 복원용으로 보존한다. 새 단품 출시 준비가 끝나기 전에 기존 SKU를 삭제하거나 판매를 중단하지 않는다.
4. 공통 migration과 verifier·Edge Function allowlist를 staging에 적용하고 Apple Sandbox 구매→서버 승인→장착→재실행/복원→환불, 계정 삭제·연결 해제·복수 지급을 실제 환경에서 검증한다. production 판매 잠금은 유지한다.
5. App Store의 실제 가격 조회와 심사 화면을 확인하고 업로드 이력에 맞는 build 번호를 확정한다. 최종 Apple Distribution export/validation을 수행한다. 현재 Archive는 Apple Development 서명이다.
6. Windows와 공개 웹의 카탈로그·안내 업데이트는 플랫폼별 후속 작업이다. 이번 macOS 분리 판매 서버 계약의 운영 전환은 구버전·다른 플랫폼 호환 검증 후 진행한다.

심사 제출·업로드·공개 릴리스·실결제·운영 DB 변경은 하지 않았다.

## 로컬 파일

- Archive: `/private/tmp/sidey-keepsakes-appstore/SIDEYAppStore.xcarchive`
- 전체 테스트 로그: `/private/tmp/sidey-keepsakes-tests.log`
- Archive 검증 로그: `/private/tmp/sidey-keepsakes-appstore-archive.log`
- 캡처와 등록 자료: `~/Downloads/SIDEY-store-refactor/`

[Apple 입력 항목 안내](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information) · [Sandbox 테스트 개요](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox)
