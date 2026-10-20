import { describe, expect, it } from "vitest";
import { featureOpacity, figureGeometry, figureStates, formOf, settleFusion, stepFusion, type FigureState } from "../../src/renderer/src/figureModel";

// 助手形象. Expected values are the design system's (docs/design-system.md, 助手形象) and the assistant
// spec's state table, not recomputed here.

describe("助手形象 states", () => {
  it("has the nine states: the entity while idle, done, waiting or failed; a particle ball while working", () => {
    const forms = Object.fromEntries(figureStates.map((state) => [state, formOf(state)]));
    expect(forms).toEqual({
      idle: "entity",
      thinking: "particles",
      searching: "particles",
      reading: "particles",
      writing: "particles",
      running: "particles",
      done: "entity",
      waiting: "entity",
      error: "entity",
    } satisfies Record<FigureState, string>);
  });
});

describe("粒子 ↔ 实体", () => {
  // Fusion runs from 0 (all particles) to 1 (the entity).
  const run = (from: number, to: number, seconds: number) => {
    let state = { value: from, velocity: 0 };
    const path: number[] = [];
    for (let t = 0; t < seconds; t += 1 / 120) {
      state = stepFusion(state, to, 1 / 120);
      path.push(state.value);
    }
    return path;
  };

  it("fuses on a critically damped spring: about 0.8s, never past the end", () => {
    const path = run(0, 1, 2);
    expect(Math.max(...path)).toBeLessThanOrEqual(1);
    // ~0.8s: nine tenths of the way there by then, and still a little short at half that.
    expect(path[Math.round(0.85 * 120)]!).toBeGreaterThan(0.9);
    expect(path[Math.round(0.4 * 120)]!).toBeLessThan(0.75);
    expect(path.at(-1)!).toBeCloseTo(1, 2);
  });

  it("scatters the same way back, never below nothing", () => {
    const path = run(1, 0, 2);
    expect(Math.min(...path)).toBeGreaterThanOrEqual(0);
    expect(path.at(-1)!).toBeCloseTo(0, 2);
  });

  it("settles at once to a state's still frame (减弱动态效果)", () => {
    expect(settleFusion("thinking")).toEqual({ value: 0, velocity: 0 });
    expect(settleFusion("waiting")).toEqual({ value: 1, velocity: 0 });
  });

  it("brings in the eyes and mouth only once fusion is 72% done", () => {
    expect(featureOpacity(0)).toBe(0);
    expect(featureOpacity(0.72)).toBe(0);
    expect(featureOpacity(0.86)).toBeCloseTo(0.5, 5);
    expect(featureOpacity(1)).toBe(1);
  });
});

describe("助手形象 sizes", () => {
  it("at 48px, the top of the assistant column: the full face and five orbiting particles", () => {
    const g = figureGeometry(48);
    expect(g.radius).toBeCloseTo(17.28, 5); // 36%
    expect(g.eye.width).toBeCloseTo(3.456, 5); // 20% of the radius
    expect(g.eye.height).toBeCloseTo(4.6656, 5); // 27%
    expect(g.eye.corner).toBeCloseTo(1.31328, 5); // 38% of the short side
    expect(g.mouth).toEqual({ halfWidth: expect.closeTo(2.592, 5), line: expect.closeTo(1.0368, 5) });
    expect(g.orbiters).toEqual({ count: 5, radius: expect.closeTo(0.528, 5) });
    expect(g.particles).toBe(150);
    expect(g.dot(0)).toBeCloseTo(0.42, 5);
    expect(g.dot(1)).toBeCloseTo(1.14, 5);
    expect(g.halo).toBeCloseTo(0.672, 5);
  });

  it("at 22px, the toggle on the card: a bigger body, eyes only, no orbiting particles", () => {
    const g = figureGeometry(22);
    expect(g.radius).toBeCloseTo(8.8, 5); // 40% below 24px
    expect(g.mouth).toBeNull();
    expect(g.orbiters).toBeNull();
  });
});
