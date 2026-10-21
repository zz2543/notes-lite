import { _electron as electron, expect, test as base, type ElectronApplication, type Locator, type Page } from "@playwright/test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const appDir = join(__dirname, "../..");
// Apps a test launched; any still running when it ends are closed before its scratch folder goes,
// since Windows will not delete files an app holds open.
const running = new Set<ElectronApplication>();

/** Each test gets a scratch folder for its libraries and the app's settings. */
export const test = base.extend<{ scratch: string }>({
  // eslint-disable-next-line no-empty-pattern
  scratch: async ({}, use) => {
    const dir = await mkdtemp(join(tmpdir(), "notes-desktop-e2e-"));
    await use(dir);
    await Promise.all([...running].map((app) => app.close().catch(() => {})));
    running.clear();
    await rm(dir, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
  },
});

export { expect };

export async function library(scratch: string, name: string, files: Record<string, string>): Promise<string> {
  const root = join(scratch, name);
  for (const [path, body] of Object.entries(files)) {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), body);
  }
  return root;
}

/**
 * Launches the built app with its settings kept in the scratch folder. The command-line agents it finds
 * are those in `scratch/agents` (none unless a test installs one), never the ones on this computer, and
 * their settings are read from `scratch/home`.
 */
export async function launch(scratch: string, env: Record<string, string> = {}): Promise<{ app: ElectronApplication; page: Page }> {
  // A window the runner covers or leaves in the background still draws every frame, so motion can be filmed.
  const app = await electron.launch({
    args: [appDir, "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows"],
    env: { ...process.env, NOTES_DESKTOP_USER_DATA: join(scratch, "profile"), NOTES_DESKTOP_AGENT_PATH: join(scratch, "agents"), NOTES_DESKTOP_AGENT_HOME: join(scratch, "home"), ...env },
  });
  running.add(app);
  app.on("close", () => running.delete(app));
  const page = await app.firstWindow();
  // A window the runner leaves unfocused or hidden would otherwise get its frames throttled, and motion
  // tests would see springs crawl or jump.
  await app.evaluate(({ BrowserWindow }) =>
    BrowserWindow.getAllWindows().forEach((window) => window.webContents.setBackgroundThrottling(false)),
  );
  return { app, page };
}

/** The next folder picker answers with this folder instead of asking. */
export async function answerFolderPicker(app: ElectronApplication, folder: string) {
  await app.evaluate(({ dialog }, path) => {
    dialog.showOpenDialog = (async () => ({ canceled: false, filePaths: [path] })) as typeof dialog.showOpenDialog;
  }, folder);
}

/** Launches and opens `root` from the welcome page. */
export async function launchWith(scratch: string, root: string, env?: Record<string, string>) {
  const launched = await launch(scratch, env);
  await answerFolderPicker(launched.app, root);
  await launched.page.getByRole("button", { name: "选择笔记库…" }).click();
  return launched;
}

export interface Frame {
  top: number;
  /** The scale it is drawn at, whether set by `scale` or by a `transform`. */
  scale: number;
  blur: number;
  filter: string;
  opacity: number;
}

/** Films the element matching `selector` once per frame while `act` runs and `ms` after it. */
export async function film(page: Page, selector: string, act: () => Promise<unknown>, ms = 900): Promise<Frame[]> {
  await page.evaluate((selector) => {
    const w = window as unknown as { film: Frame[]; filming: boolean };
    w.film = [];
    w.filming = true;
    const frame = () => {
      if (!w.filming) return;
      const element = document.querySelector(selector);
      if (element) {
        const style = getComputedStyle(element);
        const blur = /blur\(([\d.]+)px\)/.exec(style.filter);
        w.film.push({
          top: element.getBoundingClientRect().top,
          scale: style.scale === "none" ? new DOMMatrix(style.transform).a : Number(style.scale),
          blur: blur ? Number(blur[1]) : 0,
          filter: style.filter,
          opacity: Number(style.opacity),
        });
      }
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  }, selector);
  await act();
  await page.waitForTimeout(ms);
  return page.evaluate(() => {
    const w = window as unknown as { film: Frame[]; filming: boolean };
    w.filming = false;
    return w.film;
  });
}

/** The `transition` the element matching `selector` declares for `property`: its duration in seconds and its curve. */
export const transitionOf = (page: Page, selector: string, property: string) =>
  page.evaluate(
    ({ selector, property }) => {
      const style = getComputedStyle(document.querySelector(selector)!);
      const pick = (list: string) => list.split(/,(?![^(]*\))/).map((item) => item.trim());
      const index = pick(style.transitionProperty).indexOf(property);
      if (index < 0) return null;
      return { duration: parseFloat(pick(style.transitionDuration)[index]!), curve: pick(style.transitionTimingFunction)[index]! };
    },
    { selector, property },
  );

/** The side panel's “资料库 | 空间” switch: on while the spaces show. */
export const sideSwitch = (page: Page) => page.getByRole("switch", { name: "空间", exact: true });

/** Shows `side` in the side panel, pressing the switch only if the other side shows. */
export async function showSide(page: Page, side: "资料库" | "空间") {
  const on = side === "空间";
  if ((await sideSwitch(page).getAttribute("aria-checked")) !== String(on)) await sideSwitch(page).click();
}

const isSettings = (window: Page) => window.url().endsWith("#settings");

/**
 * Opens 设置 with ⌘, / Ctrl+, in `page`, and answers it: the page of its own window (on `category`, if
 * given). Asked again while it is open, the same window comes to the front.
 */
export async function openSettings(app: ElectronApplication, page: Page, category?: string): Promise<Locator> {
  await page.keyboard.press("ControlOrMeta+Comma");
  await expect.poll(() => app.windows().some(isSettings)).toBe(true);
  const settings = app.windows().find(isSettings)!;
  const panel = settings.getByRole("main", { name: "设置" });
  await expect(panel).toBeVisible();
  if (category) await panel.getByRole("tab", { name: category }).click();
  return panel;
}

/** Closes the 设置 window with Esc, and waits until it has gone. */
export async function closeSettings(app: ElectronApplication, panel: Locator) {
  // The window closes on the key going down, so the press may find its page already gone.
  await panel
    .page()
    .keyboard.press("Escape")
    .catch(() => undefined);
  await expect.poll(() => app.windows().some(isSettings)).toBe(false);
}
