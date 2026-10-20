import { useEffect, useRef } from "react";
import { featureOpacity, figureGeometry, formOf, settleFusion, stateNames, stepFusion, type FigureGeometry, type FigureState, type Fusion } from "./figureModel";
import { usePrefersReducedMotion } from "./MotionProvider";

// 助手形象 (design system, 助手形象): a flat, single-colour round entity with rounded-square eyes and a thin
// mouth, ringed by a few orbiting particles; while the assistant works the same particles make up a
// ball. Every change of state is the one set of particles fusing or scattering, never a swapped icon.
// Under 减弱动态效果 it draws each state's still frame only.

interface Palette {
  ink: string;
  eye: string;
  error: string;
  accent: string;
}

function readPalette(el: Element): Palette {
  const style = getComputedStyle(el);
  const read = (name: string) => style.getPropertyValue(name).trim();
  return { ink: read("--figure-ink"), eye: read("--figure-eye"), error: read("--figure-error"), accent: read("--accent") };
}

// The particles sit on a sphere (a Fibonacci lattice, so evenly), each with its own arrival delay and arc.
interface Particle {
  x: number;
  y: number;
  z: number;
  delay: number;
  arc: number;
}

function sphere(count: number): Particle[] {
  const golden = Math.PI * (3 - Math.sqrt(5));
  return Array.from({ length: count }, (_, i) => {
    const y = 1 - (2 * (i + 0.5)) / count;
    const ring = Math.sqrt(1 - y * y);
    const angle = golden * i;
    // A fixed pseudo-random spread, so the figure looks the same on every launch.
    const noise = (Math.sin(i * 12.9898) * 43758.5453) % 1;
    return { x: Math.cos(angle) * ring, y, z: Math.sin(angle) * ring, delay: Math.abs(noise) * 0.45, arc: noise * 0.35 };
  });
}

const ease = (t: number) => 1 - (1 - t) ** 3;
const clamp = (v: number) => Math.min(1, Math.max(0, v));

/** How brightly a particle at (x, y, z) lights up in a working state at time t (seconds). */
function glow(state: FigureState, x: number, y: number, z: number, t: number): number {
  switch (state) {
    case "thinking": {
      // A slow light turning over the ball.
      const a = t * 0.9;
      const d = Math.hypot(x - Math.cos(a) * 0.8, y - Math.sin(a * 0.7) * 0.5, z - Math.sin(a) * 0.8);
      return clamp(1 - d / 0.9);
    }
    case "searching":
      return clamp(1 - Math.abs(x - Math.sin(t * 2.2)) / 0.35);
    case "reading":
      return clamp(1 - Math.abs(y - Math.sin(t * 1.8)) / 0.3);
    case "writing": {
      // A bright arc going round the rim.
      const d = Math.abs(Math.atan2(y, x) - (((t * 3) % (2 * Math.PI)) - Math.PI));
      return clamp(1 - Math.min(d, 2 * Math.PI - d) / 0.9) * clamp(1 - Math.abs(z) * 1.4);
    }
    case "running":
      // Horizontal stripes flickering.
      return (Math.sin(y * 18 + t * 9) > 0.55 ? 1 : 0.15) * (0.6 + 0.4 * Math.sin(t * 23));
    default:
      return 0;
  }
}

interface Frame {
  state: FigureState;
  /** Seconds since the figure appeared. */
  t: number;
  /** Seconds since this state began. */
  since: number;
  fusion: number;
  /** Where the eyes look, -1..1 each way. */
  gaze: { x: number; y: number };
  /** 0 open … 1 shut. */
  blink: number;
  still: boolean;
}

function roundedRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.roundRect(x - w / 2, y - h / 2, w, h, Math.min(r, w / 2, h / 2));
}

