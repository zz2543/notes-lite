import { FadersHorizontal, ListBullets, Sparkle, type Icon } from "@phosphor-icons/react";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import type { ColorScheme } from "../../shared/preferences";
import { Segmented, type Choice } from "./controls";
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
  { id: "list", label: "笔记列表", icon: ListBullets, content: () => null },
  { id: "motion", label: "动画", icon: Sparkle, content: () => null },
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

function GeneralPage() {
  const { preferences, change } = usePreferences();
  return (
    <SettingsGroup title="外观" description="浅色或深色，默认跟随系统。">
      <SettingRow label="外观">
        <Segmented label="外观" choices={colorSchemes} value={preferences.colorScheme} onChange={(colorScheme) => change({ colorScheme })} />
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
