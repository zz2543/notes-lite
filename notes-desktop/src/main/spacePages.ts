// 空间主页: each space's homepage runs in a sandbox of its own, a WebContentsView laid over the
// card, never in the app's page (ADR 0003). It has no Node, its own persistent storage, and the
// network; it reaches the notes only through `space` (or its old name `lb`), whose requests main hands
// to the core library. Nothing here decides what a request may do.
import { join } from "node:path";
import { ipcMain, protocol, session, shell, WebContentsView, type BrowserWindow, type Rectangle, type Session } from "electron";
import { hostAllowed, spaceChanges, spaceLibrary, spaceRequests, spacesFolder, type SpaceReply, type SpaceScope, type SpaceStorage } from "../core";
import type { SpacePageEvent, SpacePageProblem } from "../shared/api";
import { spacePageChannels } from "../shared/spacePage";
import { kitFonts, kitLibraries, kitScripts, kitStyle, settingsStyleId } from "./spaceKit";

export const spaceScheme = "notes-space";
const pageUrl = `${spaceScheme}://page/`;

/** Before the app is ready: the homepage's address is a secure origin with storage of its own. */
export function registerSpaceScheme() {
  protocol.registerSchemesAsPrivileged([{ scheme: spaceScheme, privileges: { standard: true, secure: true, supportFetchAPI: true } }]);
}

const isOpen = (request: unknown) => typeof request === "object" && request !== null && (request as { method?: unknown }).method === "open";
const isPath = (result: unknown): result is { path: string } => typeof result === "object" && result !== null && typeof (result as { path?: unknown }).path === "string";

const escapeHtml = (s: string) => s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

/** `</` would close the element an inline script or style sits in; `<\/` reads the same to JS and CSS. */
const inline = (text: string) => text.replaceAll("</", "<\\/");

/**
 * The space file as a whole page: the style kit and the page settings, then `space` and the components,
 * all before any of its own content, so its scripts and elements find them ready. `offset` is how many
 * lines come before the space file's first, so an error's line can be told in the file's own terms.
 */
