export const MAX_PARTICLES = 160;

function randomSequence(seed) {
  let value = seed >>> 0 || 1;
  return () => {
    value = (1664525 * value + 1013904223) >>> 0;
    return value / 0x100000000;
  };
}

function randomBetween(random, minimum, maximum) {
  return minimum + random() * Math.max(0, maximum - minimum);
}

export function spawnParticles(current, options) {
  const particles = current.slice(-MAX_PARTICLES);
  const available = Math.max(0, MAX_PARTICLES - particles.length);
  const count = Math.min(Math.max(0, options.count ?? 0), available);
  const random = randomSequence(options.seed ?? 1);
  const palette = options.palette ?? ["#78c2ad", "#a887d6", "#f5ba38"];
  const minimumSpeed = options.minimumSpeed ?? 22;
  const maximumSpeed = options.maximumSpeed ?? 74;
  const minimumLifetime = options.minimumLifetime ?? 0.55;
  const maximumLifetime = options.maximumLifetime ?? 1;
  const minimumRadius = options.minimumRadius ?? 2;
  const maximumRadius = options.maximumRadius ?? 3;
  for (let index = 0; index < count; index += 1) {
    const angle = random() * Math.PI * 2;
    const speed = randomBetween(random, minimumSpeed, maximumSpeed);
    particles.push({
      x: options.x,
      y: options.y,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed,
      age: 0,
      lifetime: randomBetween(random, minimumLifetime, maximumLifetime),
      radius: randomBetween(random, minimumRadius, maximumRadius),
      color: palette[Math.floor(random() * palette.length) % palette.length],
    });
  }
  return particles;
}

export function stepParticles(particles, deltaSeconds) {
  return particles
    .map((particle) => ({
      ...particle,
      x: particle.x + particle.vx * deltaSeconds,
      y: particle.y + particle.vy * deltaSeconds,
      vy: particle.vy + 12 * deltaSeconds,
      age: particle.age + deltaSeconds,
    }))
    .filter((particle) => particle.age < particle.lifetime)
    .slice(-MAX_PARTICLES);
}
