import { ChatsCircle, FadersHorizontal, ListBullets, Sparkle, TextAa, type Icon } from "@phosphor-icons/react";
import { useEffect, useId, useRef, useState, type ReactNode } from "react";
import { attachmentName, defaultAttachmentFolder, type AttachmentNaming } from "../../shared/attachments";
import type { AccentChoice, ColorScheme, ListDetail, MotionIntensity, Navigation } from "../../shared/preferences";
import { useSystemAccent } from "./appearance";
import { AssistantPage } from "./AssistantSettings";
import { PreviewChoices, Segmented, Swatches, type Choice, type PreviewChoice, type Swatch } from "./controls";
import { listDetails } from "./listDetail";
import { usePreferences } from "./preferences";
import "./settings.css";
import { icon } from "./tokens";
import { TypographyPage } from "./TypographySettings";
import { SelectedIcon } from "./SelectedIcon";

// 设置: a window of its own. Categories on the left, each a page of groups on the right; every group
// has a title and a short description, and its rows line up label | control.

/** One category of the settings panel. Later settings (排版, 导航) add a page here or a group to one. */
interface SettingsPage {
  id: string;
  label: string;
  icon: Icon;
  content(): ReactNode;
}

const pages: SettingsPage[] = [
  { id: "general", label: "通用", icon: FadersHorizontal, content: () => <GeneralPage /> },
  { id: "typography", label: "排版", icon: TextAa, content: () => <TypographyPage /> },
  { id: "list", label: "笔记列表", icon: ListBullets, content: () => <ListPage /> },
  { id: "motion", label: "动画", icon: Sparkle, content: () => <MotionPage /> },
  { id: "assistant", label: "助手", icon: ChatsCircle, content: () => <AssistantPage /> },
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

/** One setting: its name on the left, its control on the right (or below it, when `stacked`). */
export function SettingRow({ label, stacked = false, children }: { label: string; stacked?: boolean; children: ReactNode }) {
  return (
    <div className={stacked ? "settings-row stacked" : "settings-row"}>
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

const navigations: Choice<Navigation>[] = [
  { value: "double", label: "双栏" },
  { value: "single", label: "单栏" },
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
    <>
      <SettingsGroup title="外观" description="浅色或深色、强调色，默认都跟随系统。强调色只用在插入光标、选区、开关和主要按钮上。">
        <SettingRow label="外观">
          <Segmented label="外观" choices={colorSchemes} value={preferences.colorScheme} onChange={(colorScheme) => change({ colorScheme })} />
        </SettingRow>
        <SettingRow label="强调色">
          <Swatches label="强调色" choices={accents} value={preferences.accent} onChange={(accent) => change({ accent })} />
        </SettingRow>
      </SettingsGroup>
      <SettingsGroup title="导航" description="双栏：文件夹树旁边是当前目录内容；单栏：文件夹与笔记在同一棵树里。切换时打开的笔记和浏览的目录都不变。">
        <SettingRow label="导航模式">
          <Segmented label="导航模式" choices={navigations} value={preferences.navigation} onChange={(navigation) => change({ navigation })} />
        </SettingRow>
      </SettingsGroup>
      <AttachmentsGroup />
    </>
  );
}

const namings: Choice<AttachmentNaming>[] = [
  { value: "original", label: "原名" },
  { value: "note-number", label: "笔记名-序号" },
  { value: "note-date", label: "笔记名-日期" },
  { value: "note-date-number", label: "笔记名-日期-序号" },
];

/** 附件: where pasted, dropped and imported files go in the library, and what they are called there. */
function AttachmentsGroup() {
  const { preferences, change } = usePreferences();
  const [problem, setProblem] = useState<string | null>(null);
  const folder = preferences.attachmentFolder;
  const choose = async () => {
    const chosen = await window.notes.chooseAttachmentFolder();
    if (!chosen.ok) return setProblem(chosen.message);
    setProblem(null);
    if (chosen.value) change({ attachmentFolder: chosen.value });
  };
  const example = (number: number) => attachmentName(preferences.attachmentNaming, "截图.png", "周一", new Date(), number);
  return (
    <SettingsGroup
      title="附件"
      description="粘贴、拖入或用“导入图片或附件…”加入笔记的文件，复制到笔记库里的这个文件夹，没有时自动新建。重名时自动编号，已有的文件不会被覆盖。"
    >
      <SettingRow label="存放位置">
        <span className="settings-inline">
          <output className="settings-path" aria-label="附件文件夹">
            笔记库/{folder}
          </output>
          {folder !== defaultAttachmentFolder && (
            <button className="settings-action" onClick={() => (setProblem(null), change({ attachmentFolder: defaultAttachmentFolder }))}>
              恢复默认
            </button>
          )}
          <button className="settings-action" onClick={() => void choose()}>
            选择…
          </button>
        </span>
      </SettingRow>
      {problem && (
        <p className="settings-row settings-warning" role="alert">
          {problem}
        </p>
      )}
      <SettingRow label="命名方式" stacked>
        <Segmented label="附件命名方式" choices={namings} value={preferences.attachmentNaming} onChange={(attachmentNaming) => change({ attachmentNaming })} />
      </SettingRow>
      <p className="settings-row settings-warning" aria-label="命名示例">
        例：在笔记“周一”里粘贴“截图.png”，存为“{example(1)}”，再一张为“{example(2)}”。
      </p>
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

/**
 * 设置 as its own window (2026-10-21 用户反馈): the categories on the window's material with the window
 * controls above them, the page beside on the list's surface, as in the main window. It moves and closes
 * like any window; Esc closes it too.
 */
export function SettingsWindow() {
  const [page, setPage] = useState(pages[0]!.id);
  const nav = useRef<HTMLElement>(null);
  const current = pages.find((p) => p.id === page) ?? pages[0]!;

  useEffect(() => {
    document.title = "设置";
    nav.current?.querySelector<HTMLElement>("[aria-selected=true]")?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.isComposing || event.defaultPrevented) return;
      window.close();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  return (
    <main className="settings settings-window" aria-label="设置">
      <nav ref={nav} className="settings-nav" role="tablist" aria-label="设置分类" aria-orientation="vertical">
        {/* The window is moved by its top, where the window controls are. */}
        <div className="drag" />
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
              <SelectedIcon off={PageIcon} selected={on} />
              <span className="label">{p.label}</span>
            </button>
          );
        })}
      </nav>
      <div className="settings-page" id="settings-page" role="tabpanel" aria-labelledby={`settings-tab-${current.id}`}>
        <div className="settings-page-drag drag" />
        <h2>{current.label}</h2>
        {current.content()}
      </div>
    </main>
  );
}

const isSettingsShortcut = (event: KeyboardEvent) =>
  (event.metaKey || event.ctrlKey) && !event.altKey && !event.shiftKey && (event.code === "Comma" || event.key === ",");

/** ⌘, / Ctrl+, opens 设置 in its window (the menu's 设置… does too, from main). */
export function useSettingsShortcut() {
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (!isSettingsShortcut(event)) return;
      event.preventDefault();
      window.notes.openSettings();
    };
    window.addEventListener("keydown", onKeyDown, true);
    return () => window.removeEventListener("keydown", onKeyDown, true);
  }, []);
}
