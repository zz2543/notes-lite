import { _electron as electron, test as base, type ElectronApplication, type Page } from "@playwright/test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

const appDir = join(__dirname, "../..");

/** Each test gets a scratch folder for its libraries and the app's settings. */
export const test = base.extend<{ scratch: string }>({
  // eslint-disable-next-line no-empty-pattern
  scratch: async ({}, use) => {
    const dir = await mkdtemp(join(tmpdir(), "notes-desktop-e2e-"));
    await use(dir);
    await rm(dir, { recursive: true, force: true });
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

/** Launches the built app with its settings kept in the scratch folder. */
export async function launch(scratch: string): Promise<{ app: ElectronApplication; page: Page }> {
  const app = await electron.launch({ args: [appDir], env: { ...process.env, NOTES_DESKTOP_USER_DATA: join(scratch, "profile") } });
  return { app, page: await app.firstWindow() };
}

/** The next folder picker answers with this folder instead of asking. */
export async function answerFolderPicker(app: ElectronApplication, folder: string) {
  await app.evaluate(({ dialog }, path) => {
    dialog.showOpenDialog = (async () => ({ canceled: false, filePaths: [path] })) as typeof dialog.showOpenDialog;
  }, folder);
}

/** Launches and opens `root` from the welcome page. */
export async function launchWith(scratch: string, root: string) {
  const launched = await launch(scratch);
  await answerFolderPicker(launched.app, root);
  await launched.page.getByRole("button", { name: "选择笔记库…" }).click();
  return launched;
}
