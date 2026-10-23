import { useEffect, useLayoutEffect, useState } from "react";
import type { Appearance } from "../../shared/appearance";
import type { AccentChoice } from "../../shared/preferences";
import { typographyVariables, type Typography } from "../../shared/typography";
import { resolveSpaceTheme, spaceThemeChromeCss, type CustomSpaceTheme, type SpaceThemeChoice } from "../../shared/spaceThemes";

/** Hands the window material to the design system's variables (tokens.css), before the first frame. */
export function applyAppearance({ material }: Appearance, root: HTMLElement = document.documentElement) {
  root.dataset.material = material;
}

/** The system accent colour (#rrggbb), followed while the app runs; null when the system does not say. */
export function useSystemAccent(): string | null {
  const [accent, setAccent] = useState(window.notes.appearance.accent);
  useEffect(() => window.notes.onSystemAccentChanged(setAccent), []);
  return accent;
}

/** 排版: the typesetting variables on the root, so the editor, the preview and the space homepage all follow. */
export function useTypography(typography: Typography) {
  useLayoutEffect(() => {
    const root = document.documentElement.style;
    for (const [name, value] of Object.entries(typographyVariables(typography))) root.setProperty(name, value);
  }, [typography]);
}

/** --accent: the chosen preset, or the system's colour (the design system's blue when it has none). */
export function useAccent(choice: AccentChoice) {
  const system = useSystemAccent();
  useLayoutEffect(() => {
    const root = document.documentElement.style;
    const value = choice === "system" ? system : `var(--accent-${choice})`;
    if (value) root.setProperty("--accent", value);
    else root.removeProperty("--accent");
  }, [choice, system]);
}

/** 空间风格 on the app's own space card around a homepage (its title row): the look's page and text. */
export function useSpaceThemeChrome(choice: SpaceThemeChoice, custom: CustomSpaceTheme) {
  useLayoutEffect(() => {
    let style = document.getElementById("space-theme-chrome");
    if (!style) {
      style = document.createElement("style");
      style.id = "space-theme-chrome";
      document.head.appendChild(style);
    }
    style.textContent = spaceThemeChromeCss(resolveSpaceTheme(choice, custom));
  }, [choice, custom]);
}
