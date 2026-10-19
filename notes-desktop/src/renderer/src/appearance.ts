import type { Appearance } from "../../shared/appearance";

/** Hands the system's look to the design system's variables (tokens.css), before the first frame. */
export function applyAppearance({ material, accent }: Appearance, root: HTMLElement = document.documentElement) {
  root.dataset.material = material;
  if (accent) root.style.setProperty("--accent", accent);
}
