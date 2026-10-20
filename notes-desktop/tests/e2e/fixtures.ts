import { _electron as electron, test as base, type ElectronApplication, type Page } from "@playwright/test";
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

export { expect } from "@playwright/test";

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
 * are those in `scratch/agents` (none unless a test installs one), never the ones on this computer.
 */
export async function launch(scratch: string, env: Record<string, string> = {}): Promise<{ app: ElectronApplication; page: Page }> {
  // A window the runner covers or leaves in the background still draws every frame, so motion can be filmed.
  const app = await electron.launch({
    args: [appDir, "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows"],
    env: { ...process.env, NOTES_DESKTOP_USER_DATA: join(scratch, "profile"), NOTES_DESKTOP_AGENT_PATH: join(scratch, "agents"), ...env },
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
