import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const app = join(__dirname, "../..");
const shipped = (file: string) => readFile(join(app, "resources/licenses/katex", file), "utf8");

describe("bundled KaTeX", () => {
  it("ships with its MIT licence, copied verbatim from the katex package", async () => {
    expect(await shipped("LICENSE")).toContain("The MIT License");
    expect(await shipped("LICENSE")).toBe(await readFile(join(app, "node_modules/katex/LICENSE"), "utf8"));
  });

  it("ships the Apache 2.0 licence of the mhchem extension it loads, with the extension's copyright", async () => {
    expect(await shipped("mhchem-Apache-2.0.txt")).toMatch(/Apache License\s+Version 2\.0, January 2004[\s\S]*END OF TERMS AND CONDITIONS/);
    const source = await readFile(join(app, "node_modules/katex/contrib/mhchem/mhchem.js"), "utf8");
    expect(source).toContain("Licensed under the Apache License, Version 2.0");
    const readme = await shipped("README.txt");
    for (const copyright of source.match(/Copyright \(c\) [^\n]+/g)!) expect(readme).toContain(copyright);
    const { version } = JSON.parse(await readFile(join(app, "node_modules/katex/package.json"), "utf8")) as { version: string };
    expect(readme).toContain(`katex ${version}`);
  });
});
