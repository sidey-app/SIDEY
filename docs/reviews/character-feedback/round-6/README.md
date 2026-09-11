# 6차 효과음 검토 — 하트 뾲뾲

[검토 페이지](index.html) · macOS 직배포판용 후보. 새 하트의 적용 승인 대기.

사용자가 오리 5차 B·대포 5차 C를 선택했다. 이전에 고른 말랑공 A·파프리카 C·바나나 B·모래주머니 C·별빛 구슬 B를 합쳐 일곱 음원과 반복 WAV를 바이트·음량 변경 없이 보존한다. 확대음은 폐기 상태를 유지한다.

하트는 입술을 터뜨리는 `뾲뾲` 느낌으로 새 세 후보를 준비했다. 각각 별개의 CC0 mouth-pop 녹음을 사용하며 한 번 맞을 때 두 번의 짧은 입술 팝을 재생한다. A는 짧고 동그랗게, B는 여유 있고 말랑하게, C는 빠르고 또렷하게 편집한다. 원본 앞뒤의 불필요한 여운을 자르고 작은 속도 변화·선형 음량 조절·fade만 적용했다. 합성 발진음이나 포화 효과를 섞지 않았다.

- A: fleurescence, [Mouth pop](https://freesound.org/people/fleurescence/sounds/573153/).
- B: jcallison, [Mouth pop](https://freesound.org/people/jcallison/sounds/258269/).
- C: hollandm, [Mouth pop 1](https://freesound.org/people/hollandm/sounds/691906/).

공개 HQ MP3와 디코딩 WAV, CC0 라이선스·원본 URL·저자·해시는 `sources/manifest.json`에 보존한다. FFmpeg 7.1로 48kHz mono PCM16 변환 후 순수 Python으로 편집한다. 기존 선택 음원 출처는 4차 소스 기록을 참조한다.

한 번 듣기 버튼은 하트 1회 피격의 뾲뾲이고, 3회 피격 듣기는 이를 0.5초 간격으로 세 번 재생한다. 후보의 선택·피드백은 채팅으로 전달해야 하며 자동 승인·앱 적용하지 않는다.

검증 통과: 후보 10개(새 하트 3, 선택 원본 7)·WAV 21개, 기존 원본 바이트 보존, 오리 B·대포 C 선택, 하트의 분리된 두 팝과 무음 간격, sample 재현·peak 상한·fade 경계·반복/비교 PCM·SHA-256·소스 해시, 정적 HTML 링크·JavaScript 문법. 실제 청감과 브라우저 조작은 사용자 검토가 필요하다.

```sh
python3 docs/reviews/character-feedback/round-6/generate_audio.py
python3 docs/reviews/character-feedback/round-6/verify_review.py
node --check docs/reviews/character-feedback/round-6/review.js
```
