import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { spaceStorage } from "../../src/core";
import { scratchFolder } from "../support/library";

// spaces-spec #51: a homepage's own storage (the tab or period last chosen) is kept per space, and
// stays with the space when it is renamed.

describe("空间主页的本地存储", () => {
  it("keeps one key per library and space, the same each time it is asked, after a restart too", async () => {
    const file = join(await scratchFolder(), "space-storage.json");
    const storage = spaceStorage(file);
    const fitness = await storage.key("/库", "健身");

    expect(await storage.key("/库", "健身")).toBe(fitness);
    expect(await spaceStorage(file).key("/库", "健身")).toBe(fitness);
    expect(await storage.key("/库", "雅思")).not.toBe(fitness);
    expect(await storage.key("/别的库", "健身")).not.toBe(fitness);
  });

  it("goes with a renamed space, and a new space under the old name starts empty", async () => {
    const file = join(await scratchFolder(), "space-storage.json");
    const storage = spaceStorage(file);
    const fitness = await storage.key("/库", "健身");

    await storage.renamed("/库", "健身", "力量训练");

    expect(await storage.key("/库", "力量训练")).toBe(fitness);
    expect(await spaceStorage(file).key("/库", "力量训练"), "remembered after a restart").toBe(fitness);
    expect(await storage.key("/库", "健身")).not.toBe(fitness);
  });

  it("does not hand a deleted space's storage to a new space of the same name", async () => {
    const storage = spaceStorage(join(await scratchFolder(), "space-storage.json"));
    const fitness = await storage.key("/库", "健身");

    await storage.deleted("/库", "健身");

    expect(await storage.key("/库", "健身")).not.toBe(fitness);
  });
});
