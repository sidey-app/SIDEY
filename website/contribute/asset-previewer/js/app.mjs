import { ASSET_CONTRACTS, MAX_PNG_BYTES, decodePng, inferAssetKind, loadBundledPng } from "./asset-loader.mjs";
import { characterScreenPoint, renderPreview } from "./canvas-renderer.mjs";
import { spawnParticles, stepParticles } from "./particles.mjs";
import { CanvasRecorder } from "./recording.mjs";
import {
  DEMO_DURATION_SECONDS,
  FIXED_STEP_SECONDS,
  createSimulationState,
  demoStateAt,
  frameForMode,
  pulseScaleAt,
  stepSimulation,
  throwTimelineAt,
} from "./simulation.mjs";

const canvas = document.querySelector("#preview-canvas");
const status = document.querySelector("#preview-status");
const validationList = document.querySelector("#validation-list");
const recordButton = document.querySelector("#record-button");

const state = {
  assets: null,
  mode: "idle",
  edge: "bottom",
  scale: 3,
  background: "checker",
  direction: 1,
  simulation: createSimulationState(),
  particles: [],
  ambientSparkle: false,
  pulseParticles: false,
  pulseElapsed: null,
  throwElapsed: null,
  demoElapsed: null,
  demoPhase: null,
  ambientElapsed: 0,
  particleSeed: 1,
  paused: false,
};

function announce(message, tone = "info") {
  status.textContent = message;
  status.dataset.tone = tone;
}

function updateAssetStatus(kind, message, tone) {
  const item = validationList.querySelector(`[data-kind="${kind}"]`);
  item.querySelector("span").textContent = message;
  item.dataset.tone = tone;
}

function closeAsset(asset) {
  if (asset?.bitmap && typeof asset.bitmap.close === "function") asset.bitmap.close();
}

async function loadDefaults() {
  const [base, throwHit, throwable] = await Promise.all([
    loadBundledPng("../../assets/characters/pixel_hamster.png", "base"),
    loadBundledPng("../../assets/previewer/pixel_hamster_throw_hit.png", "throwHit"),
    loadBundledPng("../../assets/previewer/patch_soft_ball.png", "throwable"),
  ]);
  state.assets = { base: base.bitmap, throwHit: throwHit.bitmap, throwable: throwable.bitmap };
  for (const kind of Object.keys(ASSET_CONTRACTS)) updateAssetStatus(kind, "공식 햄스터 세트 · valid", "valid");
  announce("공식 햄스터 세트를 불러왔음. 파일은 이 브라우저에서만 처리됨.", "success");
}

async function validateFiles(files, forcedKind = null) {
  const candidates = [];
  for (const file of files) {
    if (file.type && file.type !== "image/png") throw new Error(`${file.name}: PNG 파일만 지원함 (invalid_file_type)`);
    if (file.size > MAX_PNG_BYTES) throw new Error(`${file.name}: 파일이 2 MiB 제한을 넘음 (file_too_large)`);
    const buffer = await file.arrayBuffer();
    const kind = forcedKind ?? inferAssetKind(buffer);
    if (!kind) throw new Error(`${file.name}: 크기로 파일 종류를 판별할 수 없음 (unknown_asset_kind)`);
    if (forcedKind && files.length !== 1) throw new Error("개별 입력에는 파일 하나만 넣어야 함 (too_many_files)");
    if (candidates.some((candidate) => candidate.kind === kind)) throw new Error(`${file.name}: 같은 규격 파일이 중복됨 (duplicate_asset_kind)`);
    candidates.push({ file, kind });
  }

  const decoded = [];
  try {
    for (const candidate of candidates) decoded.push(await decodePng(candidate.file, candidate.kind));
  } catch (error) {
    decoded.forEach(closeAsset);
    throw error;
  }
  return decoded;
}

function applyDecodedAssets(decoded, sourceLabel) {
  for (const asset of decoded) {
    closeAsset({ bitmap: state.assets[asset.kind] });
    state.assets[asset.kind] = asset.bitmap;
    updateAssetStatus(asset.kind, `${sourceLabel}: ${ASSET_CONTRACTS[asset.kind].label} · valid`, "valid");
  }
  announce(`${decoded.length}개 PNG 검증 후 적용 완료. 서버 전송·저장 없음.`, "success");
}

