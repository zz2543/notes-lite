import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const app = join(__dirname, "../..");

describe("bundled fonts", () => {
  it("ship with their OFL licences, copied verbatim from the packages the fonts come from", async () => {
    for (const [file, pkg] of [
      ["NotoSerifSC-OFL.txt", "@fontsource/noto-serif-sc"],
      ["SourceSerif4-OFL.txt", "@fontsource-variable/source-serif-4"],
    ]) {
      const shipped = await readFile(join(app, "resources/licenses/fonts", file!), "utf8");
      expect(shipped).toContain("SIL Open Font License, Version 1.1");
      expect(shipped).toBe(await readFile(join(app, "node_modules", pkg!, "LICENSE"), "utf8"));
    }
  });

  it("are packaged with the licence folder beside the app", async () => {
    const builder = await readFile(join(app, "electron-builder.yml"), "utf8");
    expect(builder).toMatch(/extraResources:\s*\n\s*- from: resources\/licenses\s*\n\s*to: licenses/);
  });
});
