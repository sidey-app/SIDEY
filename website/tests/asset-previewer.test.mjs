import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { ASSET_CONTRACTS, inferAssetKind, inspectPng } from "../contribute/asset-previewer/js/asset-loader.mjs";
import { MAX_PARTICLES, spawnParticles, stepParticles } from "../contribute/asset-previewer/js/particles.mjs";
import { extensionForMimeType, selectRecordingMimeType } from "../contribute/asset-previewer/js/recording.mjs";
import {
  FIXED_STEP_SECONDS,
  computeFlightDuration,
  createSimulationState,
  demoStateAt,
  frameForMode,
  stepSimulation,
  throwTimelineAt,
} from "../contribute/asset-previewer/js/simulation.mjs";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url));
const toArrayBuffer = (buffer) => buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);

test("frame selection follows the ten-frame base contract", () => {
  assert.deepEqual([0, 0.6, 1.2].map((time) => frameForMode("idle", time)), [0, 1, 0]);
  assert.deepEqual([0, 0.12, 0.24, 0.36].map((time) => frameForMode("walk", time)), [2, 3, 4, 5]);
  assert.deepEqual([frameForMode("doze", 0), frameForMode("doze", 0.5)], [6, 7]);
  assert.deepEqual([frameForMode("offline", 0), frameForMode("offline", 0.65)], [8, 9]);
});

test("fixed 30 FPS steps move deterministically and reverse at bounds", () => {
  let state = createSimulationState(0.5);
  for (let index = 0; index < 30; index += 1) state = stepSimulation(state, "walk", 1);
  assert.ok(Math.abs(state.position - 0.61) < 1e-10);
  assert.ok(Math.abs(state.actionElapsed - 30 * FIXED_STEP_SECONDS) < 1e-10);

  state = createSimulationState(0.879);
  state = stepSimulation(state, "walk", 1);
  assert.equal(state.position, 0.88);
  assert.equal(state.direction, -1);
});

test("throw timeline reproduces release, rotation, impact, and hit timing", () => {
  assert.equal(computeFlightDuration(0), 0.35);
  assert.equal(computeFlightDuration(1600), 0.95);
  assert.equal(throwTimelineAt(0.19, 400).objectFrame, null);
  assert.equal(throwTimelineAt(0.2, 400).phase, "flight");
  assert.equal(throwTimelineAt(0.284, 400).objectFrame, 1);

  const impactAt = 0.2 + computeFlightDuration(400);
  const impact = throwTimelineAt(impactAt + 0.12, 400);
  assert.equal(impact.phase, "impact");
  assert.equal(impact.objectFrame, 10);
  assert.equal(impact.targetFrame, 5);
  assert.equal(throwTimelineAt(impactAt + 0.45, 400).phase, "done");
});

test("twenty-second demo covers both walk directions and all major states", () => {
  assert.equal(demoStateAt(0).phase, "idle");
  assert.deepEqual([demoStateAt(2).direction, demoStateAt(5).direction], [1, -1]);
  assert.equal(demoStateAt(8).phase, "doze");
  assert.equal(demoStateAt(11).phase, "offline");
  assert.equal(demoStateAt(13).phase, "pulse");
  assert.equal(demoStateAt(19.99).phase, "throw");
});

test("recording MIME negotiation uses the first supported codec and matching extension", () => {
  const supported = new Set(["video/webm", "video/mp4"]);
  assert.equal(selectRecordingMimeType((mime) => supported.has(mime)), "video/webm");
  assert.equal(selectRecordingMimeType(() => false), null);
  assert.equal(extensionForMimeType("video/webm;codecs=vp9"), "webm");
  assert.equal(extensionForMimeType("video/mp4"), "mp4");
});

test("particle creation is deterministic and never exceeds the hard cap", () => {
  const options = { x: 10, y: 20, count: MAX_PARTICLES + 50, seed: 42 };
  const first = spawnParticles([], options);
  const second = spawnParticles([], options);
  assert.equal(first.length, MAX_PARTICLES);
  assert.deepEqual(first, second);
  assert.ok(stepParticles(first, 0.1).length <= MAX_PARTICLES);
  assert.equal(spawnParticles(first, { ...options, seed: 99 }).length, MAX_PARTICLES);
});

test("particle ranges honor their named minimum and maximum bounds", () => {
  const particles = spawnParticles([], {
    x: 0,
    y: 0,
    count: 100,
    seed: 17,
    minimumSpeed: 8,
    maximumSpeed: 24,
    minimumLifetime: 0.75,
    maximumLifetime: 1.15,
    minimumRadius: 2,
    maximumRadius: 3,
  });

  for (const particle of particles) {
    const speed = Math.hypot(particle.vx, particle.vy);
    assert.ok(speed >= 8 && speed <= 24);
    assert.ok(particle.lifetime >= 0.75 && particle.lifetime <= 1.15);
    assert.ok(particle.radius >= 2 && particle.radius <= 3);
  }
});

test("bundled PNG headers satisfy each public interface contract", async () => {
  const files = [
    ["../assets/v1/characters/pixel_hamster/base.png", "base"],
    ["../assets/v1/characters/pixel_hamster/throw_hit.png", "throwHit"],
    ["../assets/v1/throwables/patch_soft_ball/sprite.png", "throwable"],
  ];
  for (const [path, kind] of files) {
    const bytes = await read(path);
    const buffer = toArrayBuffer(bytes);
    assert.equal(inferAssetKind(buffer), kind);
    assert.equal(inspectPng(buffer, ASSET_CONTRACTS[kind]).frameCount, ASSET_CONTRACTS[kind].frameCount);
  }
});

test("PNG preflight rejects a bad signature and wrong IHDR dimensions before decoding", async () => {
  const source = await read("../assets/v1/characters/pixel_hamster/base.png");
  const badSignature = Uint8Array.from(source);
  badSignature[0] = 0;
  assert.throws(
    () => inspectPng(toArrayBuffer(badSignature), ASSET_CONTRACTS.base),
    (error) => error.code === "invalid_png_signature",
  );

  const wrongWidth = Uint8Array.from(source);
  new DataView(wrongWidth.buffer).setUint32(16, 241);
  assert.throws(
    () => inspectPng(wrongWidth.buffer, ASSET_CONTRACTS.base),
    (error) => error.code === "invalid_dimensions",
  );
});

test("previewer stays a local-only modular contributor tool", async () => {
  const [html, landing, sitemap, app, recording] = await Promise.all([
    read("contribute/asset-previewer/index.html").then(String),
    read("index.html").then(String),
    read("sitemap.xml").then(String),
    read("contribute/asset-previewer/js/app.mjs").then(String),
    read("contribute/asset-previewer/js/recording.mjs").then(String),
  ]);
  assert.ok(html.includes('type="module" src="./js/app.mjs"'));
  assert.ok(!html.includes("../../assets/script.js"));
  assert.ok(html.includes("파일은 서버로 전송하거나 저장하지 않습니다"));
  assert.ok(html.includes("SIDEY 웹 클라이언트가 아닙니다"));
  assert.ok(html.includes('id="recording-fallback"'));
  assert.ok(!landing.includes("asset-previewer"));
  assert.ok(sitemap.includes("https://sidey-app.github.io/SIDEY/contribute/asset-previewer/"));
  assert.ok(recording.includes("canvas.captureStream(30)"));
  assert.ok(!`${app}\n${recording}`.match(/getUserMedia|getDisplayMedia|eval\(|new Function/));
});
