import { useEffect, useState, type CSSProperties } from "react";
import {
  customFrom,
  customPalette,
  spaceDecors,
  spaceFonts,
  spaceRadiusRange,
  spaceShadows,
  spaceTheme,
  spaceThemes,
  type CustomSpaceTheme,
  type SpaceDecor,
  type SpacePalette,
  type SpaceThemeChoice,
  type SpaceThemePreset,
} from "../../shared/spaceThemes";
import { PreviewChoices, Segmented, Slider, Switch, type PreviewChoice } from "./controls";
import { usePreferences } from "./preferences";
import { SettingRow, SettingsGroup } from "./SettingsPanel";

// 空间: how every space homepage looks. One of the examples (默认 follows the app), or 自定义 — the
// user's own colours and details, started from any example. The homepages follow at once.

/** Light or dark, as the app shows now (外观). */
function useDark(): boolean {
  const query = typeof matchMedia === "function" ? matchMedia("(prefers-color-scheme: dark)") : null;
  const [dark, setDark] = useState(!!query?.matches);
  useEffect(() => {
    if (!query) return;
    const changed = () => setDark(query.matches);
    query.addEventListener("change", changed);
    return () => query.removeEventListener("change", changed);
  }, [query]);
  return dark;
}

/** The app's own look in a preview: its tokens, as the homepage takes them. */
const appPalette: SpacePalette = {
  page: "var(--space-surface)",
  card: "var(--card-bg)",
  text: "var(--card-fg)",
  muted: "var(--side-fg)",
  line: "var(--line)",
  accent: "var(--accent)",
  onAccent: "var(--on-accent)",
  feature: "var(--card-bg)",
  featureText: "var(--card-fg)",
  series: ["var(--accent-blue)", "var(--accent-green)", "var(--accent-orange)"],
  good: "var(--accent-green)",
  warn: "var(--accent-orange)",
  bad: "var(--figure-error)",
};

/** A homepage in miniature: the page, a card with a heading and a progress bar, a feature card with bars. */
export function SpaceThemePreview({ palette, decor, radius }: { palette: SpacePalette; decor: SpaceDecor; radius: number }) {
  const style = {
    "--p-page": palette.page,
    "--p-image": palette.pageImage ?? "none",
    "--p-card": palette.card,
    "--p-text": palette.text,
    "--p-muted": palette.muted,
    "--p-accent": palette.accent,
    "--p-feature": palette.feature,
    "--p-feature-text": palette.featureText,
    "--p-radius": `${Math.round(radius / 3)}px`,
    "--p-s1": palette.series[0],
    "--p-s2": palette.series[1],
    "--p-s3": palette.series[2],
  } as CSSProperties;
  return (
    <span className="space-theme-preview" data-decor={decor} style={style}>
      <span className="p-card">
        <span className="p-line" />
        <span className="p-progress">
          <span />
        </span>
      </span>
      <span className="p-card p-feature">
        {[62, 88, 44, 100].map((h, i) => (
          <span key={i} className="p-bar" style={{ height: `${h}%`, background: `var(--p-s${(i % 3) + 1})` }} />
        ))}
      </span>
    </span>
  );
}

function presetPalette(id: SpaceThemePreset, dark: boolean): SpacePalette {
  const theme = spaceTheme(id);
  return (dark ? theme.dark : theme.light) ?? appPalette;
}

function ColorField({ label, value, onChange }: { label: string; value: string; onChange(value: string): void }) {
  return (
    <label className="space-color" title={label}>
      <input type="color" aria-label={label} value={value} onChange={(event) => onChange(event.target.value)} />
      <span>{label}</span>
    </label>
  );
}

const startChoices = spaceThemes.map((t) => ({ value: t.id, label: t.name }));

