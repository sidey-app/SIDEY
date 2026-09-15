# 발목·발 비율 보정 v1

상태: **사용자 요청에 따른 파생 수정·구현 담당자 시각 검토 완료**. 새 픽셀을 사용자가 개별 승인했다고 주장하지 않는다.

별도 파생 패키지이며 기존 승인 패키지의 재귀 파일 목록에 포함하지 않는다. [revision.json](revision.json)에 수정 요청과 구현 담당자 검토 범위를 기록했다. [원작 기여·이용 조건](../character-five/LICENSE.md)과 [SIDEY Paid Asset License 1.0](../../../assets/PAID_ASSET_LICENSE.md)을 따른다.

원본 Git SHA: `d8188a529b54c61969d4a987b782976bcca2e45c`. 각 원본·결과 SHA-256과 90프레임의 정확한 수정 좌표/RGBA는 [report.json](report.json)에 기록한다.

## 전후 비교

[정지 0·상승 1(쿼카 3)·피격 6 비교](review/summary.png) · [기니피그·원숭이 참고](review/references.png)

각 쌍은 BEFORE → AFTER다. 확대는 정수 nearest-neighbor이며 PNG 안에 기재된 배율을 따른다.

| 캐릭터 | 변경 프레임 | 변경 픽셀 | 비교표 |
| --- | ---: | ---: | --- |
| shiba | 15/18 | 126 | [전체 전후](review/pixel_shiba-all-frames.png) |
| duck | 15/18 | 126 | [전체 전후](review/pixel_duck-all-frames.png) |
| poop | 15/18 | 126 | [전체 전후](review/pixel_poop-all-frames.png) |
| tteokbokki | 15/18 | 134 | [전체 전후](review/pixel_tteokbokki-all-frames.png) |
| quokka | 18/18 | 96 | [전체 전후](review/pixel_quokka-all-frames.png) |

## 수정 범위

- 발바닥 y20을 3×1에서 2×1px로 줄인다. 왼발의 가장 왼쪽·오른발의 가장 오른쪽 픽셀만 없애며 기존 보폭과 발색을 유지한다.
- 상승 프레임은 y18 배 밑 내부에 바로 위의 기존 색을 이어 놓고 y19에 한 칸 좁은 외곽선을 둔다. 두 발은 몸과 수직으로 직접 연결하며 별도의 발색 기둥은 남기지 않는다.
- 시바·오리·똥·떡볶이 base 1/3/5와 throw_hit 6, 쿼카 base 3/5와 throw_hit 6의 발목을 조정한다.
- 신규 4종 base 7~9의 졸기·잠 실루엣 12프레임은 전체 RGBA를 보존한다. 쿼카는 잠든 프레임에도 분리된 두 발이 있어 너비만 줄인다.
- 모든 프레임에서 y0~17, 얼굴·눈·의상·팔·색과 셀 경계 접촉을 보존한다. 발 주변에서도 프레임별 허용 좌표 이외 변경을 거부한다.

원숭이의 발은 실제로 4~5px 폭이며 일부 상승 프레임에는 발 위 투명 행이 있다. 그 결함을 복제하지 않고, 기니피그의 2px 너비와 짧은 노출 비율을 참고했다.

## 재현·검증

저장소 루트에서 실행한다. 기본 실행은 후보 파일을 쓰지 않는다.

```sh
python3 -B docs/reviews/character-five/build_compact_feet_v1.py --write
python3 -B docs/reviews/character-five/build_compact_feet_v1.py
python3 -B docs/reviews/character-five/build_compact_feet_v1.py --self-test
```

원본 생성기 재현 → 고정 원본 해시 확인 → 90프레임 허용 좌표/기준선/연결/기존 팔레트/동작 프레임 다양성 검사 → 결과 바이트 비교 순서로 검증한다.

공용 원본과 웹 사본은 사용자 수정 지시에 따라 파생 출처를 기록해 승격한다. macOS 미러는 별도 플랫폼 작업에서 갱신한다. 기존 승인 JSON은 변경하지 않으며 새 픽셀의 사용자 승인 근거로 사용하지 않는다. 앱 공개 릴리스와는 별개다.
