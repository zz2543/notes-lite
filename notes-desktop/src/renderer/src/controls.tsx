import { motion } from "motion/react";
import { useId, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import { LiquidPill, useVisualEffect } from "./effects";
import { useMotion } from "./MotionProvider";

// The settings panel's control library. Every value is set by something you can see — segments,
// swatches, previews, switches, sliders with their value — never by typing a number.

export interface Choice<T extends string> {
  value: T;
  label: string;
}

/** Arrow keys move the choice within a radio group, as in any system radio group. */
function useRadioKeys<T extends string>(values: readonly T[], value: T, onChange: (value: T) => void) {
  const group = useRef<HTMLDivElement>(null);
  const onKeyDown = (event: KeyboardEvent) => {
    const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[event.key];
    if (!step) return;
    event.preventDefault();
    const next = values[(values.indexOf(value) + step + values.length) % values.length]!;
    onChange(next);
    requestAnimationFrame(() => group.current?.querySelector<HTMLElement>("[aria-checked=true]")?.focus());
  };
  return { ref: group, onKeyDown };
}

const radio = (on: boolean) => ({ role: "radio", "aria-checked": on, tabIndex: on ? 0 : -1 }) as const;

/** 分段控件: a few mutually exclusive choices; the selected segment's pill slides to the new one (滑移). */
export function Segmented<T extends string>({ label, choices, value, onChange }: { label: string; choices: readonly Choice<T>[]; value: T; onChange(value: T): void }) {
  const { slide } = useMotion();
  const pill = useId();
  const keys = useRadioKeys(choices.map((c) => c.value), value, onChange);
  // 界面特效 › 液态滑块: the pill is one drop of liquid under the group instead, following the choice.
  const liquid = useVisualEffect("effectGooey");
  const [group, setGroup] = useState<HTMLDivElement | null>(null);
  const [chosen, setChosen] = useState<HTMLButtonElement | null>(null);
  const setRef = (el: HTMLDivElement | null) => {
    keys.ref.current = el;
    setGroup(el);
  };
  return (
    <div className={liquid ? "segmented liquid" : "segmented"} role="radiogroup" aria-label={label} {...keys} ref={setRef}>
      {liquid && <LiquidPill container={group} target={chosen} fill="--list-pill" shadow="--pill-shadow" className="segment-liquid" />}
      {choices.map((choice) => (
        <button key={choice.value} {...radio(choice.value === value)} ref={choice.value === value ? setChosen : undefined} onClick={() => onChange(choice.value)}>
          {!liquid && choice.value === value && <motion.span layoutId={pill} transition={slide} className="segment-pill" aria-hidden />}
          <span className="label">{choice.label}</span>
        </button>
      ))}
    </div>
  );
}

export interface Swatch<T extends string> extends Choice<T> {
  /** Any CSS colour, usually a design-system variable. */
  color: string;
}

/** 色板: colour choices as dots; the chosen one is ringed. */
export function Swatches<T extends string>({ label, choices, value, onChange }: { label: string; choices: readonly Swatch<T>[]; value: T; onChange(value: T): void }) {
  const keys = useRadioKeys(choices.map((c) => c.value), value, onChange);
  return (
    <div className="swatches" role="radiogroup" aria-label={label} {...keys}>
      {choices.map((choice) => (
        <button
          key={choice.value}
          className="swatch"
          {...radio(choice.value === value)}
          aria-label={choice.label}
          title={choice.label}
          style={{ background: choice.color }}
          onClick={() => onChange(choice.value)}
        />
      ))}
    </div>
  );
}

export interface PreviewChoice<T extends string> extends Choice<T> {
  preview: ReactNode;
}

/** 带预览的选项: each choice shows what it looks like above its name. */
export function PreviewChoices<T extends string>({ label, choices, value, onChange }: { label: string; choices: readonly PreviewChoice<T>[]; value: T; onChange(value: T): void }) {
  const keys = useRadioKeys(choices.map((c) => c.value), value, onChange);
  return (
    <div className="preview-choices" role="radiogroup" aria-label={label} {...keys}>
      {choices.map((choice) => (
        <button key={choice.value} className="preview-choice" {...radio(choice.value === value)} aria-label={choice.label} onClick={() => onChange(choice.value)}>
          <span className="preview" aria-hidden>
            {choice.preview}
          </span>
          <span className="label">{choice.label}</span>
        </button>
      ))}
    </div>
  );
}

/** 开关: on or off; the knob slides with 轻弹. */
export function Switch({ label, on, onChange }: { label: string; on: boolean; onChange(on: boolean): void }) {
  const { pop } = useMotion();
  return (
    <button className="switch" role="switch" aria-checked={on} aria-label={label} onClick={() => onChange(!on)}>
      <motion.span className="knob" layout transition={pop} aria-hidden />
    </button>
  );
}

/** 滑块: a value in a range, shown live beside the track as it moves. */
export function Slider({
  label,
  value,
  min,
  max,
  step,
  format = String,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  format?(value: number): string;
  onChange(value: number): void;
}) {
  return (
    <div className="slider">
      <input
        type="range"
        aria-label={label}
        aria-valuetext={format(value)}
        min={min}
        max={max}
        step={step}
        value={value}
        style={{ "--fill": `${((value - min) / (max - min)) * 100}%` } as React.CSSProperties}
        onChange={(event) => onChange(Number(event.target.value))}
      />
      <output className="slider-value">{format(value)}</output>
    </div>
  );
}
