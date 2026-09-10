(() => {
  const { groups, sounds } = globalThis.sideyAudioCandidates;
  const player = new Audio();
  player.preload = 'none';
  const status = document.querySelector('#playback-status');
  let generation = 0;
  let cueFrame = 0;
  let cues = [];
  let cueKind = 'hit';
  const cue = document.querySelector('#event-cue');

  function updateCue() {
    const active = cues.some(time => player.currentTime >= time && player.currentTime < time + .16);
    cue.textContent = active ? (cueKind === 'grow' ? '확대!' : '피격!') : '대기';
    cue.classList.toggle('active', active);
    if (!player.paused && !player.ended) cueFrame = requestAnimationFrame(updateCue);
  }

  function stop() {
    generation += 1;
    cancelAnimationFrame(cueFrame);
    cue.textContent = '대기'; cue.classList.remove('active');
    player.pause();
    player.removeAttribute('src');
    player.load();
    status.textContent = '재생을 멈췄습니다.';
  }

  async function play(file, label, eventTimes = [0], kind = 'hit') {
    stop();
    const request = generation;
    cues = eventTimes; cueKind = kind;
    player.src = file;
    status.textContent = label;
    try {
      await player.play();
    } catch {
      if (request === generation) status.textContent = '재생하지 못했습니다. WAV 파일을 직접 열어 주세요.';
    }
  }

  function button(text, action, ariaLabel, secondary = false) {
    const element = document.createElement('button');
    element.textContent = text;
    element.setAttribute('aria-label', ariaLabel);
    if (secondary) element.className = 'secondary';
    element.addEventListener('click', action);
    return element;
  }

  function candidateCard(candidate) {
    const card = document.createElement('article');
    card.className = 'sound-card';
    const label = document.createElement('label');
    label.className = 'candidate-label';
    const title = document.createElement('span');
    title.textContent = candidate.label;
    label.append(title);
    if (candidate.approval === 'approved') {
      const chosen = document.createElement('span');
      chosen.className = 'badge'; chosen.textContent = '선택 완료';
      label.append(chosen);
    } else {
      const radio = document.createElement('input');
      radio.type = 'radio'; radio.name = candidate.group_id; radio.value = candidate.id;
      radio.setAttribute('aria-label', `${candidate.label} 후보 선택`);
      label.append(radio);
    }
    const description = document.createElement('p');
    description.textContent = `${candidate.description} · ${candidate.duration_seconds.toFixed(2)}초`;
    const buttons = document.createElement('div');
    buttons.className = 'buttons';
    buttons.append(
      button('한 번 듣기', () => play(candidate.file, `${candidate.label} · 재생 중`, [0], candidate.kind), `${candidate.label} 한 번 듣기`),
      button('3회 피격 듣기', () => play(candidate.repeat_file, `${candidate.label} · ${candidate.repeat_interval_seconds}초 간격 3회`, [0, 1, 2].map(n => .15 + n * candidate.repeat_interval_seconds), candidate.kind), `${candidate.label} 세 번 듣기`, true),
    );
    const download = document.createElement('a');
    download.href = candidate.file; download.download = ''; download.textContent = 'WAV 다운로드';
    card.append(label, description, buttons, download);
    return card;
  }

  for (const group of groups) {
    const section = document.createElement('section');
    section.id = `group-${group.id}`;
    section.setAttribute('aria-labelledby', `heading-${group.id}`);
    const headingRow = document.createElement('div');
    headingRow.className = 'section-heading';
    const title = document.createElement('h2');
    title.id = `heading-${group.id}`; title.textContent = group.label;
    headingRow.append(title);
    if (group.comparison_file) {
      const order = group.kind === 'grow' ? 'C-1 → C-2 → C-3' : 'A → B → C';
      headingRow.append(button(`${order} 비교`, () => play(group.comparison_file, `${group.label} · ${order} 순서로 비교`, group.comparison_cues_seconds, group.kind), `${group.label} 순서대로 비교`, true));
    }
    const description = document.createElement('p');
    description.className = 'section-note'; description.textContent = group.description;
    const grid = document.createElement('div'); grid.className = 'sound-grid';
    for (const candidate of sounds.filter(item => item.group_id === group.id)) grid.append(candidateCard(candidate));
    section.append(headingRow, description, grid);
    document.querySelector('#sound-groups').append(section);
    const link = document.createElement('a');
    link.href = `#${section.id}`; link.textContent = group.label.split(' · ')[0];
    document.querySelector('#group-nav').append(link);
  }
  player.addEventListener('playing', () => { cancelAnimationFrame(cueFrame); updateCue(); });
  player.addEventListener('ended', () => { cancelAnimationFrame(cueFrame); cue.textContent = '대기'; cue.classList.remove('active'); });
  player.addEventListener('ended', () => { status.textContent = '재생이 끝났습니다.'; });
  document.querySelector('#stop-all').addEventListener('click', stop);
  document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });
  window.addEventListener('pagehide', stop);
  document.addEventListener('keydown', event => { if (event.key === 'Escape') stop(); });
  document.querySelector('#prepare-feedback').addEventListener('click', () => {
    const selections = groups.map(group => {
      const fixed = sounds.find(item => item.group_id === group.id && item.approval === 'approved');
      if (fixed) return `${fixed.label} (기존 선택 유지)`;
      const selected = document.querySelector(`input[name="${group.id}"]:checked`);
      return sounds.find(item => item.id === selected?.value)?.label ?? `${group.label}: 미선택`;
    });
    const notes = document.querySelector('#feedback-notes').value.trim() || '추가 의견 없음';
    const result = document.querySelector('#feedback-result');
    result.value = `SIDEY 6차 후보 선택\n${selections.join('\n')}\n\n다듬을 부분: ${notes}`;
    result.focus(); result.select();
  });
})();