function draw(ctx: CanvasRenderingContext2D, g: FigureGeometry, particles: Particle[], palette: Palette, f: Frame) {
  const { size, radius: R } = g;
  const c = size / 2;
  ctx.clearRect(0, 0, size, size);
  const { state, t, since, fusion } = f;
  const body = state === "error" ? palette.error : palette.ink;
  const breathing = f.still ? 1 : 1 + 0.015 * Math.sin(t * 2.1);
  // 完成: a light bounce as it lands; 出错: a slight shake, then still.
  const bounce = state === "done" && !f.still ? 1 + 0.07 * Math.exp(-since * 6) * Math.sin(since * 18) : 1;
  const shake = state === "error" && !f.still ? R * 0.08 * Math.exp(-since * 7) * Math.sin(since * 42) : 0;
  const cx = c + shake;
  const cy = c;
  const entity = R * fusion * breathing * bounce;

  // 等你回应: a breathing ring in the accent colour.
  if (state === "waiting" && fusion > 0.5) {
    ctx.strokeStyle = palette.accent;
    ctx.lineWidth = g.halo;
    ctx.globalAlpha = (f.still ? 0.8 : 0.5 + 0.35 * Math.sin(t * 2.4)) * featureOpacity(fusion);
    ctx.beginPath();
    ctx.arc(cx, cy, R + g.halo * 3 + (f.still ? 0 : g.halo * Math.sin(t * 2.4)), 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }

  // The particles: on the turning ball when scattered; drawn in along a slight arc as the entity forms,
  // each at its own time, melting once the growing entity reaches it.
  if (fusion < 1) {
    const spin = t * 0.5;
    const cos = Math.cos(spin);
    const sin = Math.sin(spin);
    for (const p of particles) {
      const x = p.x * cos + p.z * sin;
      const z = -p.x * sin + p.z * cos;
      const y = p.y;
      const travel = ease(clamp((fusion - p.delay) / (1 - p.delay)));
      const r = 1 - travel;
      // The arc: a sideways nudge that peaks halfway in.
      const nudge = p.arc * Math.sin(travel * Math.PI);
      const px = cx + R * (x * r - y * nudge);
      const py = cy + R * (y * r + x * nudge);
      if (Math.hypot(px - cx, py - cy) < entity) continue;
      const depth = (z + 1) / 2;
      const light = formOf(state) === "particles" ? glow(state, x, y, z, t) : 0;
      ctx.globalAlpha = (0.35 + 0.55 * depth) * (1 - fusion * 0.3);
      ctx.fillStyle = fusion > 0 ? body : palette.ink;
      ctx.beginPath();
      ctx.arc(px, py, g.dot(depth), 0, Math.PI * 2);
      ctx.fill();
      if (light > 0) {
        ctx.globalAlpha = light * (1 - fusion) * (0.4 + 0.6 * depth);
        ctx.fillStyle = palette.accent;
        ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }

  // The orbiting particles, at full size only.
  if (g.orbiters) {
    ctx.fillStyle = body;
    for (let i = 0; i < g.orbiters.count; i++) {
      const a = (i / g.orbiters.count) * Math.PI * 2 + t * 0.35 * (i % 2 ? 1 : 0.8);
      const tilt = 0.45;
      const ox = Math.cos(a) * R * 1.2;
      const oy = Math.sin(a) * R * 1.2 * tilt;
      ctx.globalAlpha = 0.35 + 0.3 * ((Math.sin(a) + 1) / 2);
      ctx.beginPath();
      ctx.arc(cx + ox, cy + oy, g.orbiters.radius, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  if (entity <= 0) return;
  // The entity: flat, one colour. While it forms its edge is soft.
  const forming = fusion * (1 - fusion);
  ctx.save();
  if (forming > 0.01) {
    ctx.shadowColor = body;
    ctx.shadowBlur = R * 0.6 * forming * 4;
  }
  ctx.fillStyle = body;
  ctx.beginPath();
  ctx.arc(cx, cy, entity, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  const features = featureOpacity(fusion);
  if (features <= 0) return;
  ctx.globalAlpha = features;
  ctx.fillStyle = palette.eye;
  ctx.strokeStyle = palette.eye;
  const scale = entity / R;
  const look = state === "idle" ? f.gaze : { x: 0, y: 0 };
  const eyeY = cy - R * 0.08 * scale + look.y * R * 0.07;
  const spread = R * 0.34 * scale;
  const big = state === "waiting" ? 1.3 : 1;
  const w = g.eye.width * scale * big;
  const h = g.eye.height * scale * big * (state === "idle" ? 1 - 0.85 * f.blink : 1);
  for (const side of [-1, 1]) {
    const ex = cx + side * spread + look.x * R * 0.1;
    if (state === "done") {
      // ^ ^
      ctx.lineWidth = g.eye.foldLine * scale;
      ctx.lineCap = "round";
      ctx.lineJoin = "round";
      ctx.beginPath();
      ctx.moveTo(ex - w * 0.75, eyeY + h * 0.3);
      ctx.lineTo(ex, eyeY - h * 0.35);
      ctx.lineTo(ex + w * 0.75, eyeY + h * 0.3);
      ctx.stroke();
    } else {
      ctx.save();
      ctx.translate(ex, eyeY);
      // 出错: the inner corners lift, worried.
      if (state === "error") ctx.rotate(side * -0.32);
      roundedRect(ctx, 0, 0, w, h, g.eye.corner * scale * big);
      ctx.fill();
      ctx.restore();
    }
  }

  if (g.mouth) {
    const my = cy + R * 0.3 * scale;
    const half = g.mouth.halfWidth * scale;
    ctx.lineWidth = g.mouth.line * scale;
    ctx.lineCap = "round";
    if (state === "waiting") {
      roundedRect(ctx, cx, my, half * 1.1, half * 0.9, half * 0.3);
      ctx.fill();
    } else {
      // A shallow smile; wider when done; turned down when something failed.
      const curve = state === "done" ? 0.75 : state === "error" ? -0.55 : 0.4;
      ctx.beginPath();
      ctx.moveTo(cx - half, my);
      ctx.quadraticCurveTo(cx, my + half * curve * 1.2, cx + half, my);
      ctx.stroke();
    }
  }
  ctx.globalAlpha = 1;
}

/** The figure at `size` px (48 at the top of the 助手栏, 22 on the card's toggle). */
export function AssistantFigure({ size, state }: { size: number; state: FigureState }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const still = usePrefersReducedMotion();
  const stateRef = useRef(state);
  stateRef.current = state;
  const changed = useRef({ state, at: performance.now() });
  if (changed.current.state !== state) changed.current = { state, at: performance.now() };

  useEffect(() => {
    const el = canvas.current!;
    const ctx = el.getContext("2d")!;
    const g = figureGeometry(size);
    const particles = sphere(g.particles);
    const ratio = window.devicePixelRatio || 1;
    el.width = Math.round(size * ratio);
    el.height = Math.round(size * ratio);
    ctx.scale(ratio, ratio);
    let palette = readPalette(el);
    const scheme = matchMedia("(prefers-color-scheme: dark)");
    const recolor = () => {
      palette = readPalette(el);
      if (still) paint(performance.now());
    };
    scheme.addEventListener("change", recolor);
    const observer = new MutationObserver(recolor);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["style", "data-theme", "class"] });

    let fusion: Fusion = settleFusion(stateRef.current);
    const gaze = { x: 0, y: 0 };
    const pointer = { x: 0, y: 0 };
    const onPointer = (event: PointerEvent) => {
      const box = el.getBoundingClientRect();
      const dx = event.clientX - (box.left + box.width / 2);
      const dy = event.clientY - (box.top + box.height / 2);
      const d = Math.hypot(dx, dy) || 1;
      const reach = Math.min(1, d / 300);
      pointer.x = (dx / d) * reach;
      pointer.y = (dy / d) * reach;
    };
    if (!still) window.addEventListener("pointermove", onPointer);
    let nextBlink = 2.5;
    let last = performance.now();
    const start = last;

    function paint(now: number) {
      const s = stateRef.current;
      const t = (now - start) / 1000;
      const since = (now - changed.current.at) / 1000;
      if (still) {
        fusion = settleFusion(s);
        draw(ctx, g, particles, palette, { state: s, t: 0, since: 10, fusion: fusion.value, gaze: { x: 0, y: 0 }, blink: 0, still: true });
        return;
      }
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      fusion = stepFusion(fusion, formOf(s) === "entity" ? 1 : 0, dt);
      gaze.x += (pointer.x - gaze.x) * Math.min(1, dt * 8);
      gaze.y += (pointer.y - gaze.y) * Math.min(1, dt * 8);
      // An occasional blink: shut and open in about 0.16s.
      if (t > nextBlink + 0.16) nextBlink = t + 2.5 + ((t * 7.3) % 3);
      const blinking = t > nextBlink ? Math.sin(((t - nextBlink) / 0.16) * Math.PI) : 0;
      draw(ctx, g, particles, palette, { state: s, t, since, fusion: fusion.value, gaze, blink: Math.max(0, blinking), still: false });
    }

    let frame = 0;
    const loop = (now: number) => {
      paint(now);
      frame = requestAnimationFrame(loop);
    };
    if (still) paint(performance.now());
    else frame = requestAnimationFrame(loop);
    return () => {
      cancelAnimationFrame(frame);
      window.removeEventListener("pointermove", onPointer);
      scheme.removeEventListener("change", recolor);
      observer.disconnect();
    };
  }, [size, still]);

  // A still figure is drawn again when its state changes.
  useEffect(() => {
    if (!still || !canvas.current) return;
    const el = canvas.current;
    const ctx = el.getContext("2d")!;
    const g = figureGeometry(size);
    draw(ctx, g, sphere(g.particles), readPalette(el), { state, t: 0, since: 10, fusion: settleFusion(state).value, gaze: { x: 0, y: 0 }, blink: 0, still: true });
  }, [state]);

  return (
    <canvas
      ref={canvas}
      className="assistant-figure"
      role="img"
      aria-label={`助手形象：${stateNames[state]}`}
      data-state={state}
      style={{ width: size, height: size }}
    />
  );
}
