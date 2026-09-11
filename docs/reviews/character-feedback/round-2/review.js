(() => {
  const candidates = globalThis.sideyAudioCandidates.sounds;
  const player = new Audio();
  player.preload = 'none';
  const status = document.querySelector('#playback-status');
  let generation = 0;

  function stop() {
    generation += 1;
    player.pause();
    player.removeAttribute('src');
    player.load();
    status.textContent = '재생을 멈췄습니다.';
  }

  async function play(candidate, repeat) {
    stop();
    const request = generation;
    player.src = repeat ? candidate.repeat_file : candidate.file;
    status.textContent = `${candidate.label} · ${repeat ? '세 번' : '한 번'} 재생 중`;
    try {
      await player.play();
    } catch (error) {
      if (request === generation) status.textContent = '재생하지 못했습니다. WAV 다운로드로 직접 들어 주세요.';
    }
  }

  for (const candidate of candidates) {
    const card = document.createElement('article');
    card.className = 'sound-card';
    const label = document.createElement('label');
    label.className = 'candidate-label';
    const name = document.createElement('span');
    name.textContent = candidate.label;
    const radio = document.createElement('input');
    radio.type = 'radio'; radio.name = candidate.kind; radio.value = candidate.id;
    radio.setAttribute('aria-label', `${candidate.label} 후보 선택`);
    label.append(name, radio);
    const description = document.createElement('p');
    description.textContent = `${candidate.description} · ${candidate.duration_seconds.toFixed(2)}초`;
    const buttons = document.createElement('div'); buttons.className = 'buttons';
    for (const repeat of [false, true]) {
      const button = document.createElement('button');
      button.textContent = repeat ? '세 번 듣기' : '한 번 듣기';
      button.setAttribute('aria-label', `${candidate.label} ${button.textContent}`);
      if (repeat) button.className = 'secondary';
      button.addEventListener('click', () => play(candidate, repeat));
      buttons.append(button);
    }
    const download = document.createElement('a');
    download.href = candidate.file; download.download = ''; download.textContent = 'WAV 다운로드';
    card.append(label, description, buttons, download);
    document.querySelector(`#${candidate.kind}-candidates`).append(card);
  }
  player.addEventListener('ended', () => { status.textContent = '재생이 끝났습니다.'; });
  document.querySelector('#stop-all').addEventListener('click', stop);
  document.addEventListener('visibilitychange', () => { if (document.hidden) stop(); });
  window.addEventListener('pagehide', stop);
  document.querySelector('#prepare-feedback').addEventListener('click', () => {
    const selections = ['hit', 'grow'].map(kind => {
      const selected = document.querySelector(`input[name="${kind}"]:checked`);
      return candidates.find(item => item.id === selected?.value)?.label ?? `${kind === 'hit' ? '말랑공' : '확대'}: 아직 선택하지 않음`;
    });
    const notes = document.querySelector('#visual-feedback').value.trim() || '아직 의견을 적지 않음';
    const result = document.querySelector('#feedback-result');
    result.value = `SIDEY 2차 시안 피드백\n소리 후보: ${selections.join(' / ')}\n소리·기절 링: ${notes}\n(후보 선택 및 피드백이며, 최종 에셋 승인은 별도입니다.)`;
    result.focus(); result.select();
  });
})();
