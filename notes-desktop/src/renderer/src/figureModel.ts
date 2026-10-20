// 助手形象: what the figure is in each state and how big each part is. The values are the design
// system's (助手形象); AssistantFigure.tsx draws them.

/** 待命, 思考, 搜索, 读取, 写入, 运行命令, 完成, 等你回应, 出错. */
export type FigureState = "idle" | "thinking" | "searching" | "reading" | "writing" | "running" | "done" | "waiting" | "error";
export type FigureForm = "entity" | "particles";

export const figureStates: readonly FigureState[] = ["idle", "thinking", "searching", "reading", "writing", "running", "done", "waiting", "error"];

/** How the figure says its state, for assistive technology. */
export const stateNames: Record<FigureState, string> = {
  idle: "待命",
  thinking: "思考",
  searching: "搜索",
  reading: "读取",
  writing: "写入",
  running: "运行命令",
  done: "完成",
  waiting: "等你回应",
  error: "出错",
};

/** The entity while it waits, has finished, waits on you or failed; a particle ball while it works. */
export const formOf = (state: FigureState): FigureForm =>
  state === "idle" || state === "done" || state === "waiting" || state === "error" ? "entity" : "particles";

// 粒子 ↔ 实体: a critically damped spring (stiffness 26, damping 10.2; about 0.8s, no bounce).
const stiffness = 26;
const damping = 10.2;

/** Fusion: 0 is the particle ball, 1 the entity. */
export interface Fusion {
  value: number;
  velocity: number;
}

/** One frame of fusion towards `target` (0 or 1). */
export function stepFusion({ value, velocity }: Fusion, target: number, dt: number): Fusion {
  // Semi-implicit Euler in small steps stays stable whatever the frame time.
  const steps = Math.max(1, Math.ceil(dt / (1 / 240)));
  const h = dt / steps;
  for (let i = 0; i < steps; i++) {
    velocity += (stiffness * (target - value) - damping * velocity) * h;
    value += velocity * h;
  }
  // Numerically the spring could creep a hair past its end; the figure never does.
  return { value: Math.min(1, Math.max(0, value)), velocity };
}

/** The still frame of a state, under 减弱动态效果 or when the figure first appears. */
export const settleFusion = (state: FigureState): Fusion => ({ value: formOf(state) === "entity" ? 1 : 0, velocity: 0 });

/** The eyes and mouth fade in only once fusion is 72% done. */
export const featureOpacity = (fusion: number) => Math.min(1, Math.max(0, (fusion - 0.72) / 0.28));

export interface FigureGeometry {
  size: number;
  /** The entity, a circle. */
  radius: number;
  /** Rounded-square eyes. */
  eye: { width: number; height: number; corner: number; foldLine: number };
  /** A thin arc; none at the toggle's size. */
  mouth: { halfWidth: number; line: number } | null;
  /** Orbiting particles; only at full size. */
  orbiters: { count: number; radius: number } | null;
  /** Particles on the sphere. */
  particles: number;
  /** A particle's dot radius at a depth from 0 (back) to 1 (front). */
  dot(depth: number): number;
  /** Line width of the 等你回应 ring. */
  halo: number;
}

/** Below this canvas size the figure is the card's toggle: a bigger body, eyes only. */
const small = 24;

export function figureGeometry(size: number): FigureGeometry {
  const radius = size * (size < small ? 0.4 : 0.36);
  const eyeWidth = radius * 0.2;
  const eyeHeight = radius * 0.27;
  return {
    size,
    radius,
    eye: { width: eyeWidth, height: eyeHeight, corner: Math.min(eyeWidth, eyeHeight) * 0.38, foldLine: eyeWidth * 0.42 },
    mouth: size < small ? null : { halfWidth: radius * 0.15, line: radius * 0.06 },
    orbiters: size < small ? null : { count: 5, radius: size * 0.011 },
    particles: 150,
    dot: (depth) => ((0.35 + 0.6 * depth) * size) / 40,
    halo: size * 0.014,
  };
}
