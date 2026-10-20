import { ArrowsIn, ArrowsOut } from "@phosphor-icons/react";
import { useEffect, useState, type RefObject } from "react";
import { icon } from "./tokens";

// 专注模式: a layout state of the window, not another editor. The card keeps its editor (text, caret,
// selection, undo, scroll) while the navigation and the list slide away under it.

const mac = /Mac/.test(navigator.platform);
export const focusShortcut = mac ? "⌘⇧F" : "Ctrl+Shift+F";

const isFocusShortcut = (event: KeyboardEvent) =>
  event.code === "KeyF" && event.shiftKey && !event.altKey && (mac ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey);

/**
 * Whether the window is in 专注模式. ⌘⇧F / Ctrl+Shift+F switches it; Esc, typed in the card or with
 * nothing focused, leaves it. Esc is taken before the editor sees it, so a selection stays as it is.
 */
export function useFocusMode(card: RefObject<HTMLElement | null>): [boolean, (on: boolean) => void] {
  const [focused, setFocused] = useState(false);
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.isComposing) return;
      if (isFocusShortcut(event)) {
        event.preventDefault();
        setFocused((now) => !now);
        return;
      }
      if (event.key !== "Escape" || event.defaultPrevented || !focused) return;
      const target = event.target;
      if (target !== document.body && !(target instanceof Node && card.current?.contains(target))) return;
      event.preventDefault();
      event.stopPropagation();
      setFocused(false);
    };
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, [focused]);
  return [focused, setFocused];
}

/** The card's button into 专注模式, and, low-key at the same place, out of it. */
export function FocusToggle({ focused, onChange }: { focused: boolean; onChange(on: boolean): void }) {
  const label = focused ? "退出专注" : "进入专注模式";
  return (
    <button
      className="icon-button small card-focus"
      aria-label={label}
      title={`${label} ${focusShortcut}`}
      // The editor keeps focus, so typing goes on where it was.
      onMouseDown={(event) => event.preventDefault()}
      onClick={() => onChange(!focused)}
    >
      {focused ? <ArrowsIn size={icon.small} /> : <ArrowsOut size={icon.small} />}
    </button>
  );
}
