import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import type { Preferences } from "../shared/preferences";

/** App-wide settings, stored with the app and never inside a library. */
export interface Settings {
  libraryPath?: string;
  /** What the settings panel shows; read through `readPreferences`, since it may be partial or old. */
  preferences?: Partial<Preferences>;
}

export function settingsStore(directory: string) {
  const file = join(directory, "settings.json");
  // Updates run one after another, so quick changes never write the file at the same time.
  let queue: Promise<unknown> = Promise.resolve();
  return {
    async read(): Promise<Settings> {
      try {
        return JSON.parse(await readFile(file, "utf8")) as Settings;
      } catch {
        return {};
      }
    },
    update(change: Partial<Settings>): Promise<void> {
      const write = async () => {
        const next = { ...(await this.read()), ...change };
        await mkdir(dirname(file), { recursive: true });
        // Write beside the file and swap it in, so a crash never leaves half a settings file.
        await writeFile(`${file}.tmp`, JSON.stringify(next, null, 2));
        await rename(`${file}.tmp`, file);
      };
      const done = queue.then(write, write);
      queue = done.catch(() => {});
      return done;
    },
  };
}
