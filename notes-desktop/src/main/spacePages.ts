// 空间主页: each space's homepage runs in a sandbox of its own, a WebContentsView laid over the
// card, never in the app's page (ADR 0003). It has no Node, its own persistent storage, and the
// network; it reaches the notes only through `space` (or its old name `lb`), whose requests main hands
// to the core library. Nothing here decides what a request may do.
import { createHash } from "node:crypto";
import { join } from "node:path";
import { ipcMain, protocol, session, shell, WebContentsView, type BrowserWindow, type Rectangle, type Session } from "electron";
import { spaceLibrary, spaceRequests, type SpaceReply } from "../core";
import { spacePageChannels } from "../shared/spacePage";
import { kitScripts, kitStyle, settingsStyleId } from "./spaceKit";

export const spaceScheme = "notes-space";
const pageUrl = `${spaceScheme}://page/`;

/** Before the app is ready: the homepage's address is a secure origin with storage of its own. */
export function registerSpaceScheme() {
  protocol.registerSchemesAsPrivileged([{ scheme: spaceScheme, privileges: { standard: true, secure: true, supportFetchAPI: true } }]);
}

const escapeHtml = (s: string) => s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

/** `</` would close the element an inline script or style sits in; `<\/` reads the same to JS and CSS. */
const inline = (text: string) => text.replaceAll("</", "<\\/");

/**
 * The space file as a whole page: the style kit and the page settings, then `space` and the components,
 * all before any of its own content, so its scripts and elements find them ready.
 */
function documentFor(name: string, html: string, settings: string): string {
  const head = [
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    `<title>${escapeHtml(name)}</title>`,
    `<style>${inline(kitStyle)}</style>`,
    `<style id="${settingsStyleId}">${inline(settings)}</style>`,
    ...kitScripts.map((script) => `<script>${inline(script)}</script>`),
  ].join("");
  return `<!doctype html><html lang="zh-CN"><head>${head}</head><body class="space-page lb-page">\n${html}\n</body></html>`;
}

/** Stable per library and space, so a space keeps its preferences and never sees another's. */
const partitionOf = (root: string, name: string) => `persist:space-${createHash("sha256").update(`${root}\u0000${name}`).digest("hex").slice(0, 32)}`;

interface Hosted {
  name: string;
  view: WebContentsView;
  /** The space file as last loaded. */
  html: string;
}

export interface SpacePages {
  /** Lays the homepage of `name` over `bounds` (window coordinates), loading it the first time or when its file changed. */
  show(name: string, bounds: Rectangle): Promise<void>;
  /** Takes the homepage off the window; it keeps running, state intact, for when it comes back. */
  hide(): void;
  /** Closes every homepage, as when another library opens. */
  closeAll(): void;
  /** Sends the page settings (排版, 强调色, 动效) again to every open homepage, after they changed. */
  settingsChanged(): void;
}

/**
 * `settings` answers the page settings as CSS (spaceKit's spacePageSettings) at the moment they are
 * needed: when a homepage loads, and whenever `settingsChanged` is called.
 */
export function spacePages(window: () => BrowserWindow | null, root: () => string | null, settings: () => string): SpacePages {
  let hosted: Hosted[] = [];
  let shown: Hosted | null = null;
  let hostedRoot: string | null = null;
  const handled = new WeakSet<Session>();

  const trash = (path: string) => shell.trashItem(path);

  /** Each space's session answers its own address with its own page, read from disk at each load. */
  const serve = (ses: Session, library: string, name: string) => {
    if (handled.has(ses)) return;
    handled.add(ses);
    ses.protocol.handle(spaceScheme, async () => {
      const space = await spaceLibrary(library).space(name).catch(() => null);
      const page = documentFor(name, space?.html ?? "", settings());
      return new Response(page, { headers: { "content-type": "text/html; charset=utf-8" } });
    });
    // No camera, microphone, location or notifications: the page is someone else's script.
    ses.setPermissionRequestHandler((_contents, _permission, answer) => answer(false));
    ses.setPermissionCheckHandler(() => false);
  };

  const create = (library: string, name: string, html: string): Hosted => {
    const partition = partitionOf(library, name);
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
    void contents.loadURL(pageUrl);
    return { name, view, html };
  };

  const closeAll = () => {
    hide();
    for (const { view } of hosted) if (!view.webContents.isDestroyed()) view.webContents.close();
    hosted = [];
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
    let page = hosted.find((h) => h.name === name);
    if (page && page.view.webContents.isDestroyed()) {
      hosted = hosted.filter((h) => h !== page);
      page = undefined;
    }
    if (!page) {
      page = create(library, name, space.html);
      hosted.push(page);
    } else if (page.html !== space.html) {
      // Rewritten since it was loaded (by an agent, say): shown as it is now.
      page.html = space.html;
      page.view.webContents.reload();
    }
    if (shown !== page) {
      hide();
      win.contentView.addChildView(page.view);
      shown = page;
    }
    page.view.setBounds({ x: Math.round(bounds.x), y: Math.round(bounds.y), width: Math.round(bounds.width), height: Math.round(bounds.height) });
  };

  // `lb` requests: only from a homepage's own main frame, and always as that homepage's space.
  ipcMain.handle(spacePageChannels.request, async (event, request: unknown): Promise<SpaceReply> => {
    const page = hosted.find((h) => !h.view.webContents.isDestroyed() && h.view.webContents === event.sender);
    const library = hostedRoot;
    if (!page || !library || event.senderFrame !== page.view.webContents.mainFrame) {
      return { ok: false, error: { code: "outside-scope", message: "只有空间主页本身可以使用 lb。" } };
    }
    return spaceRequests(library, page.name, { trash }).handle(request);
  });

  const settingsChanged = () => {
    const css = settings();
    for (const { view } of hosted) if (!view.webContents.isDestroyed()) view.webContents.send(spacePageChannels.settings, css);
  };

  return { show, hide, closeAll, settingsChanged };
}
