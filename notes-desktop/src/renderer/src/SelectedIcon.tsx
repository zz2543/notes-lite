import type { Icon } from "@phosphor-icons/react";
import { icon } from "./tokens";

/**
 * An icon that turns from outline to fill (and may change shape, a folder opening) when its row is chosen:
 * both are drawn in the same place and cross-fade, rather than one replacing the other at once (切换笔记,
 * 2026-10-21).
 */
export function SelectedIcon({ off: Off, on: On = Off, selected }: { off: Icon; on?: Icon; selected: boolean }) {
  return (
    <span className="selected-icon" data-selected={selected} aria-hidden>
      <Off size={icon.regular} weight="regular" className="off" />
      <On size={icon.regular} weight="fill" className="on" />
    </span>
  );
}
