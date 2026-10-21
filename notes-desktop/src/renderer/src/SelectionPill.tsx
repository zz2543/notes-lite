import { animate } from "motion/react";
import { useLayoutEffect, useRef } from "react";
import { noteSwitch } from "./motion";
import { useMotion, usePrefersReducedMotion } from "./MotionProvider";

/** The row each group's pill left, for the pill that takes over shortly after. */
const left = new Map<string, { row: HTMLElement | null; className: string; at: number }>();
/** How long a pill that left waits for the next one: opening a note may take a few renders to settle. */
const handover = 250;

/** The old pill fading out where it was, as the new one arrives. */
function fadeOutAt(row: HTMLElement | null, className: string, duration: number) {
  if (!row?.isConnected) return;
  const ghost = Object.assign(document.createElement("span"), { className });
  ghost.setAttribute("aria-hidden", "true");
  row.prepend(ghost);
  void animate(ghost, { opacity: [1, 0] }, { duration, ease: "easeOut" }).then(() => ghost.remove());
}

/**
 * 选中底板: rendered inside the selected row. When the selection moves, near or far, the old pill fades
 * out where it was while the new one fades in on its row, growing a touch (2026-10-22 用户反馈: like the
 * reference video, a crossfade rather than a slide). It sits in its row, so when the row moves (a folder
 * above it opens) it moves with it.
 */
export function SelectionPill({ group }: { group: "side" | "list" | "space" }) {
  const { amplitude } = useMotion();
  const reduced = usePrefersReducedMotion();
  const ref = useRef<HTMLSpanElement>(null);
  const settings = useRef({ amplitude, reduced });
  settings.current = { amplitude, reduced };

  useLayoutEffect(() => {
    const pill = ref.current;
    if (!pill) return;
    const gone = left.get(group);
    left.delete(group);
    const from = gone && performance.now() - gone.at < handover ? gone : undefined;
    const { amplitude, reduced } = settings.current;
    let running: { stop: () => void } | undefined;
    if (from && from.row !== pill.parentElement) {
      fadeOutAt(from.row, from.className, noteSwitch.fadeOut);
      const grow = reduced ? {} : { scale: [1 - noteSwitch.scale * amplitude, 1] };
      // Drawn from its first frame as the animation starts, never for a frame at full strength.
      pill.style.opacity = "0";
      running = animate(pill, { opacity: [0, 1], ...grow }, { duration: noteSwitch.fadeIn, ease: "easeOut" });
    }
    return () => {
      left.set(group, { row: pill.parentElement, className: pill.className, at: performance.now() });
      running?.stop();
    };
  }, [group]);

  return <span ref={ref} className={`pill ${group}`} data-testid="selection-pill" aria-hidden />;
}

/**
 * 选中底板 in the folder tree (2026-10-22 用户反馈, from the reference video): every row keeps a short white
 * tile under its icon; the chosen row's tile stretches out to the row's end on 滑移 while the one left
 * shrinks back to its icon, both at once.
 */
export function RowTile({ on }: { on: boolean }) {
  return <span className={`pill side tile ${on ? "on" : ""}`} data-testid={on ? "selection-pill" : undefined} aria-hidden />;
}
