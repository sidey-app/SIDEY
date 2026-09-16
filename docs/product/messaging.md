# 메시징

## 영구 데이터와 실시간 신호

Postgres가 메시지의 source of truth다. 클라이언트는 UUID로 메시지를 낙관적으로
표시하되 저장 결과와 Realtime 알림을 같은 UUID로 조정한다. 확정 여부가 불분명한
실패도 같은 UUID로 확인하고 재시도해 중복 발송을 만들지 않는다. 메시지는 서버
보관 정책에 따라 생성 후 사흘이 지나면 삭제된다.

Presence는 연결·online·away 상태에 사용한다. Broadcast는 SIDEY 입력창의 typing,
캐릭터 pulse와 projectile 같은 저장하지 않는 event에만 사용한다. DB 변경 알림은
식별자만 전달하고 client가 RLS를 거쳐 row를 다시 읽는다. 연결이 복구되면 membership,
presence와 최근 메시지를 다시 맞춘 뒤 online으로 전환한다.

## 작성과 표시

메시지 입력은 최대 200자·3줄을 허용한다. Enter는 전송,
Shift+Enter는 줄바꿈이다. Typing은 SIDEY 입력창의 lease 동안만 표시하고 실제 메시지
말풍선이 있으면 본문을 우선한다.

Overlay는 발신자별 최신 메시지를 최대 두 개 표시하고 각각 일정 시간이 지나면
없앤다. 과거 기록 조회나 reconnect snapshot은 지나간 말풍선을 다시 재생하지 않는다.
조용히 모드는 새 메시지 본문 말풍선을 숨기지만 typing과 그룹별 미확인 수는 유지한다.

최근 기록은 server retention 범위에서 페이지로 읽는다. Pending과 failed 전송은 원래
방의 outbox에 남으며 다른 방의 draft를 바꾸지 않는다.

## 보안 경계

Room membership, message rate와 transient event 권한은 서버가 확인한다. 로그에는
message body, token, 평문 invite code와 사용자·방·메시지 식별자 원문을 남기지 않는다.
