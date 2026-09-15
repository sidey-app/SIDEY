# 콘텐츠·가격·macOS 배포판 변경 검토

## 범위와 상태

확정 상품 가격, 승인 캐릭터 5종·독립 투척물 4종, macOS 양 배포판 기절·제품 이름, macOS/Windows 나무 정지 공유를 준비한다. 캐릭터 17종·기본 포함 투척물 19종·유료 상품 33개이며 Windows는 기존 24개 상품을 유지한다. 사용자의 PR 생성·병합 승인에 따라 아래 의존 순서로 검토·통합한다. 버전 인상·앱 공개 릴리스·App Store 제출·운영 backend 배포는 하지 않는다.

## 검토 원본

- 기존 상품 가격: `58e41077b9eca6a0c224328a872dc8647842e9e8` ([PR #145](https://github.com/sidey-app/SIDEY/pull/145)).
- 신규 9개 상품과 승인 원본: `57ac0ff65824103c19b62f2da31391e2d341a7d6` ([PR #146](https://github.com/sidey-app/SIDEY/pull/146)). 검토한 PR 원본과 실제 main에 통합된 두 JSON 및 승인 자산의 바이트가 같다.
- 승인 패키지 72개 항목의 미승인·누락 없음. 선택한 시트·음원 18개는 승인 원본과 byte·SHA-256이 일치한다. 재사용 삑삑 오리는 기존 상품·시트·음원을 유지한다.

## 머지 시 필수 순서

1. [Windows 기존 카탈로그 출처 고정 #143](https://github.com/sidey-app/SIDEY/pull/143).
2. 공용 기존 상품 가격 #145.
3. [macOS #149](https://github.com/sidey-app/SIDEY/pull/149)와 [Windows #148](https://github.com/sidey-app/SIDEY/pull/148)의 기존 상품 가격 카탈로그 및 나무 공유 동작.
4. 공용 신규 콘텐츠 #146.
5. [macOS 신규 콘텐츠 #150](https://github.com/sidey-app/SIDEY/pull/150) 연결.
6. 공용 macOS 지원 선언과 이 문서의 최종 검증 기록.
7. 공개 원본을 참조하는 [backend 상품 PR](https://github.com/sidey-app/sidey-backend/pull/3)의 최종 snapshot 검증.

각 단계는 최신 main에 동기화하고 정확한 PR head의 필수 CI를 다시 확인한다. 선행 Windows 출처 고정이 없는 공용 가격·콘텐츠 PR의 Windows 카탈로그 검사는 의도한 배포 순서가 아직 반영되지 않아 실패한다. 이를 통과로 취급하거나 검사를 완화하지 않는다.

플랫폼 `catalog-source.json`과 backend `SOURCE.json`은 위의 실제 공개 main 커밋으로 고정했다. Windows는 기존 24개 상품 가격 커밋을, macOS와 backend는 신규 33개 상품 커밋을 사용한다. squash 전후 원본 JSON 해시가 같음을 확인하고 생성기·카탈로그·필수 CI를 다시 실행한다. 마지막 macOS 지원 선언은 원본 상품·자산 바이트를 변경하지 않으며, 소비자의 출처 고정은 그대로 유지한다.

## 확인한 검증

- macOS 로컬 신규 콘텐츠: 직배포 301개(기존 backend 연동 1개 제외)·App Store 37개·Recording 10개·Python 6개 통과. 양쪽 Debug·Release·archive 6개 산출물의 이름·bundle·카탈로그·원본 자산·빌드 출처와 두 archive의 dSYM UUID 일치를 확인했다. 로컬 ad-hoc 서명이며 제출용 서명 검증은 아니다.
- 신규 macOS 지원 선언은 공용 manifest와 각 플랫폼 작업 디렉터리의 실제 PNG/BGRA를 함께 읽어 모든 선언 미러의 byte 일치를 사전 확인했다. 한 Git head의 통합 CI는 선행 PR 통합 후 별도로 확인한다.

- 신규 공용 콘텐츠 PR #146의 Python 검사 86개, 17개 base·17개 action·19개 투척물·3개 말풍선의 원본 및 선언된 미러 검사 통과.
- 신규 공용 콘텐츠의 [최종 통합 CI](https://github.com/sidey-app/SIDEY/actions/runs/34988174572)는 macOS·Windows·공용·웹 모두 통과했다. 웹 47개 페이지 빌드와 테스트 15개 통과. 브라우저 연결 부재로 실제 데스크톱·모바일 화면 검사는 미완료다.
- 공개 [Pages 배포](https://github.com/sidey-app/SIDEY/actions/runs/34989113680)는 신규 공용 원본 `57ac0ff`로 성공했다. 한·영·일 상점 12페이지의 상품 33개·가격·지원 안내와 총 26개 URL HTTP 200을 확인했고, PNG 9개·WAV 4개 및 상품 JS는 승인 원본과 일치했다. 최종 지원 선언 배포 후 같은 HTTP 검사를 다시 확인한다.
- Windows Core 199개·Presentation 146개 통과. 새 가격에서 화면 생성이 실패하던 고정 가격 분기를 수정했고 7개 언어 원화 표시를 검증했다. Windows PR head `6ad05eaf075ebbbfd47ec6c99d7c1a1ffa312647`의 전체 Release·플랫폼 테스트·패키징·앱 smoke가 [CI](https://github.com/sidey-app/SIDEY/actions/runs/34983219991)에서 통과했다.
- backend verifier/PGlite 29개·Python 2개·수집기 5개와 [전체 Supabase reset·pgTAP·동시성 CI](https://github.com/sidey-app/sidey-backend/actions/runs/34989392191) 통과. 상품 PR #3을 `25a5b5dcf32be04ea522e9632d8340282a09a26e`로 병합하고 private primary main의 트리 일치를 확인했다. migration 재실행·이전 주문/Apple 금액·복원 권리·독립 소유권·18개 유료 투척물 경로를 검증했다. 운영 DB는 변경하지 않았다.

- squash 후 앱 검증은 실제 main의 merge 커밋 포함 여부와 검증된 PR head의 트리 일치로 확인하도록 수정했다. 실제 Git squash·후속 main 전진·거부 조건 9개를 포함한 workflow 테스트 30개가 통과했다.

## 후속 출시 확인

- App Store Connect에서 기존 상품의 실제 한국 가격을 확정된 등급과 대조하고, 신규 9개 상품·판매 국가·심사 정보를 등록한다. 현재 운영 가격을 조회하거나 바꾸지 않았으므로 차이가 없다고 주장하지 않는다. 앱은 Apple이 반환하는 현지화 가격을 표시한다.
- 운영 backend migration과 verifier 배포, 클라이언트 업데이트 이후 실제 서로 다른 macOS/Windows 계정·기기에서 늦은 입장·재접속·방 이동·다중 기기의 나무 공유를 확인한다. 현재 자동 테스트는 클라이언트 상태 처리와 DB 계약을 각각 검증하며 운영 기기 간 실측을 대신하지 않는다.
- 새 main의 두 macOS 배포판 실행 출처와 current-main Windows smoke를 최종 확인하고 웹 자동 배포 결과를 확인한다. 검토용 브랜치 실행과 PR CI는 공개 출시 완료가 아니다.