async function handleFiles(files, forcedKind = null) {
  if (!files.length) return;
  if (!state.assets) {
    announce("공식 기본 세트 로드가 끝난 뒤 다시 시도해 주세요.", "error");
    return;
  }
  announce("PNG signature와 IHDR 확인 중…");
  try {
    const decoded = await validateFiles(files, forcedKind);
    applyDecodedAssets(decoded, files.length === 1 ? files[0].name : "드롭 세트");
  } catch (error) {
    if (forcedKind) updateAssetStatus(forcedKind, error.message, "error");
    announce(error.message, "error");
  }
}

document.querySelectorAll("input[type=file][data-kind]").forEach((input) => {
  input.addEventListener("change", () => {
    handleFiles(Array.from(input.files), input.dataset.kind);
    input.value = "";
  });
});

const dropZone = document.querySelector("#drop-zone");
for (const eventName of ["dragenter", "dragover"]) {
  dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.dataset.dragging = "true";
  });
}
for (const eventName of ["dragleave", "drop"]) {
  dropZone.addEventListener(eventName, (event) => {
    event.preventDefault();
    dropZone.dataset.dragging = "false";
  });
}
dropZone.addEventListener("drop", (event) => handleFiles(Array.from(event.dataTransfer.files)));

function stopDemo() {
  state.demoElapsed = null;
  state.demoPhase = null;
}

document.querySelector("#mode-control").addEventListener("change", (event) => {
  if (!event.target.matches("input[name=mode]")) return;
  stopDemo();
  state.mode = event.target.value;
  state.simulation = { ...state.simulation, actionElapsed: 0 };
  announce(`${event.target.nextElementSibling.textContent.trim()} 상태를 재생 중.`);
});

for (const [selector, key, parse] of [
  ["#edge-control", "edge", String],
  ["#scale-control", "scale", Number],
  ["#background-control", "background", String],
]) {
  document.querySelector(selector).addEventListener("change", (event) => {
    state[key] = parse(event.target.value);
  });
}
document.querySelector("#direction-control").addEventListener("change", (event) => {
  stopDemo();
  state.direction = Number(event.target.value) < 0 ? -1 : 1;
  state.simulation = { ...state.simulation, direction: state.direction };
});

document.querySelector("#ambient-control").addEventListener("change", (event) => {
  state.ambientSparkle = event.target.checked;
  state.ambientElapsed = 0;
});
document.querySelector("#burst-control").addEventListener("change", (event) => {
  state.pulseParticles = event.target.checked;
});

function pulse() {
  stopDemo();
  state.throwElapsed = null;
  state.pulseElapsed = 0;
  if (state.pulseParticles) {
    const point = characterScreenPoint(canvas, state.edge, state.simulation.position);
    state.particles = spawnParticles(state.particles, { x: point.x, y: point.y, count: 42, seed: state.particleSeed++ });
  }
  announce("더블클릭 7배 반응 재생.");
}

canvas.addEventListener("dblclick", pulse);
document.querySelector("#pulse-button").addEventListener("click", pulse);
document.querySelector("#throw-button").addEventListener("click", () => {
  stopDemo();
  state.pulseElapsed = null;
  state.throwElapsed = 0;
  announce("throw → 포물선 회전 → impact → hit 재생.");
});
document.querySelector("#demo-button").addEventListener("click", () => {
  state.demoElapsed = 0;
  state.demoPhase = null;
  state.throwElapsed = null;
  state.pulseElapsed = null;
  state.simulation = createSimulationState(0.25);
  setPaused(false);
  announce(`결정적 전체 데모 ${DEMO_DURATION_SECONDS}초 재생 시작.`);
});

const recorder = new CanvasRecorder(canvas, (recordingState, mimeType) => {
  if (recordingState === "recording") {
    recordButton.textContent = "녹화 중지";
    recordButton.setAttribute("aria-pressed", "true");
    announce(`프리뷰 Canvas만 녹화 중 · 최대 30초 · ${mimeType}`, "success");
  } else {
    recordButton.textContent = "영상 녹화";
    recordButton.setAttribute("aria-pressed", "false");
    announce(`무음 영상 저장 완료 · ${mimeType}`, "success");
  }
});

if (!recorder.supported) {
  recordButton.disabled = true;
  document.querySelector("#recording-fallback").hidden = false;
}
recordButton.addEventListener("click", () => {
  if (recorder.active) recorder.stop();
  else if (!recorder.start()) {
    document.querySelector("#recording-fallback").hidden = false;
    announce("이 브라우저는 지원 가능한 MediaRecorder 코덱이 없음.", "error");
  }
});

