import { animate } from "motion/react";
import { useLayoutEffect, useRef } from "react";
import { noteSwitch } from "./motion";
import { useMotion, usePrefersReducedMotion } from "./MotionProvider";

/** Where each group's pill was as it left its row, for the pill that takes over shortly after. */
const left = new Map<string, { rect: DOMRect; row: HTMLElement | null; className: string; at: number }>();
/** How long a pill that left waits for the next one: opening a note may take a few renders to settle. */
const handover = 250;

/** The old pill fading out where it was, so a far jump reads as one selection leaving and another arriving. */
function fadeOutAt(row: HTMLElement | null, className: string, duration: number) {
  if (!row?.isConnected) return;
  const ghost = Object.assign(document.createElement("span"), { className });
  ghost.setAttribute("aria-hidden", "true");
  row.prepend(ghost);
  void animate(ghost, { opacity: [1, 0] }, { duration, ease: "easeOut" }).then(() => ghost.remove());
}

/**
 * 选中底板: rendered inside the selected row. When the selection moves up to `noteSwitch.farRows` rows,
 * the pill slides from the old row to the new one with 滑移; further, the old one fades out and the new one
 * fades in, slightly growing. It sits in its row, so when the row moves (a folder above it opens) it moves
 * with it. A selection that moves again mid-way starts from wherever the pill is drawn.
 */
export function SelectionPill({ group }: { group: "side" | "list" | "space" }) {
  const { slide, amplitude } = useMotion();
  const reduced = usePrefersReducedMotion();
  const ref = useRef<HTMLSpanElement>(null);
  const settings = useRef({ slide, amplitude, reduced });
  settings.current = { slide, amplitude, reduced };

  useLayoutEffect(() => {
    const pill = ref.current;
    if (!pill) return;
    const gone = left.get(group);
    left.delete(group);
    const from = gone && performance.now() - gone.at < handover ? gone : undefined;
    const to = pill.getBoundingClientRect();
    const { slide, amplitude, reduced } = settings.current;
    let running: { stop: () => void } | undefined;
    if (from && to.height > 0) {
      const dx = from.rect.left - to.left;
      const dy = from.rect.top - to.top;
      if (Math.abs(dy) > noteSwitch.farRows * to.height) {
        fadeOutAt(from.row, from.className, noteSwitch.fadeOut);
        const grow = reduced ? {} : { scale: [1 - noteSwitch.scale * amplitude, 1] };
        // Drawn from its first frame as the animation starts, never for a frame at full strength.
        pill.style.opacity = "0";
        running = animate(pill, { opacity: [0, 1], ...grow }, { duration: noteSwitch.fadeIn, ease: "easeOut" });
      } else if (dx || dy || from.rect.width !== to.width || from.rect.height !== to.height) {
        pill.style.transformOrigin = "0 0";
        const start = `translate(${dx}px, ${dy}px) scale(${from.rect.width / to.width}, ${from.rect.height / to.height})`;
        // Set at once, so the first frame draws it where it was; the animation itself starts a frame later.
        pill.style.transform = start;
        running = animate(pill, { transform: [start, "translate(0px, 0px) scale(1, 1)"] }, slide);
      }
    }
    return () => {
      // Measured before React takes the pill out, so the next one starts where this one is drawn.
      left.set(group, { rect: pill.getBoundingClientRect(), row: pill.parentElement, className: pill.className, at: performance.now() });
      running?.stop();
    };
  }, [group]);

  return <span ref={ref} className={`pill ${group}`} data-testid="selection-pill" aria-hidden />;
}
