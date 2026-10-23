import { describe, expect, it } from "vitest";
import { readPreferences } from "../../src/shared/preferences";
import {
  customFrom,
  readCustomSpaceTheme,
  resolveSpaceTheme,
  spaceThemeChromeCss,
  spaceThemeCss,
  spaceThemes,
  defaultCustomSpaceTheme,
} from "../../src/shared/spaceThemes";

describe("空间风格", () => {
  it("defaults to 默认, which overrides nothing", () => {
    const preferences = readPreferences({});
    expect(preferences.spaceTheme).toBe("app");
    expect(spaceThemeCss(resolveSpaceTheme("app", preferences.customSpaceTheme))).toBe("");
    expect(spaceThemeChromeCss(null)).toBe("");
  });

  it("keeps a known choice and drops an unknown one", () => {
    expect(readPreferences({ spaceTheme: "earth" }).spaceTheme).toBe("earth");
    expect(readPreferences({ spaceTheme: "neon" }).spaceTheme).toBe("app");
  });

  it("writes every example as variables, light and dark, with its details", () => {
    for (const theme of spaceThemes.filter((t) => t.id !== "app")) {
      const css = spaceThemeCss(resolveSpaceTheme(theme.id, defaultCustomSpaceTheme), (font) => `/*font ${font}*/`);
      expect(css).toContain(`--space-theme: ${theme.id};`);
      expect(css).toContain(`--space-decor: ${theme.decor};`);
      expect(css).toContain(`--space-radius: ${theme.radius}px;`);
      expect(css).toContain("--space-chart-6:");
      expect(css).toContain("--space-feature:");
      expect(css).toContain(`/*font ${theme.font}*/`);
      // Dark-only looks have one palette, so no dark block.
      expect(css.includes("prefers-color-scheme: dark")).toBe(!theme.darkOnly);
    }
  });

  it("reads a stored custom look field by field, keeping valid values and clamping the radius", () => {
    const custom = readCustomSpaceTheme({ page: "#ABCDEF", card: "red", accent: "app", radius: 99, decor: "led", font: "comic", series: ["#111111"] });
    expect(custom.page).toBe("#abcdef");
    expect(custom.card).toBe(defaultCustomSpaceTheme.card);
    expect(custom.accent).toBe("app");
    expect(custom.radius).toBe(36);
    expect(custom.decor).toBe("led");
    expect(custom.font).toBe(defaultCustomSpaceTheme.font);
    expect(custom.series).toEqual(["#111111", defaultCustomSpaceTheme.series[1], defaultCustomSpaceTheme.series[2]]);
  });

  it("starts a custom look from an example, its translucent card made solid", () => {
    const glass = customFrom("glass");
    expect(glass.card).toMatch(/^#[0-9a-f]{6}$/);
    expect(glass.decor).toBe("glow");
    const css = spaceThemeCss(resolveSpaceTheme("custom", { ...glass, accent: "app" }));
    expect(css).toContain("--space-accent: var(--accent);");
    expect(css).toContain("--space-theme: custom;");
  });

  it("gives the title row the colour at the top of a page that fades", () => {
    expect(spaceThemeChromeCss(resolveSpaceTheme("sky", defaultCustomSpaceTheme))).toContain("--space-surface: #a9cdee;");
  });
});
