import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import type { Navigation } from "../../shared/preferences";
import { assistantBreakpoints } from "./tokens";

// While the 助手栏 is open the side navigation makes room for it as the window narrows: 双栏, then 单栏,
// then the 图标栏. The tier is settled only when the column opens, the window is resized or the
// navigation setting changes; closing the column leaves the navigation as it is.

/** 双栏导航, 单栏导航, or the 图标栏 (icons only). */
export type NavigationTier = Navigation | "rail";

export function tierFor(setting: Navigation, assistantOpen: boolean, width: number): NavigationTier {
  if (!assistantOpen || width >= assistantBreakpoints.single) return setting;
  return width >= assistantBreakpoints.rail ? "single" : "rail";
}

const windowWidth = () => window.innerWidth;
const onResize = (changed: () => void) => {
  window.addEventListener("resize", changed);
  return () => window.removeEventListener("resize", changed);
};

/** The window narrower than the widest tier: the 助手栏 is narrower too. */
export const useNarrowWindow = () => useSyncExternalStore(onResize, windowWidth) < assistantBreakpoints.single;

/** The navigation tier, and a way to bring the 图标栏 back to 单栏 (an icon or “展开导航”). */
export function useNavigationTier(setting: Navigation, assistantOpen: boolean): [NavigationTier, () => void] {
  const [tier, setTier] = useState(() => tierFor(setting, assistantOpen, windowWidth()));
  const open = useRef(assistantOpen);
  open.current = assistantOpen;
  const settle = () => setTier(tierFor(setting, open.current, windowWidth()));
  useEffect(settle, [setting]);
  useEffect(() => {
    if (assistantOpen) settle();
  }, [assistantOpen]);
  useEffect(() => onResize(settle), [setting]);
  return [tier, () => setTier("single")];
}
