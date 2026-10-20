// The whole motion vocabulary from the design system (动效): four spring presets, the 专注 spring and
// the three intensities. Components take their transitions from here and never write their own.
import type { Transition } from "motion/react";
import { defaultPreferences, type MotionIntensity } from "../../shared/preferences";

export type { MotionIntensity };
export const defaultIntensity: MotionIntensity = defaultPreferences.motion;

export interface MotionPresets {
  /** 轻弹: hover, press, switches, an icon turning from outline to fill. */
  pop: Transition;
  /** 滑移: the selection pill, list changes and reordering, switching notes, column widths, the caret. */
  slide: Transition;
  /** 展开: folders opening, caret rotation, menus, the search field. */
  expand: Transition;
  /** 浮现: dialogs, the settings panel, space page cards. */
  emerge: Transition;
  /** 专注: the note card filling the window; restrained even at 强. */
  focus: Transition;
  /** Travel distances and scale-ins are multiplied by this: 强 2, 标准 1, 轻 0.6. */
  amplitude: number;
  /** 浮层进入 / 退出 (the settings panel, dialogs): motion targets, entering with 浮现. */
  overlay: OverlayMotion;
}

export interface OverlayMotion {
  initial: { opacity: number; scale: number; y: number; filter: string };
  animate: { opacity: number; scale: number; y: number; filter: string };
  exit: { opacity: number; scale: number; filter: string; transition: Transition };
}

// 幅度 at 标准 (the design system lists 强, twice these): an overlay rises 10px from scale 0.94 out of a
// 5px blur, and leaves in 0.16s to scale 0.985 and a 3px blur.
const overlayTravel = { scale: 0.06, rise: 10, blur: 5, exitScale: 0.015, exitBlur: 3, exitDuration: 0.16 };

type Spring = { visualDuration: number; bounce: number };

// The 标准 values; the other intensities are derived from them.
const standard = {
  pop: { visualDuration: 0.18, bounce: 0.28 },
  slide: { visualDuration: 0.3, bounce: 0.16 },
  expand: { visualDuration: 0.32, bounce: 0.22 },
  emerge: { visualDuration: 0.42, bounce: 0.26 },
} satisfies Record<string, Spring>;
const focus: Spring = { visualDuration: 0.42, bounce: 0.08 };

const factors: Record<MotionIntensity, { bounce: number; duration: number; amplitude: number }> = {
  light: { bounce: 0.35, duration: 0.85, amplitude: 0.6 },
  standard: { bounce: 1, duration: 1, amplitude: 1 },
  strong: { bounce: 2.6, duration: 1.3, amplitude: 2 },
};

// 轻弹 and 滑移 run all the time, so intensity barely changes them.
const frequent = { bounce: 1.15, duration: 1.05 };
const maxBounce = 0.72;
const focusLimits = { bounce: 0.12, duration: 1.1 };
// Blur never rides a spring: a bounce would swing it below zero. It eases on its own, whichever preset
// carries it.
const blur = { duration: 0.28, ease: [0.2, 0.8, 0.2, 1] as [number, number, number, number] };

// The design system states every value to two decimals.
const round = (value: number) => Math.round(value * 100 + 1e-9) / 100;

function overlayMotion(amplitude: number, reduced: boolean): OverlayMotion {
  const t = overlayTravel;
  const exitDuration = t.exitDuration;
  return {
    initial: { opacity: 0, scale: round(1 - t.scale * amplitude), y: round(t.rise * amplitude), filter: `blur(${round(t.blur * amplitude)}px)` },
    animate: { opacity: 1, scale: 1, y: 0, filter: "blur(0px)" },
    exit: {
      opacity: 0,
      scale: round(1 - t.exitScale * amplitude),
      filter: `blur(${round(t.exitBlur * amplitude)}px)`,
      transition: reduced ? { default: { type: false }, opacity: { duration: exitDuration } } : { duration: exitDuration, ease: "easeIn" },
    },
  };
}

/**
 * `reduced` follows the system's 减弱动态效果: every value then changes at once except opacity, which
 * still fades (without a bounce) over the preset's duration.
 */
export function motionPresets(intensity: MotionIntensity = defaultIntensity, { reduced = false } = {}): MotionPresets {
  const factor = factors[intensity];
  const filter = { duration: round(blur.duration * factor.duration), ease: blur.ease };
  const spring = ({ visualDuration, bounce }: Spring, scale: { bounce: number; duration: number }, bounceLimit = maxBounce): Transition => {
    const duration = round(visualDuration * scale.duration);
    if (reduced) return { default: { type: false }, opacity: { duration, ease: "easeOut" } };
    return { type: "spring", visualDuration: duration, bounce: round(Math.min(bounceLimit, bounce * scale.bounce)), filter };
  };
  const capped = { bounce: Math.min(factor.bounce, frequent.bounce), duration: Math.min(factor.duration, frequent.duration) };
  return {
    pop: spring(standard.pop, capped),
    slide: spring(standard.slide, capped),
    expand: spring(standard.expand, factor),
    emerge: spring(standard.emerge, factor),
    focus: spring(focus, { bounce: factor.bounce, duration: Math.min(factor.duration, focusLimits.duration) }, focusLimits.bounce),
    amplitude: factor.amplitude,
    overlay: overlayMotion(factor.amplitude, reduced),
  };
}
