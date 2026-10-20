import { describe, expect, it } from "vitest";
import { defaultPreferences, readPreferences } from "../../src/shared/preferences";
import { readTypography, typographyVariables } from "../../src/shared/typography";

describe("排版设置", () => {
  it("default to the design system's 正文排版 values", () => {
    expect(readTypography(undefined)).toEqual({
      bodyFont: "system",
      headingFont: "system",
      codeFont: "mono",
      size: 17,
      leading: 1.8,
      paraGap: 0.9,
      measure: 680,
      headingRatio: 1.6,
      autospace: true,
    });
  });

  it("keep values inside the design system's ranges, snapped to the slider's step", () => {
    expect(readTypography({ size: 40, leading: 1, paraGap: -2, measure: 683, headingRatio: 1.63 })).toMatchObject({
      size: 22,
      leading: 1.4,
      paraGap: 0,
      measure: 680,
      headingRatio: 1.65,
    });
  });

  it("read unknown fonts and wrong types as the current value; installed fonts are kept by family name", () => {
    const base = readTypography({ bodyFont: "serif" });
    expect(readTypography({ bodyFont: "comic", headingFont: "installed:霞鹜文楷", codeFont: "songti", size: "18", autospace: "yes" }, base)).toEqual({
      ...base,
      bodyFont: "serif",
      headingFont: "installed:霞鹜文楷",
      codeFont: "mono",
    });
    expect(readTypography({ bodyFont: "installed:" }).bodyFont).toBe("system");
  });

  it("set the page's typesetting variables; installed families are quoted, with the system face behind them", () => {
    expect(typographyVariables(readTypography(undefined))).toEqual({
      "--body-font": "var(--font-ui)",
      "--heading-font": "var(--font-ui)",
      "--code-font": "var(--font-mono)",
      "--body-size": "17px",
      "--body-leading": "1.8",
      "--para-gap": "0.9em",
      "--measure": "680px",
      "--heading-ratio": "1.6",
      "--text-autospace": "normal",
    });
    const set = typographyVariables(readTypography({ bodyFont: "serif", headingFont: "songti", codeFont: 'installed:My "Mono"\\', autospace: false }));
    expect(set["--body-font"]).toBe("var(--font-serif)");
    expect(set["--heading-font"]).toBe("var(--font-songti)");
    expect(set["--code-font"]).toBe('"My \\"Mono\\"\\\\", var(--font-mono)');
    expect(set["--text-autospace"]).toBe("no-autospace");
  });
});

describe("preferences carry the typography", () => {
  it("default to it, and merge a change to one field into the rest", () => {
    expect(readPreferences(undefined).typography).toEqual(readTypography(undefined));
    const now = readPreferences({ typography: { size: 19, bodyFont: "songti" } });
    expect(readPreferences({ typography: { leading: 2 } }, now).typography).toEqual({ ...defaultPreferences.typography, size: 19, bodyFont: "songti", leading: 2 });
  });
});
