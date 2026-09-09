# 캐릭터 피드백 1차 검토

`index.html`을 브라우저에서 열면 오프라인으로도 검토할 수 있다. 외부 폰트·네트워크 API·계정 연결이 없다. 소리는 직접 재생 버튼을 누를 때만 나온다.

- 말랑공 피격 3종과 공통 확대 3종. 각 후보별 원본과 0.5초 간격 3회 반복 WAV.
- 기존 햄스터 수면 프레임 8·9를 그대로 그린 기절 PNG, 코드로 정의한 별 아이콘 PNG, 30FPS 궤도/6초 기절 GIF.
- PNG·GIF는 개발 검토 렌더이며 실제 배포 앱의 화면 캡처가 아니다.
- `audio-manifest.json`·`visual-manifest.json`의 모든 승인 상태는 `pending`이다. 파일과 연출 수치가 고정된 검토 단위다.
- HTML에서 후보를 선택해도 승인이 저장되거나 앱에 적용되지 않는다. 피드백은 채팅으로 전달한다.

## 재현

저장소 루트에서 다음 명령을 각각 실행한다.

```sh
python3 docs/reviews/character-feedback/round-1/generate_audio.py
swift -module-cache-path /private/tmp/sidey-character-feedback-module-cache docs/reviews/character-feedback/round-1/render_preview.swift "$PWD" "$PWD/docs/reviews/character-feedback/round-1/visual"
python3 docs/reviews/character-feedback/round-1/verify_review.py
swift -module-cache-path /private/tmp/sidey-character-feedback-module-cache docs/reviews/character-feedback/round-1/verify_visuals.swift "$PWD/docs/reviews/character-feedback/round-1/visual"
node --check docs/reviews/character-feedback/round-1/review.js
```

음원은 표준 라이브러리로 만든 재현 가능한 자체 합성으로 외부 샘플을 사용하지 않는다. 픽셀 별은 기존 픽셀 렌더링에 맞춘 작은 코드 기반 아이콘이며 생성형 이미지 모델로 캐릭터를 다시 그리지 않는다. PNG·GIF는 macOS Core Graphics/ImageIO로 렌더한다. 승인 후 후보 파일을 재생성하면 해시가 달라질 수 있으므로 기존 승인 파일을 덮지 말고 새 버전으로 검토해야 한다.

## 검증 범위

PCM 형식·길이·peak/RMS·시작/끝 0·반복 간격, 후보/원본 SHA-256, 미승인 상태, HTML 파일 연결, JS 구문, PNG 크기·hard alpha, GIF 프레임 수·실제 지연 합계·6초 기절 구간을 검사한다. 합성 PNG는 직접 확인한다.

이 환경에서는 연결된 브라우저가 없어 실제 브라우저 버튼 클릭·청취 검증은 수행하지 못했다. 앱 코드를 변경하지 않았으므로 앱 테스트·빌드·30분 부하 검증은 아직 수행하지 않았다. 해당 검증은 승인 후 구현 단계에 남아 있다.
