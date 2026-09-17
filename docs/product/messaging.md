# 메시징

## 영구 데이터와 실시간 신호

Postgres가 메시지의 source of truth다. 클라이언트는 UUID로 메시지를 낙관적으로
표시하되 message.ack와 message.created 알림을 같은 UUID로 조정한다. 확정 여부가 불분명한
실패도 같은 UUID로 확인하고 재시도해 중복 발송을 만들지 않는다. 메시지는 서버
보관 정책에 따라 생성 후 사흘이 지나면 삭제된다.

Presence는 ONLINE·AWAY·OFFLINE만 표시한다. 기기는 자신의 active room, 활동 상태와
heartbeat를 보내고 서버가 같은 사용자의 여러 기기를 합산한다. OS idle 5분 이상이거나
화면이 잠기면 AWAY다. Reconnecting은 해당 기기의 transport 상태이며 상대방 presence가 아니다.
Typing과 캐릭터 pulse·throw는 별도 일시 이벤트이며 복구하거나 DB에 저장하지 않는다.

재연결은 authorized room 구독을 먼저 등록하고 live 메시지를 받으면서 복구한다.
구독 ACK의 `recoveryThrough`까지 REST를 `(created_at,id)` 순서로 끝까지 조회한다.
이전 완료 checkpoint 이후의 결과와 live 메시지를 UUID로 합치고, 복구가 모두 완료된
후에만 checkpoint를 저장하고 READY가 된다. 가장 최근 live timestamp를 checkpoint로
사용하지 않으며 cursor의 microsecond 정밀도를 보존한다. 실패한 복구는 checkpoint를
진행시키지 않는다. 느린 연결이 종료되어도 같은 과정으로 보관 기간 내 메시지를 회수한다.

`room.changed`는 REST room/profile snapshot을 새로 읽는 힌트다. 서버가 탈퇴·추방된
구독자에게 별도 알림을 보내지 않을 수 있으므로 클라이언트는 membership을 주기적으로
재확인한다. 권한 거부를 받으면 즉시 해당 방 상태와 구독을 정리한다.

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
