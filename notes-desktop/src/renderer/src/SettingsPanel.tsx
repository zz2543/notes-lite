import { FadersHorizontal, ListBullets, Sparkle, type Icon } from "@phosphor-icons/react";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import type { AccentChoice, ColorScheme, ListDetail, MotionIntensity } from "../../shared/preferences";
import { useSystemAccent } from "./appearance";
import { PreviewChoices, Segmented, Swatches, type Choice, type PreviewChoice, type Swatch } from "./controls";
import { listDetails } from "./listDetail";
import { usePreferences } from "./preferences";
import "./settings.css";
import { icon } from "./tokens";

// 设置: a glass panel floating over the window. Categories on the left, each a page of groups on the
// right; every group has a title and a short description, and its rows line up label | control.

/** One category of the settings panel. Later settings (排版, 导航) add a page here or a group to one. */
interface SettingsPage {
  id: string;
  label: string;
  icon: Icon;
  content(): ReactNode;
}

const pages: SettingsPage[] = [
  { id: "general", label: "通用", icon: FadersHorizontal, content: () => <GeneralPage /> },
  { id: "list", label: "笔记列表", icon: ListBullets, content: () => <ListPage /> },
  { id: "motion", label: "动画", icon: Sparkle, content: () => <MotionPage /> },
];

export function SettingsGroup({ title, description, children }: { title: string; description: string; children: ReactNode }) {
  const id = useId();
  return (
    <section className="settings-group" role="group" aria-labelledby={`${id}-title`} aria-describedby={`${id}-description`}>
      <h3 id={`${id}-title`}>{title}</h3>
      <p id={`${id}-description`} className="settings-description">
        {description}
      </p>
      <div className="settings-rows">{children}</div>
    </section>
  );
}

/** One setting: its name on the left, its control on the right. */
export function SettingRow({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="settings-row">
      <span className="settings-label">{label}</span>
      <div className="settings-control">{children}</div>
    </div>
  );
}

const colorSchemes: Choice<ColorScheme>[] = [
  { value: "system", label: "跟随系统" },
  { value: "light", label: "浅色" },
  { value: "dark", label: "深色" },
];

const presets: Swatch<AccentChoice>[] = [
  { value: "blue", label: "蓝", color: "var(--accent-blue)" },
  { value: "purple", label: "紫", color: "var(--accent-purple)" },
  { value: "pink", label: "粉", color: "var(--accent-pink)" },
  { value: "orange", label: "橙", color: "var(--accent-orange)" },
  { value: "green", label: "绿", color: "var(--accent-green)" },
];

function GeneralPage() {
  const { preferences, change } = usePreferences();
  const system = useSystemAccent();
  const accents: Swatch<AccentChoice>[] = [{ value: "system", label: "跟随系统", color: system ?? "var(--accent-blue)" }, ...presets];
  return (
    <SettingsGroup title="外观" description="浅色或深色、强调色，默认都跟随系统。强调色只用在插入光标、选区、开关和主要按钮上。">
      <SettingRow label="外观">
        <Segmented label="外观" choices={colorSchemes} value={preferences.colorScheme} onChange={(colorScheme) => change({ colorScheme })} />
      </SettingRow>
      <SettingRow label="强调色">
        <Swatches label="强调色" choices={accents} value={preferences.accent} onChange={(accent) => change({ accent })} />
      </SettingRow>
    </SettingsGroup>
  );
}

/** A miniature list row at one detail level: bars stand in for the title, the summary and the date. */
function DetailPreview({ detail }: { detail: ListDetail }) {
  return (
    <span className={`detail-preview ${detail}`}>
      {[0, 1].map((row) => (
        <span key={row} className="detail-row">
          <span className="bar title" />
          {detail === "detailed" && <span className="bar summary" />}
          {detail !== "compact" && <span className="bar date" />}
        </span>
      ))}
    </span>
  );
}

