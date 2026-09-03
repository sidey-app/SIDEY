# 캐릭터 에셋 PR

먼저 [`assets/README.md`](https://github.com/sidey-app/SIDEY/blob/main/assets/README.md)의 제작 규격과 제출 절차를 확인해 주세요.

## 공개 방식

하나만 선택해 주세요.

- [ ] 무료 캐릭터
- [ ] 유료 캐릭터

유료 캐릭터는 PR을 열기 전에 판매·정산 조건을 협의해야 합니다.
[ryu200112@gmail.com](mailto:ryu200112@gmail.com)으로 먼저 문의해 주세요.
제출만으로 출시·판매·수익 배분이 확정되지는 않습니다.
승인된 유료 에셋에는 [SIDEY Paid Asset License 1.0](https://github.com/sidey-app/SIDEY/blob/main/assets/PAID_ASSET_LICENSE.md)이 적용됩니다.

## 에셋 정보

- 캐릭터 이름:
- `character_id`:
- 투척물 이름과 `object_id`:
- 제작자 GitHub 계정:
- 제작 도구와 참고 자료:

## 제출 확인

- [ ] 캐릭터 파일을 `assets/v1/characters/<character_id>/`에 추가했습니다.
- [ ] 새 투척물이 있다면 `assets/v1/throwables/<object_id>/`에 추가했습니다.
- [ ] `assets/v1/manifest.json`의 경로·SHA-256·투척물 매핑을 갱신했습니다.
- [ ] `python3 scripts/validate_pixel_assets.py` 검사를 통과했습니다.
- [ ] [공개 에셋 프리뷰어](https://sidey-app.github.io/SIDEY/contribute/asset-previewer/)에서 전체 동작을 확인했습니다.
- [ ] 직접 제작했거나 SIDEY에 제출하고 배포할 권리를 보유한 에셋입니다.
- [ ] 유료 캐릭터인 경우 판매·정산·배포 권한을 정한 별도 서면 계약을 체결했습니다.

## 원본 전체본

<!-- 크롭하지 않은 원본 이미지나 전체 콘셉트를 PR 본문에 직접 첨부해 주세요. -->

여기에 원본 전체본을 첨부해 주세요.

## 프리뷰 결과

<!-- 공개 에셋 프리뷰어에서 확인한 스크린샷이나 녹화 영상을 첨부해 주세요. -->

여기에 프리뷰 결과를 첨부해 주세요.

## 추가 설명

<!-- 변경 이유, 기존 에셋 사용 여부, 리뷰어가 알아야 할 내용을 적어 주세요. -->
