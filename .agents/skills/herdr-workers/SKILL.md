---
name: herdr-workers
description: SIDEY를 Herdr Desktop에서 병렬 작업할 때 현재 Codex 패널을 메인으로 두고, 작업별 Codex 워커를 같은 탭에 표시하며 새 작업으로 전환할 때 이전 워커를 교체한다.
---

# Herdr 워커 패널

메인이 작업 분배와 결과 통합을 맡는다. 워커로 배정받은 세션은 배정된 일만 수행한다.

1. **메인을 식별한다.** `herdr-app ls`에서 현재 프로젝트의 space, tab, Codex 터미널 ID를 찾는다. `HC_TERMINAL_ID`와 화면 포커스는 단서일 뿐이다. 불일치하면 현재 대화 내용이나 이전에 확인한 메인 ID를 대조한다. 식별이 모호하면 패널을 조작하기 전에 대상부터 확인한다.
2. **작업이 바뀌었는지 판단한다.** 같은 목표의 질문·정정·추가 검증이면 기존 워커에 `hc send <terminal> <지시>`로 이어서 맡긴다. 별개의 목표면 이전 작업의 결과와 미완료 변경을 메인에 먼저 회수한다. `hc ls --json`의 직접 자식들을 `hc get <terminal>`로 조회해 아래의 소유 라벨과 이전 작업 ID를 확인한다. 종료 가능한 워커마다 스킬 폴더의 `python3 scripts/close_worker.py <parent> <old-task> <terminal>`을 실행한다. 사람이 입력 중인 패널은 보존한다. 진행 중이면 결과를 기다리거나 명시적으로 취소된 일만 중단하고 상태를 다시 확인한다. 새 작업이 단독 작업이면 정리 후 메인에서 계속한다.
3. **역할마다 새 패널을 연다.** 새 목표에는 새 작업 ID를 정하고, 같은 목표의 후속 지시에는 그 ID를 유지한다. 아래 변수들은 메인이 확인한 값으로 채운다. 재시도 시 같은 작업·역할의 워커가 이미 열렸으면 그 주소를 사용한다. 이름은 현재 프로세스들과 겹치지 않게 32자 이내로 짓는다.

   ```sh
   hc run --bg --json --no-notify --parent "$parent" --name "$worker_name" \
     --cwd "$worktree" --label sidey.owner=herdr-workers --label "sidey.task=$task_id" \
     --label "sidey.role=$role" --label "herdr.space=$space" --label "herdr.tab=$tab" -- \
     codex --no-daemon fork --sandbox "$worker_sandbox" --cd "$worktree" "$parent_thread" "$assignment"
   ```

   `parent_thread`는 메인 대화의 Codex thread ID다. fork 시점까지의 대화가 복사된다. 지시에 역할, 현재 목표, 읽거나 수정할 경로, 결과 형식을 명시한다. 리뷰는 읽기 전용으로, 구현은 메인에 허용된 범위 안에서 서로 겹치지 않는 파일이나 작업 트리로 배분한다. 같은 역할을 내장 서브에이전트와 패널 양쪽에 중복 배정하지 않는다.
4. **작업과 표시를 확인한다.** `herdr-app ls`에서 새 터미널이 지정한 탭에 보이는지, `hc get`에서 부모와 실행 상태가 맞는지 확인한다. `herdr-app do agent.focus --terminal "$parent"`로 메인에 포커스를 돌린다. `hc wait`와 `hc read`로 각 결과를 회수한다. 다른 워커에게 필요한 결정이나 경로는 메인이 메시지로 전달한다. 작업 완료 후 다음 배정까지 패널을 열어둔다.

Herdr 연결이 없으면 표시할 수 있는 패널 수를 실제 상태대로 알린다. 연결 실패나 포커스 이동을 이유로 다른 터미널을 닫지 않는다.
