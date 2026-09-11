function drawBackground(context, width, height, background) {
  if (background === "dark") {
    context.fillStyle = "#171523";
    context.fillRect(0, 0, width, height);
    return;
  }
  if (background === "checker") {
    const cell = 24;
    for (let y = 0; y < height; y += cell) {
      for (let x = 0; x < width; x += cell) {
        context.fillStyle = (x / cell + y / cell) % 2 === 0 ? "#f7f5ff" : "#ded9ed";
        context.fillRect(x, y, cell, cell);
      }
    }
    return;
  }
  context.fillStyle = "#f7f5ff";
  context.fillRect(0, 0, width, height);
}

function edgeGeometry(edge, width, height, normalizedPosition, inward = 24) {
  const horizontal = edge === "bottom" || edge === "top";
  const tangentLength = horizontal ? width : height;
  const margin = Math.min(100, tangentLength * 0.15);
  const tangent = margin + normalizedPosition * (tangentLength - margin * 2);
  switch (edge) {
    case "top": return { x: width - tangent, y: inward, rotation: Math.PI };
    case "left": return { x: inward, y: height - tangent, rotation: Math.PI / 2 };
    case "right": return { x: width - inward, y: tangent, rotation: -Math.PI / 2 };
    case "bottom":
    default: return { x: tangent, y: height - inward, rotation: 0 };
  }
}

function drawEdge(context, edge, width, height) {
  context.save();
  context.strokeStyle = "rgba(111, 92, 255, 0.5)";
  context.lineWidth = 2;
  context.beginPath();
  if (edge === "top") { context.moveTo(0, 1); context.lineTo(width, 1); }
  else if (edge === "left") { context.moveTo(1, 0); context.lineTo(1, height); }
  else if (edge === "right") { context.moveTo(width - 1, 0); context.lineTo(width - 1, height); }
  else { context.moveTo(0, height - 1); context.lineTo(width, height - 1); }
  context.stroke();
  context.restore();
}

function drawSheetFrame(context, bitmap, frame, cellSize, point, scale, options = {}) {
  if (frame == null) return;
  context.save();
  context.translate(Math.round(point.x), Math.round(point.y));
  context.rotate(point.rotation ?? 0);
  context.scale((options.flip ? -1 : 1) * (options.pulseScale ?? 1), options.pulseScale ?? 1);
  context.globalAlpha = options.alpha ?? 1;
  context.filter = options.grayscale ? "grayscale(1)" : "none";
  context.imageSmoothingEnabled = false;
  const baseline = cellSize === 24 ? 20 : Math.floor(cellSize / 2);
  context.drawImage(
    bitmap,
    frame * cellSize,
    0,
    cellSize,
    cellSize,
    -Math.floor(cellSize / 2) * scale,
    -baseline * scale,
    cellSize * scale,
    cellSize * scale,
  );
  context.restore();
}

function drawZzz(context, point, edge) {
  const offsets = {
    bottom: [26, -64], top: [-26, 64], left: [64, 26], right: [-64, -26],
  };
  const [x, y] = offsets[edge] ?? offsets.bottom;
  context.save();
  context.font = "700 18px ui-rounded, system-ui, sans-serif";
  context.fillStyle = "#f59e0b";
  context.strokeStyle = "rgba(64, 42, 9, 0.8)";
  context.lineWidth = 3;
  context.strokeText("Zzz", point.x + x, point.y + y);
  context.fillText("Zzz", point.x + x, point.y + y);
  context.restore();
}

function drawParticles(context, particles) {
  for (const particle of particles) {
    const life = Math.max(0, 1 - particle.age / particle.lifetime);
    context.save();
    context.globalAlpha = life;
    context.fillStyle = particle.color;
    context.translate(Math.round(particle.x), Math.round(particle.y));
    context.rotate(Math.PI / 4);
    const radius = Math.max(1, Math.round(particle.radius * life));
    context.fillRect(-radius, -radius, radius * 2, radius * 2);
    context.restore();
  }
}

function drawThrowScene(context, view, width, height) {
  const actorPosition = 0.22;
  const targetPosition = 0.78;
  const actor = edgeGeometry(view.edge, width, height, actorPosition, 30);
  const target = edgeGeometry(view.edge, width, height, targetPosition, 30);
  const timeline = view.throwTimeline;
  const actorFrame = timeline.actorFrame ?? view.baseFrame;
  const targetFrame = timeline.targetFrame ?? view.baseFrame;
  drawSheetFrame(context, timeline.actorFrame == null ? view.assets.base : view.assets.throwHit, actorFrame, 24, actor, view.scale, { flip: false });
  drawSheetFrame(context, timeline.targetFrame == null ? view.assets.base : view.assets.throwHit, targetFrame, 24, target, view.scale, { flip: true });

  if (timeline.objectFrame != null) {
    let point = target;
    if (timeline.phase === "flight") {
      const progress = timeline.flightProgress;
      const position = actorPosition + (targetPosition - actorPosition) * progress;
      const arc = 34 + Math.min(96, Math.abs(target.x - actor.x + target.y - actor.y) * 0.18);
      point = edgeGeometry(view.edge, width, height, position, 44 + Math.sin(Math.PI * progress) * arc);
    } else {
      point = edgeGeometry(view.edge, width, height, targetPosition, 48);
    }
    drawSheetFrame(context, view.assets.throwable, timeline.objectFrame, 16, point, view.scale);
  }
}

export function renderPreview(canvas, view) {
  const context = canvas.getContext("2d");
  const { width, height } = canvas;
  context.clearRect(0, 0, width, height);
  context.imageSmoothingEnabled = false;
  drawBackground(context, width, height, view.background);
  drawEdge(context, view.edge, width, height);

  if (view.throwTimeline && view.throwTimeline.phase !== "done") {
    drawThrowScene(context, view, width, height);
  } else {
    const point = edgeGeometry(view.edge, width, height, view.position, 30);
    drawSheetFrame(context, view.assets.base, view.baseFrame, 24, point, view.scale, {
      flip: view.direction < 0,
      pulseScale: view.pulseScale,
      grayscale: view.mode === "offline",
      alpha: view.mode === "offline" ? 0.75 : 1,
    });
    if (view.mode === "doze") drawZzz(context, point, view.edge);
  }
  drawParticles(context, view.particles);
}

export function characterScreenPoint(canvas, edge, position) {
  return edgeGeometry(edge, canvas.width, canvas.height, position, 30);
}