function documentFor(name: string, html: string, settings: string): { page: string; offset: number } {
  const head = [
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<title>${escapeHtml(name)}</title>`,
    `<style>${inline(kitStyle)}</style>`,
    `<style id="${settingsStyleId}">${inline(settings)}</style>`,
    ...kitScripts.map((script) => `<script>${inline(script)}</script>`),
  ].join("");
  const before = `<!doctype html><html lang="zh-CN"><head>${head}</head><body class="space-page lb-page">\n`;
  return { page: `${before}${html}\n</body></html>`, offset: before.split("\n").length - 1 };
}

/** What a homepage's script reported (see spaceShim), as the page tells it; nothing in it is trusted. */
interface RawProblem {
  message?: unknown;
  source?: unknown;
  line?: unknown;
  column?: unknown;
  stack?: unknown;
}

const text = (value: unknown, limit: number) => (typeof value === "string" ? value.slice(0, limit) : "");
const count = (value: unknown) => (typeof value === "number" && Number.isFinite(value) ? Math.floor(value) : 0);

/** Where an error happened, in the space file's own lines when it happened there. */
function problemOf(raw: RawProblem, offset: number): SpacePageProblem {
  const source = text(raw.source, 2000);
  const line = count(raw.line);
  const column = count(raw.column);
  let location = "";
  if (source === "" || source.startsWith(pageUrl)) {
    // Lines before the file are the style kit and the components, which the page's author never sees.
    if (line > offset) location = `空间文件第 ${line - offset} 行${column > 0 ? `，第 ${column} 列` : ""}`;
  } else if (line > 0) location = `${source} 第 ${line} 行`;
  return { message: text(raw.message, 2000) || "未知错误", location, stack: text(raw.stack, 8000) };
}

/** Stable per library and space (and across a rename), so a space keeps its preferences and never sees another's. */
const partitionOf = async (storage: SpaceStorage, root: string, name: string) => `persist:space-${await storage.key(root, name)}`;

interface Hosted {
  name: string;
  view: WebContentsView;
  /** The space file as last loaded. */
  html: string;
  /** Its scope, which decides which changes the page hears of. */
  scope: SpaceScope;
}

export interface SpacePages {
  /** Lays the homepage of `name` over `bounds` (window coordinates), loading it the first time or when its file changed. */
  show(name: string, bounds: Rectangle): Promise<void>;
  /** Takes the homepage off the window; it keeps running, state intact, for when it comes back. */
  hide(): void;
  /** Closes every homepage, as when another library opens. */
  closeAll(): void;
  /** Closes the homepage of `name`, as when its space was renamed or deleted. */
  close(name: string): void;
  /** Sends the page settings (排版, 强调色, 动效) again to every open homepage, after they changed. */
  settingsChanged(): void;
  /**
   * Paths in the library changed (the watcher's report, whoever changed them): a rewritten space file
   * loads again, and each homepage hears, through `space.on("change")`, of the changes in its scope.
   */
  libraryChanged(paths: string[]): Promise<void>;
  /** Loads the homepage of `name` afresh, if it is open, as after its 联网 was allowed or taken back. */
  reload(name: string): void;
}

/**
 * `settings` answers the page settings as CSS (spaceKit's spacePageSettings) at the moment they are
 * needed: when a homepage loads, and whenever `settingsChanged` is called.
 */
export function spacePages(
  window: () => BrowserWindow | null,
  root: () => string | null,
  settings: () => string,
  emit: (event: SpacePageEvent) => void,
  /** Told of every path a homepage wrote (see SpaceRequestOptions.wrote). */
  wrote: (paths: string[]) => Promise<void>,
  storage: SpaceStorage,
  /** 联网: the sites the homepage of `name` may reach now, read each time it loads; none by default. */
  network: (library: string, name: string) => Promise<string[]> = async () => [],
): SpacePages {
  let hosted: Hosted[] = [];
  // How many lines come before each space file in the page last served for it.
  const offsets = new Map<string, number>();
  let shown: Hosted | null = null;
  let hostedRoot: string | null = null;
  // Which space each session serves now: a renamed space keeps its session under its new name.
  const served = new WeakMap<Session, { library: string; name: string }>();
  // The sites each session's page may reach, as allowed when it last loaded.
  const reachable = new WeakMap<Session, string[]>();

  const trash = (path: string) => shell.trashItem(path);

  /** Each space's session answers its own address with its own page, read from disk at each load. */
  const serve = (ses: Session, library: string, name: string) => {
    const handled = served.has(ses);
    served.set(ses, { library, name });
    if (handled) return;
    ses.protocol.handle(spaceScheme, async (request) => {
      // The libraries the app carries (space.load): the same on every page, offline too.
      const path = new URL(request.url).pathname;
      const font = kitFonts[path];
      if (font) return new Response(new Uint8Array(font()), { headers: { "content-type": "font/woff2", "cache-control": "max-age=31536000, immutable" } });
      const carried = kitLibraries[path];
      if (carried) return new Response(await carried(), { headers: { "content-type": "text/javascript; charset=utf-8", "cache-control": "max-age=31536000, immutable" } });
      const { library, name } = served.get(ses)!;
      reachable.set(ses, await network(library, name).catch(() => []));
      const space = await spaceLibrary(library).space(name).catch(() => null);
      const { page, offset } = documentFor(name, space?.html ?? "", settings());
      offsets.set(name, offset);
      return new Response(page, { headers: { "content-type": "text/html; charset=utf-8" } });
    });
    // 联网: nothing leaves for the web but to the sites the user allowed this homepage.
    ses.webRequest.onBeforeRequest({ urls: ["http://*/*", "https://*/*", "ws://*/*", "wss://*/*"] }, (details, answer) =>
      answer({ cancel: !hostAllowed(details.url, reachable.get(ses) ?? []) }),
    );
    // No camera, microphone, location or notifications: the page is someone else's script.
    ses.setPermissionRequestHandler((_contents, _permission, answer) => answer(false));
    ses.setPermissionCheckHandler(() => false);
  };

  /** Loads the page afresh; whatever went wrong on the old one goes with it. */
  const reload = (page: Hosted) => {
    emit({ space: page.name, kind: "loaded" });
    page.view.webContents.reload();
  };

  const create = (library: string, name: string, html: string, scope: SpaceScope, partition: string): Hosted => {
    const ses = session.fromPartition(partition);
    serve(ses, library, name);
    const view = new WebContentsView({
      webPreferences: {
        preload: join(__dirname, "../preload/space.js"),
        partition,
        sandbox: true,
        contextIsolation: true,
        nodeIntegration: false,
        nodeIntegrationInSubFrames: false,
        webviewTag: false,
        spellcheck: false,
      },
    });
    const contents = view.webContents;
    // The homepage never navigates away; links that would open a window open in the browser.
    contents.on("will-navigate", (event) => event.preventDefault());
    contents.on("will-redirect", (event) => event.isMainFrame && event.preventDefault());
    contents.setWindowOpenHandler(({ url }) => {
      if (/^https?:/i.test(url)) void shell.openExternal(url);
      return { action: "deny" };
    });
    contents.setBackgroundThrottling(false);
    const problem = (message: string) => emit({ space: name, kind: "problem", problem: { message, location: "", stack: "" } });
    contents.on("did-fail-load", (_event, code, description, url, isMainFrame) => {
      // -3 is a load given up for another (a reload, say), which is no failure.
      if (isMainFrame && code !== -3) problem(`页面加载失败：${description}（${url}）`);
    });
    const hostedPage: Hosted = { name, view, html, scope };
    contents.on("render-process-gone", (_event, details) => {
      if (details.reason === "clean-exit") return;
      problem("页面进程意外退出，已重新载入。");
      // Loads again as itself; the problem stays shown, so it is not a fresh start.
      setTimeout(() => !contents.isDestroyed() && contents.reload(), 0);
    });
    emit({ space: name, kind: "loaded" });
    void contents.loadURL(pageUrl);
    return hostedPage;
  };

  const closeAll = () => {
    hide();
    for (const { view } of hosted) if (!view.webContents.isDestroyed()) view.webContents.close();
    hosted = [];
  };

  const close = (name: string) => {
    const page = hosted.find((h) => h.name === name);
    if (!page) return;
    if (shown === page) hide();
    hosted = hosted.filter((h) => h !== page);
    if (!page.view.webContents.isDestroyed()) page.view.webContents.close();
  };

  const hide = () => {
    const win = window();
    if (shown && win && !win.isDestroyed()) win.contentView.removeChildView(shown.view);
    shown = null;
  };

  const show = async (name: string, bounds: Rectangle) => {
    const library = root();
    const win = window();
    if (!library || !win || win.isDestroyed()) return;
    if (hostedRoot !== library) {
      closeAll();
      hostedRoot = library;
    }
    const space = await spaceLibrary(library).space(name).catch(() => null);
    if (!space) return hide();
    const partition = await partitionOf(storage, library, name);
    let page = hosted.find((h) => h.name === name);
    if (page && page.view.webContents.isDestroyed()) {
      hosted = hosted.filter((h) => h !== page);
      page = undefined;
    }
    if (!page) {
      page = create(library, name, space.html, space.scope, partition);
      hosted.push(page);
    } else if (page.html !== space.html) {
      // Rewritten since it was loaded (by an agent, say): shown as it is now.
      page.html = space.html;
      page.scope = space.scope;
      reload(page);
    }
    if (shown !== page) {
      hide();
      win.contentView.addChildView(page.view);
      shown = page;
    }
    page.view.setBounds({ x: Math.round(bounds.x), y: Math.round(bounds.y), width: Math.round(bounds.width), height: Math.round(bounds.height) });
  };

  /** The homepage that sent an IPC message from its own main frame; embedded frames have no say. */
  const sentBy = (event: Electron.IpcMainEvent | Electron.IpcMainInvokeEvent) => {
    const page = hosted.find((h) => !h.view.webContents.isDestroyed() && h.view.webContents === event.sender);
    return page && event.senderFrame === page.view.webContents.mainFrame ? page : undefined;
  };

  // `lb` requests: only from a homepage's own main frame, and always as that homepage's space.
  ipcMain.handle(spacePageChannels.request, async (event, request: unknown): Promise<SpaceReply> => {
    const page = sentBy(event);
    const library = hostedRoot;
    if (!page || !library) {
      return { ok: false, error: { code: "outside-scope", message: "只有空间主页本身可以使用 lb。" } };
    }
    const reply = await spaceRequests(library, page.name, { trash, wrote }).handle(request);
    // space.open: the app opens the note (in scope and there, as the library checked).
    if (reply.ok && isOpen(request) && isPath(reply.result)) emit({ space: page.name, kind: "open", path: reply.result.path });
    // 写入提示: the app says the homepage wrote, and how much.
    if (reply.ok && reply.changes > 0) emit({ space: page.name, kind: "wrote", changes: reply.changes, records: reply.recordChanges });
    return reply;
  });

  // 错误条: errors the page's scripts, resources and components ran into.
  ipcMain.on(spacePageChannels.error, (event, raw: unknown) => {
    const page = sentBy(event);
    if (!page || typeof raw !== "object" || raw === null) return;
    emit({ space: page.name, kind: "problem", problem: problemOf(raw as RawProblem, offsets.get(page.name) ?? 0) });
  });

  const touchesSpaceFiles = (path: string) => path === "" || path === ".notes" || path === spacesFolder || path.startsWith(`${spacesFolder}/`);

  const libraryChanged = async (paths: string[]) => {
    const library = hostedRoot;
    if (!library || paths.length === 0) return;
    const spaces = paths.some(touchesSpaceFiles) ? spaceLibrary(library) : null;
    for (const page of hosted) {
      if (page.view.webContents.isDestroyed()) continue;
      const space = spaces && (await spaces.space(page.name).catch(() => null));
      if (space && space.html !== page.html) {
        // An agent rewrote it: shown as it is now, without review (ADR 0002).
        page.html = space.html;
        page.scope = space.scope;
        reload(page);
        continue;
      }
      const changed = spaceChanges(page.scope, paths);
      if (changed.length > 0) page.view.webContents.send(spacePageChannels.changed, changed);
    }
  };

  const settingsChanged = () => {
    const css = settings();
    for (const { view } of hosted) if (!view.webContents.isDestroyed()) view.webContents.send(spacePageChannels.settings, css);
  };

  const reloadNamed = (name: string) => {
    const page = hosted.find((p) => p.name === name);
    if (page) reload(page);
  };

  return { show, hide, closeAll, close, settingsChanged, libraryChanged, reload: reloadNamed };
}
