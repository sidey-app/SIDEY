export const FIXED_STEP_SECONDS = 1 / 30;
export const DEMO_DURATION_SECONDS = 20;

const clamp = (value, minimum, maximum) => Math.min(maximum, Math.max(minimum, value));

export function frameForMode(mode, elapsedSeconds) {
  const elapsed = Math.max(0, elapsedSeconds);
  switch (mode) {
    case "walk":
      return 2 + Math.floor(elapsed / 0.12) % 4;
    case "doze":
      return 6 + Math.floor(elapsed / 0.5) % 2;
    case "offline":
      return 8 + Math.floor(elapsed / 0.65) % 2;
    case "idle":
    default:
      return Math.floor(elapsed / 0.6) % 2;
  }
}

export function createSimulationState(position = 0.5) {
  return {
    position: clamp(position, 0, 1),
    direction: 1,
    actionElapsed: 0,
  };
}

export function stepSimulation(state, mode, requestedDirection = state.direction) {
  let direction = requestedDirection < 0 ? -1 : 1;
  let position = state.position;
  if (mode === "walk") {
    position += direction * 0.11 * FIXED_STEP_SECONDS;
    if (position >= 0.88) {
      position = 0.88;
      direction = -1;
    } else if (position <= 0.12) {
      position = 0.12;
      direction = 1;
    }
  }
  return {
    position,
    direction,
    actionElapsed: state.actionElapsed + FIXED_STEP_SECONDS,
  };
}

export function computeFlightDuration(distancePixels) {
  return clamp(0.35 + Math.max(0, distancePixels) / 1600, 0.35, 0.95);
}

export function throwTimelineAt(elapsedSeconds, distancePixels) {
  const elapsed = Math.max(0, elapsedSeconds);
  const releaseAt = 0.2;
  const flightDuration = computeFlightDuration(distancePixels);
  const impactAt = releaseAt + flightDuration;
  const impactElapsed = elapsed - impactAt;
  const actorFrame = elapsed < 0.4 ? Math.min(3, Math.floor(elapsed / 0.1)) : null;

  if (elapsed < releaseAt) {
    return { phase: "throw", actorFrame, targetFrame: null, objectFrame: null, flightProgress: 0, impactElapsed: null };
  }
  if (elapsed < impactAt) {
    return {
      phase: "flight",
      actorFrame,
      targetFrame: null,
      objectFrame: Math.floor((elapsed - releaseAt) / 0.083) % 8,
      flightProgress: clamp((elapsed - releaseAt) / flightDuration, 0, 1),
      impactElapsed: null,
    };
  }
  if (impactElapsed < 0.44) {
    return {
      phase: "impact",
      actorFrame,
      targetFrame: 4 + Math.min(3, Math.floor(impactElapsed / 0.11)),
      objectFrame: impactElapsed < 0.24 ? 8 + Math.min(3, Math.floor(impactElapsed / 0.06)) : null,
      flightProgress: 1,
      impactElapsed,
    };
  }
  return { phase: "done", actorFrame: null, targetFrame: null, objectFrame: null, flightProgress: 1, impactElapsed };
}

export function pulseScaleAt(elapsedSeconds) {
  if (elapsedSeconds == null || elapsedSeconds < 0) return 1;
  if (elapsedSeconds <= 0.2) return 1 + 6 * (elapsedSeconds / 0.2);
  if (elapsedSeconds <= 0.8) return 7 - 6 * ((elapsedSeconds - 0.2) / 0.6);
  return 1;
}

export function demoStateAt(elapsedSeconds) {
  const elapsed = clamp(elapsedSeconds, 0, DEMO_DURATION_SECONDS);
  if (elapsed < 2) return { mode: "idle", direction: 1, phase: "idle" };
  if (elapsed < 5) return { mode: "walk", direction: 1, phase: "walk-forward" };
  if (elapsed < 8) return { mode: "walk", direction: -1, phase: "walk-backward" };
  if (elapsed < 10.5) return { mode: "doze", direction: -1, phase: "doze" };
  if (elapsed < 13) return { mode: "offline", direction: -1, phase: "offline" };
  if (elapsed < 15.5) return { mode: "idle", direction: 1, phase: "pulse", pulseElapsed: elapsed - 13 };
  return { mode: "idle", direction: 1, phase: "throw", throwElapsed: elapsed - 15.5 };
}
