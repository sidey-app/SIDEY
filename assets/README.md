# SIDEY 픽셀 에셋 라이브러리

이 폴더는 SIDEY 승인 픽셀 에셋의 단일 원본이다. 공개 인터페이스는
[`v1/manifest.json`](v1/manifest.json)과 캐릭터별 `base.png`, `throw_hit.png`,
투척물별 `sprite.png`다. 앱과 웹 폴더에 있는 같은 PNG 및 Windows BGRA는
배포용 mirror이며 직접 편집하지 않는다.

[공개 에셋 프리뷰어](https://sidey-app.github.io/SIDEY/contribute/asset-previewer/)는
파일을 서버로 보내거나 저장하지 않고 브라우저 메모리에서만 처리한다. SIDEY 웹
클라이언트가 아니라 컨트리뷰터가 제출 전 동작을 확인하는 도구다.

![햄스터 기본·throw/hit·패치 말랑공 공식 8배 참고 이미지](v1/reference/pixel_hamster_reference.png)

## 프레임 계약

### 기본 캐릭터 `base.png`

- `240×24` px, `24×24` px 셀 10개
- 0–1: idle 기본/호흡
- 2–5: 네 단계 보행
- 6–7: 서서 졸기/고개 끄덕임
- 8–9: 웅크린 offline 수면/호흡

### 캐릭터 동작 `throw_hit.png`

- `192×24` px, `24×24` px 셀 8개
- 0–3: 준비 → 힘주기 → 놓기 → 팔로스루
- 4–7: 접촉 → 눌림 → 튕김 → 복귀

### 투척물 `sprite.png`

- `192×16` px, `16×16` px 셀 12개
- 0–7: 프레임 사이에서 중심이 움직이지 않는 회전
- 8–11: 접촉 → 눌림 → 튕김 → 복귀

## 공통 제작 규칙

- sRGB, 8-bit RGBA, hard alpha(`0` 또는 `255`), 투명 배경
- 캐릭터 모든 프레임의 가장 낮은 불투명 픽셀은 바닥에서 3px 위의 같은 발 기준선
- 투척물 0–7 프레임의 회전 중심은 `7.5, 7.5`에 고정
- 안티앨리어싱과 실시간 그림자 금지
- 화면 확대는 `2×`, `3×`, `4×` 같은 정수 nearest-neighbor만 사용
- 픽셀을 흐리게 만드는 비정수 크기, 선형 보간, 반투명 가장자리 금지

별빛 우파루파처럼 idle 중 후광으로 보이는 ambient sparkle과 더블클릭 particle
burst를 제안할 수 있다. 이 효과는 PNG 프레임이 아니라 별도 렌더러 기능이다.
성능·색상·밀도·지속 시간 검토와 macOS/Windows 각각의 구현이 필요하며, 에셋
제출만으로 제품에서 자동 활성화되지 않는다.

## 신규 제출 절차

1. `assets/v1/characters/<character_id>/`에 `base.png`와 `throw_hit.png`를 추가한다.
2. 고유 투척물이 필요하면 `assets/v1/throwables/<object_id>/sprite.png`를 추가한다.
3. `manifest.json`의 캐릭터→투척물 매핑, fallback, 상대 경로, SHA-256을 갱신한다.
4. `python3 scripts/validate_pixel_assets.py`로 중앙 원본을 검사한다.
5. 중앙 변경을 먼저 리뷰한 뒤 플랫폼별 catalog와 배포 mirror는 별도 후속 PR에서
   갱신한다.

검사 통과를 위해 규격을 억지로 재인코딩하지 말고 원본 제작 파일에서 바로잡아야
한다. 승인된 `v1` 파일을 바꿀 필요가 생기면 기존 hash를 조용히 덮지 말고 변경
이유와 호환 영향을 함께 리뷰한다.