const detailChoices: PreviewChoice<ListDetail>[] = listDetails.map(({ value, label }) => ({
  value,
  label,
  preview: <DetailPreview detail={value} />,
}));

function ListPage() {
  const { preferences, change } = usePreferences();
  return (
    <SettingsGroup title="详细程度" description="笔记列表每一行显示多少：简洁只有标题，标准加上日期，详细再加一行摘要。也可以在列表顶部的“…”菜单里切换。">
      <PreviewChoices label="详细程度" choices={detailChoices} value={preferences.listDetail} onChange={(listDetail) => change({ listDetail })} />
    </SettingsGroup>
  );
}

const intensities: Choice<MotionIntensity>[] = [
  { value: "light", label: "轻" },
  { value: "standard", label: "标准" },
  { value: "strong", label: "强" },
];

/** 动画. The 光标动画 and 输入动画 switches (tickets 10 and 11) join this page as their own group. */
function MotionPage() {
  const { preferences, change } = usePreferences();
  return (
    <SettingsGroup title="动效强度" description="“强”最生动；“轻”让面板、菜单和展开更快落定。系统开启“减弱动态效果”时，动效一律降为淡入淡出。">
      <SettingRow label="强度">
        <Segmented label="动效强度" choices={intensities} value={preferences.motion} onChange={(motion) => change({ motion })} />
      </SettingRow>
    </SettingsGroup>
  );
}

function SettingsPanel({ onClose }: { onClose(): void }) {
  const [page, setPage] = useState(pages[0]!.id);
  const panel = useRef<HTMLDivElement>(null);
  const current = pages.find((p) => p.id === page) ?? pages[0]!;

  // Focus moves into the panel, and back where it was once the panel closes.
  useEffect(() => {
    const before = document.activeElement as HTMLElement | null;
    panel.current?.querySelector<HTMLElement>("[aria-selected=true]")?.focus();
    return () => before?.focus();
  }, []);

  return (
    <div className="scrim" onPointerDown={(event) => event.target === event.currentTarget && onClose()}>
      <div
        ref={panel}
        className="settings"
        role="dialog"
        aria-modal="true"
        aria-label="设置"
        onKeyDown={(event) => {
          if (event.key !== "Escape" || event.nativeEvent.isComposing) return;
          event.stopPropagation();
          onClose();
        }}
      >
        <nav className="settings-nav" role="tablist" aria-label="设置分类" aria-orientation="vertical">
          <h2>设置</h2>
          {pages.map((p) => {
            const PageIcon = p.icon;
            const on = p.id === current.id;
            return (
              <button
                key={p.id}
                className="settings-tab"
                role="tab"
                id={`settings-tab-${p.id}`}
                aria-selected={on}
                aria-controls="settings-page"
                tabIndex={on ? 0 : -1}
                onClick={() => setPage(p.id)}
              >
                <PageIcon size={icon.regular} weight={on ? "fill" : "regular"} />
                <span className="label">{p.label}</span>
              </button>
            );
          })}
        </nav>
        <div className="settings-page" id="settings-page" role="tabpanel" aria-labelledby={`settings-tab-${current.id}`}>
          <h2>{current.label}</h2>
          {current.content()}
        </div>
      </div>
    </div>
  );
}

const isSettingsShortcut = (event: KeyboardEvent) =>
  (event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey && (event.code === "Comma" || event.key === ",");

/** ⌘, / Ctrl+, (or the menu's 设置…) opens the panel; the result is what to render. */
export function useSettingsPanel(): ReactNode {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!isSettingsShortcut(event)) return;
      event.preventDefault();
      setOpen(true);
    };
    window.addEventListener("keydown", onKeyDown, true);
    const offMenu = window.notes.onSettingsRequest(() => setOpen(true));
    return () => {
      window.removeEventListener("keydown", onKeyDown, true);
      offMenu();
    };
  }, []);
  return open ? <SettingsPanel onClose={() => setOpen(false)} /> : null;
}