function advance() {
  let mode = state.mode;
  let direction = state.direction;
  if (state.demoElapsed != null) {
    state.demoElapsed += FIXED_STEP_SECONDS;
    if (state.demoElapsed >= DEMO_DURATION_SECONDS) {
      stopDemo();
      mode = "idle";
      state.mode = "idle";
      document.querySelector('input[name=mode][value="idle"]').checked = true;
      announce("전체 데모 완료.", "success");
    } else {
      const demo = demoStateAt(state.demoElapsed);
      mode = demo.mode;
      direction = demo.direction;
      if (demo.phase === "pulse") state.pulseElapsed = demo.pulseElapsed;
      else if (state.demoPhase === "pulse") state.pulseElapsed = null;
      if (demo.phase === "throw") state.throwElapsed = demo.throwElapsed;
      else state.throwElapsed = null;
      if (demo.phase === "pulse" && state.demoPhase !== "pulse" && state.pulseParticles) {
        const point = characterScreenPoint(canvas, state.edge, state.simulation.position);
        state.particles = spawnParticles(state.particles, { x: point.x, y: point.y, count: 42, seed: state.particleSeed++ });
      }
      state.demoPhase = demo.phase;
    }
  }

  state.simulation = stepSimulation(state.simulation, mode, direction);
  state.direction = state.simulation.direction;
  if (state.pulseElapsed != null && state.demoElapsed == null) {
    state.pulseElapsed += FIXED_STEP_SECONDS;
    if (state.pulseElapsed > 0.8) state.pulseElapsed = null;
  }
  if (state.throwElapsed != null && state.demoElapsed == null) state.throwElapsed += FIXED_STEP_SECONDS;
  state.particles = stepParticles(state.particles, FIXED_STEP_SECONDS);

  if (state.ambientSparkle) {
    state.ambientElapsed += FIXED_STEP_SECONDS;
    if (state.ambientElapsed >= 1.8) {
      state.ambientElapsed = 0;
      const point = characterScreenPoint(canvas, state.edge, state.simulation.position);
      state.particles = spawnParticles(state.particles, {
        x: point.x,
        y: point.y - 22,
        count: 5,
        seed: state.particleSeed++,
        minimumSpeed: 8,
        maximumSpeed: 24,
        minimumLifetime: 0.75,
        maximumLifetime: 1.15,
        minimumRadius: 2,
        maximumRadius: 2,
      });
    }
  }
}

function draw() {
  if (!state.assets) return;
  const demo = state.demoElapsed == null ? null : demoStateAt(state.demoElapsed);
  const mode = demo?.mode ?? state.mode;
  const distance = (state.edge === "bottom" || state.edge === "top" ? canvas.width : canvas.height) * 0.56;
  const timeline = state.throwElapsed == null ? null : throwTimelineAt(state.throwElapsed, distance);
  renderPreview(canvas, {
    assets: state.assets,
    mode,
    edge: state.edge,
    scale: state.scale,
    background: state.background,
    position: state.simulation.position,
    direction: demo?.direction ?? state.direction,
    baseFrame: frameForMode(mode, state.simulation.actionElapsed),
    pulseScale: pulseScaleAt(state.pulseElapsed),
    throwTimeline: timeline,
    particles: state.particles,
  });
}

let animationFrame = null;
let lastTimestamp = null;
let accumulator = 0;
function animate(timestamp) {
  if (lastTimestamp == null) lastTimestamp = timestamp;
  accumulator += Math.min(0.25, (timestamp - lastTimestamp) / 1000);
  lastTimestamp = timestamp;
  while (accumulator >= FIXED_STEP_SECONDS) {
    advance();
    accumulator -= FIXED_STEP_SECONDS;
  }
  draw();
  animationFrame = requestAnimationFrame(animate);
}

function startAnimation() {
  if (animationFrame != null || document.hidden || state.paused) return;
  lastTimestamp = null;
  accumulator = 0;
  animationFrame = requestAnimationFrame(animate);
}

function stopAnimation() {
  if (animationFrame != null) cancelAnimationFrame(animationFrame);
  animationFrame = null;
  lastTimestamp = null;
  accumulator = 0;
}

const pauseButton = document.querySelector("#pause-button");
function setPaused(paused) {
  state.paused = paused;
  pauseButton.textContent = paused ? "계속 재생" : "일시 정지";
  pauseButton.setAttribute("aria-pressed", String(paused));
  if (paused) {
    stopAnimation();
    announce("프리뷰 일시 정지.");
  } else {
    startAnimation();
  }
}
pauseButton.addEventListener("click", () => setPaused(!state.paused));

document.addEventListener("visibilitychange", () => {
  if (document.hidden) stopAnimation();
  else startAnimation();
});

try {
  await loadDefaults();
  startAnimation();
} catch (error) {
  announce(error.message, "error");
}
