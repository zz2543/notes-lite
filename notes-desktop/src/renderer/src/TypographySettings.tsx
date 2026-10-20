import { EditorState } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { useEffect, useRef, useState } from "react";
import {
  codeFontPresets,
  fontPresets,
  fontStack,
  installedFamily,
  installedFont,
  ranges,
  type FontChoice,
  type FontPreset,
  type NumericSetting,
  type Typography,
} from "../../shared/typography";
import { PreviewChoices, Slider, Switch, type PreviewChoice } from "./controls";
import { typesetView } from "./markdownView";
import { openNoteText } from "./noteDraft";
import { usePreferences } from "./preferences";
import { SettingRow, SettingsGroup } from "./SettingsPanel";
import "./typography.css";

// 排版: the options on the left, the open note on the right, set as the editor sets it and moving into
// each new value as a slider moves. Everything here is the variables typography.ts writes on the root.

const presetLabels: { readonly [P in FontPreset]: string } = {
  system: "系统",
  songti: "思源宋体",
  serif: "Source Serif",
  mono: "等宽",
};

/** What a font looks like: a CJK and a Latin glyph in it. */
const FontSample = ({ family }: { family: string }) => (
  <span className="font-sample" style={{ fontFamily: family }}>
    永 Aa
  </span>
);

// Asked once, when a font menu is first opened: Chromium's Local Font Access lists the installed faces.
let installedFamilies: Promise<string[]> | undefined;
type LocalFont = { family: string };
const queryLocalFonts = (window as unknown as { queryLocalFonts?: () => Promise<LocalFont[]> }).queryLocalFonts;

function listInstalledFamilies(): Promise<string[]> {
  installedFamilies ??= (queryLocalFonts?.() ?? Promise.resolve([]))
    .then((fonts) => [...new Set(fonts.map((font) => font.family))].sort((a, b) => a.localeCompare(b)))
    .catch(() => []);
  return installedFamilies;
}

function useInstalledFamilies(): [string[], () => void] {
  const [families, setFamilies] = useState<string[]>([]);
  const load = () => void listInstalledFamilies().then(setFamilies);
  return [families, load];
}

/** 字体: a few presets shown in their own face, or any font installed on this computer. */
function FontPicker({ label, presets, value, fallback, onChange }: { label: string; presets: readonly FontPreset[]; value: FontChoice; fallback: FontPreset; onChange(value: FontChoice): void }) {
  const [installed, load] = useInstalledFamilies();
  const family = installedFamily(value);
  const families = family && !installed.includes(family) ? [family, ...installed] : installed;
  const choices: PreviewChoice<FontChoice>[] = presets.map((preset) => ({
    value: preset,
    label: presetLabels[preset],
    preview: <FontSample family={fontStack(preset, fallback)} />,
  }));
  return (
    <div className="font-picker">
      <PreviewChoices label={label} choices={choices} value={value} onChange={onChange} />
      <select
        className="font-installed"
        aria-label={`${label}：系统已安装字体`}
        value={family ?? ""}
        style={{ fontFamily: family ? fontStack(value, fallback) : undefined }}
        onFocus={load}
        onPointerDown={load}
        onChange={(event) => event.target.value && onChange(installedFont(event.target.value))}
      >
        <option value="" disabled>
          系统已安装字体…
        </option>
        {families.map((name) => (
          <option key={name} value={name}>
            {name}
          </option>
        ))}
      </select>
    </div>
  );
}

const trim = (value: number) => String(Number(value.toFixed(2)));

const sliders: { key: NumericSetting; label: string; format(value: number): string }[] = [
  { key: "size", label: "字号", format: (v) => `${trim(v)}px` },
  { key: "leading", label: "行距", format: trim },
  { key: "paraGap", label: "段距", format: (v) => `${trim(v)}em` },
  { key: "measure", label: "版心宽度", format: (v) => `${trim(v)}px` },
  { key: "headingRatio", label: "标题大小比例", format: trim },
];

const sample = "# 排版预览\n\n打开一篇笔记，这里就用它来预览。Markdown 原文不会因为排版设置而改变。\n\n## 小标题\n\n第二段文字，看看段距与行距。";

/** The open note (or a sample when none is open), typeset by the same rules as the editor. */
function TypesetPreview() {
  const host = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const view = new EditorView({
      parent: host.current!,
      state: EditorState.create({
        doc: openNoteText() ?? sample,
        extensions: [EditorState.readOnly.of(true), EditorView.editable.of(false), EditorView.lineWrapping, typesetView],
      }),
    });
    // The text moves into new sizes over a spring; heights are measured again once it settles.
    const settled = () => view.requestMeasure();
    view.dom.addEventListener("transitionend", settled);
    return () => view.destroy();
  }, []);
  return (
    <figure className="typeset-preview" aria-label="排版预览">
      <div className="typeset-page editor" ref={host} />
    </figure>
  );
}

export function TypographyPage() {
  const { preferences, change } = usePreferences();
  const typography = preferences.typography;
  const set = (part: Partial<Typography>) => change({ typography: { ...typography, ...part } });
  return (
    <div className="typography-page">
      <div className="typography-options">
        <SettingsGroup title="字体" description="正文、标题和代码各选一种字体：预设，或这台电脑上安装的任何字体。思源宋体与 Source Serif 4 随应用附带。">
          <SettingRow label="正文" stacked>
            <FontPicker label="正文字体" presets={fontPresets} fallback="system" value={typography.bodyFont} onChange={(bodyFont) => set({ bodyFont })} />
          </SettingRow>
          <SettingRow label="标题" stacked>
            <FontPicker label="标题字体" presets={fontPresets} fallback="system" value={typography.headingFont} onChange={(headingFont) => set({ headingFont })} />
          </SettingRow>
          <SettingRow label="代码" stacked>
            <FontPicker label="代码字体" presets={codeFontPresets} fallback="mono" value={typography.codeFont} onChange={(codeFont) => set({ codeFont })} />
          </SettingRow>
        </SettingsGroup>
        <SettingsGroup title="版式" description="字号、行距、段距、版心宽度与标题大小比例，调整时右侧预览随之变化。">
          {sliders.map(({ key, label, format }) => (
            <SettingRow key={key} label={label}>
              <Slider label={label} value={typography[key]} {...ranges[key]} format={format} onChange={(value) => set({ [key]: value } as Partial<Typography>)} />
            </SettingRow>
          ))}
        </SettingsGroup>
        <SettingsGroup title="中英文间距" description="在中文与英文、数字之间自动留出空隙。只影响显示，笔记文件不变。">
          <SettingRow label="自动间距">
            <Switch label="中英文自动间距" on={typography.autospace} onChange={(autospace) => set({ autospace })} />
          </SettingRow>
        </SettingsGroup>
      </div>
      <TypesetPreview />
    </div>
  );
}
