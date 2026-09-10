# 캐릭터 피드백 2차 검토

`index.html`을 브라우저에서 열어 개별·0.5초 간격 반복 청취와 PNG·GIF를 확인한다. 외부 서비스·폰트·API 없이 동작한다. 소리는 사용자가 재생할 때만 나온다.

## 이번 변경

- 말랑공 A: 짧고 밝게 튀어 오르는 한 번의 탄성.
- 말랑공 B: 두 번째 음이 높아지는 두 번의 탄성.
- 말랑공 C: 부드럽게 부풀고 밝게 마무리하는 고무 팝.
- 확대 A: 공기가 차오르는 풍선 장난감 질감.
- 확대 B: 비정수 배음의 종소리 세 음을 겹친 반짝이는 마법.
- 확대 C: 짧은 사각파 음계를 계단식으로 연주한 8비트 레벨업.
- 기절: 기존 수면 프레임·별 PNG·좌표·주기를 유지하고, 23×11 논리 픽셀 타원 궤도에 1px 두께 링을 추가했다. 링은 별보다 낮은 명도로 앞·뒤 색상을 구분한다.

모든 효과음과 링·합성 시안은 **승인 대기**다. 원본 캐릭터와 1차 후보는 수정하지 않았고 앱에는 적용하지 않았다. 음원은 자체 합성, 링은 기존 렌더러에 맞춘 코드 기반 픽셀 도형이다. 검토 화면은 배포 앱 캡처가 아니다.

## 재현·검증

저장소 루트에서 각각 실행한다.

```sh
python3 docs/reviews/character-feedback/round-2/generate_audio.py
swift -module-cache-path /private/tmp/sidey-character-feedback-module-cache docs/reviews/character-feedback/round-2/render_preview.swift "$PWD" "$PWD/docs/reviews/character-feedback/round-2/visual"
python3 docs/reviews/character-feedback/round-2/verify_review.py
swift -module-cache-path /private/tmp/sidey-character-feedback-module-cache docs/reviews/character-feedback/round-2/verify_visuals.swift "$PWD/docs/reviews/character-feedback/round-2/visual"
node --check docs/reviews/character-feedback/round-2/review.js
```

PCM 형식·길이·peak/RMS·시작/끝·반복 간격, 말랑공 실제 파형의 초반/후반 음높이, 파일 SHA-256, 승인 상태, 1차 별 PNG·궤도 수치 보존, 링·캐릭터 PNG의 hard alpha, GIF 실제 6초 구간을 검사한다. 확대음 세 분위기의 선호도·최종 크기와 링의 시각적 적합성은 사용자 청취·검토로 결정한다.

위 자동 검사와 JS 구문 검사, localhost 검토 페이지 HTTP 200 확인을 통과했고 합성 PNG를 직접 확인했다. 연결된 브라우저가 없어 브라우저 클릭·실제 청취 검증은 수행하지 못했다. 앱 테스트·빌드는 승인 후 구현 단계에 남아 있다.
