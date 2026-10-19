import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

/** App-wide settings, stored with the app and never inside a library. */
export interface Settings {
  libraryPath?: string;
}

export function settingsStore(directory: string) {
  const file = join(directory, "settings.json");
  return {
    async read(): Promise<Settings> {
      try {
        return JSON.parse(await readFile(file, "utf8")) as Settings;
      } catch {
        return {};
      }
    },
    async update(change: Partial<Settings>): Promise<void> {
      const next = { ...(await this.read()), ...change };
      await mkdir(dirname(file), { recursive: true });
      // Write beside the file and swap it in, so a crash never leaves half a settings file.
      await writeFile(`${file}.tmp`, JSON.stringify(next, null, 2));
      await rename(`${file}.tmp`, file);
    },
  };
}
