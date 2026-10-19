import { getValueTransition } from "motion";
import { describe, expect, it } from "vitest";
import { motionPresets, type MotionIntensity } from "../../src/renderer/src/motion";

// Expected values are the design system's tables (docs/design-system.md, 动效), not recomputed here.
const springs: Record<MotionIntensity, Record<"pop" | "slide" | "expand" | "emerge" | "focus", [number, number]>> = {
  strong: { pop: [0.19, 0.32], slide: [0.32, 0.18], expand: [0.42, 0.57], emerge: [0.55, 0.68], focus: [0.46, 0.12] },
  standard: { pop: [0.18, 0.28], slide: [0.3, 0.16], expand: [0.32, 0.22], emerge: [0.42, 0.26], focus: [0.42, 0.08] },
  light: { pop: [0.15, 0.1], slide: [0.26, 0.06], expand: [0.27, 0.08], emerge: [0.36, 0.09], focus: [0.36, 0.03] },
};

describe("动效预设", () => {
  for (const [intensity, table] of Object.entries(springs) as [MotionIntensity, (typeof springs)["strong"]][]) {
    it(`轻弹、滑移、展开、浮现 and 专注 at ${intensity}`, () => {
      const presets = motionPresets(intensity);
      for (const [name, [visualDuration, bounce]] of Object.entries(table)) {
        expect(presets[name as keyof typeof table], name).toMatchObject({ type: "spring", visualDuration, bounce });
      }
    });
  }

  it("blurs on its own curve, never on a spring, so a bounce cannot turn the blur negative", () => {
    const blur = { strong: 0.36, standard: 0.28, light: 0.24 };
    for (const [intensity, duration] of Object.entries(blur) as [MotionIntensity, number][]) {
      const presets = motionPresets(intensity);
      for (const name of ["pop", "slide", "expand", "emerge", "focus"] as const) {
        expect(getValueTransition(presets[name], "filter"), `${intensity} ${name}`).toEqual({ duration, ease: [0.2, 0.8, 0.2, 1] });
      }
    }
  });

  it("scales travel distances by 2 at 强 and 0.6 at 轻", () => {
    expect(motionPresets("strong").amplitude).toBe(2);
    expect(motionPresets("standard").amplitude).toBe(1);
    expect(motionPresets("light").amplitude).toBe(0.6);
  });

  it("with reduced motion keeps only opacity changes: nothing moves, scales or blurs", () => {
    const presets = motionPresets("strong", { reduced: true });
    for (const name of ["pop", "slide", "expand", "emerge", "focus"] as const) {
      for (const key of ["x", "y", "scale", "scaleX", "rotate", "width", "height", "filter", "layout"]) {
        expect(getValueTransition(presets[name], key), `${name} ${key}`).toMatchObject({ type: false });
      }
      const fade = getValueTransition(presets[name], "opacity");
      expect(fade.type, name).not.toBe("spring");
      expect(fade.duration, name).toBeGreaterThan(0);
    }
  });
});