function CustomEditor({ custom, dark }: { custom: CustomSpaceTheme; dark: boolean }) {
  const { change } = usePreferences();
  const set = (part: Partial<CustomSpaceTheme>) => change({ spaceTheme: "custom", customSpaceTheme: { ...custom, ...part } });
  const followsApp = custom.accent === "app";
  return (
    <SettingsGroup title="自定义" description="从一个示例开始，再改颜色和细节。换起点会换掉下面所有的值。次要文字、分隔线和强调卡片由这几种颜色推出来。">
      <SettingRow label="起点">
        <Segmented label="起点" choices={startChoices} value={custom.base} onChange={(base) => set(customFrom(base, dark))} />
      </SettingRow>
      <SettingRow label="颜色">
        <span className="space-colors">
          <ColorField label="背景" value={custom.page} onChange={(page) => set({ page })} />
          <ColorField label="卡片" value={custom.card} onChange={(card) => set({ card })} />
          <ColorField label="文字" value={custom.text} onChange={(text) => set({ text })} />
          {!followsApp && <ColorField label="强调色" value={custom.accent} onChange={(accent) => set({ accent })} />}
        </span>
      </SettingRow>
      <SettingRow label="强调色跟随应用">
        <Switch label="强调色跟随应用" on={followsApp} onChange={(on) => set({ accent: on ? "app" : customFrom(custom.base, dark).accent.replace("app", "#0a84ff") })} />
      </SettingRow>
      <SettingRow label="图表配色">
        <span className="space-colors">
          {custom.series.map((color, i) => (
            <ColorField
              key={i}
              label={`系列 ${i + 1}`}
              value={color}
              onChange={(next) => set({ series: custom.series.map((c, k) => (k === i ? next : c)) as unknown as CustomSpaceTheme["series"] })}
            />
          ))}
        </span>
      </SettingRow>
      <SettingRow label="字体">
        <Segmented label="字体" choices={spaceFonts} value={custom.font} onChange={(font) => set({ font })} />
      </SettingRow>
      <SettingRow label="圆角">
        <Slider label="圆角" {...spaceRadiusRange} value={custom.radius} format={(v) => `${v} px`} onChange={(radius) => set({ radius })} />
      </SettingRow>
      <SettingRow label="卡片阴影">
        <Segmented label="卡片阴影" choices={spaceShadows} value={custom.shadow} onChange={(shadow) => set({ shadow })} />
      </SettingRow>
      <SettingRow label="细节">
        <Segmented label="细节" choices={spaceDecors} value={custom.decor} onChange={(decor) => set({ decor })} />
      </SettingRow>
    </SettingsGroup>
  );
}

export function SpaceThemePage() {
  const { preferences, change } = usePreferences();
  const dark = useDark();
  const custom = preferences.customSpaceTheme;
  const choices: PreviewChoice<SpaceThemeChoice>[] = [
    ...spaceThemes.map((t) => ({ value: t.id, label: t.name, preview: <SpaceThemePreview palette={presetPalette(t.id, dark)} decor={t.decor} radius={t.radius} /> })),
    { value: "custom" as const, label: "自定义", preview: <SpaceThemePreview palette={customPalette(custom)} decor={custom.decor} radius={custom.radius} /> },
  ];
  const chosen = preferences.spaceTheme === "custom" ? null : spaceTheme(preferences.spaceTheme);
  return (
    <>
      <SettingsGroup title="空间风格" description="每个空间主页的颜色、字体、圆角，以及进度条、圆环和柱状图的画法。示例取自完成度很高的仪表盘设计；也可以选“自定义”，自己定。主页即时跟着变。">
        <div className="space-theme-choices">
          <PreviewChoices label="空间风格" choices={choices} value={preferences.spaceTheme} onChange={(spaceTheme) => change({ spaceTheme })} />
          <p className="settings-description space-theme-note">
            {chosen
              ? `${chosen.description}${chosen.darkOnly ? "始终是深色。" : ""}${chosen.source ? `参考：${chosen.source.title}（Dribbble）。` : ""}`
              : "你自己定的颜色和细节，浅色和深色外观下都一样。"}
          </p>
        </div>
      </SettingsGroup>
      {preferences.spaceTheme === "custom" && <CustomEditor custom={custom} dark={dark} />}
    </>
  );
}
