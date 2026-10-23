import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { addEvent, emptyReply, hostAllowed, networkDecisions, networkHosts, networkState, referencedHosts, spaceLibrary } from "../../src/core";
import { library, scratchFolder } from "../support/library";

// 联网 (spaces-spec): a homepage reaches only the sites it names and the user allowed.
describe("联网", () => {
  it("reads the sites a homepage names, and those it loads from without saying", async () => {
    expect(networkHosts("https://API.example.com/v1, *.tiles.org，localhost:8080 不是网站!")).toEqual(["*.tiles.org", "api.example.com", "localhost:8080"]);
    expect(referencedHosts('<script src="https://cdn.jsdelivr.net/x.js"></script><img src=//img.cn/a.png><a href="https://link.only">x</a><script>fetch("https://api.x.com/q")</script>')).toEqual([
      "api.x.com",
      "cdn.jsdelivr.net",
      "img.cn",
    ]);
    const root = await library({
      ".notes/空间/天气.html": '<meta name="space-scope" content="*">\n<meta name="space-network" content="api.open-meteo.com">\n<meta name="space-network-reason" content="获取天气">\n<p>今天</p>',
      ".notes/空间/本地.html": '<meta name="space-scope" content="*">\n<p>只用笔记</p>',
    });
    const spaces = spaceLibrary(root);
    expect(await spaces.space("天气")).toMatchObject({ network: ["api.open-meteo.com"], networkReason: "获取天气" });
    expect(await spaces.space("本地")).toMatchObject({ network: [], networkReason: "" });
  });

  it("lets a request through only to an allowed site", () => {
    const hosts = ["api.example.com", "*.tiles.org", "localhost:8080"];
    expect(hostAllowed("https://api.example.com/v1?q=1", hosts)).toBe(true);
    expect(hostAllowed("https://evil.example.com/", hosts)).toBe(false);
    expect(hostAllowed("https://a.b.tiles.org/x.png", hosts)).toBe(true);
    expect(hostAllowed("wss://tiles.org/", hosts)).toBe(true);
    expect(hostAllowed("http://localhost:8080/", hosts)).toBe(true);
    expect(hostAllowed("http://localhost:9090/", hosts)).toBe(false);
    expect(hostAllowed("not a url", hosts)).toBe(false);
  });

  it("asks until the user answered for these very sites, and keeps the answer", async () => {
    expect(networkState(["a.com"], "", undefined).decision).toBe("ask");
    expect(networkState(["a.com"], "", { hosts: ["a.com"], allowed: true }).decision).toBe("allowed");
    expect(networkState(["a.com"], "", { hosts: ["a.com"], allowed: false }).decision).toBe("denied");
    expect(networkState(["a.com", "b.com"], "", { hosts: ["a.com"], allowed: true }).decision, "a new site asks again").toBe("ask");

    const file = join(await scratchFolder("notes-network-"), "space-network.json");
    const kept = networkDecisions(file);
    expect(await kept.get("k")).toBeUndefined();
    await kept.set("k", { hosts: ["a.com"], allowed: true });
    expect(await networkDecisions(file).get("k")).toEqual({ hosts: ["a.com"], allowed: true });
    await kept.set("k", null);
    expect(await kept.get("k")).toBeUndefined();
  });
});

describe("执行前询问", () => {
  it("shows the call the turn waits on until it is answered or the turn ends", () => {
    const asked = addEvent(emptyReply(), { kind: "approval", id: "p1", name: "Bash", activity: "running", detail: "ls", input: { command: "ls" } });
    expect(asked.asking).toEqual({ id: "p1", name: "Bash", activity: "running", detail: "ls" });
    expect(addEvent(asked, { kind: "approvalDone", id: "other", allowed: true }).asking).toBeDefined();
    expect(addEvent(asked, { kind: "approvalDone", id: "p1", allowed: true }).asking).toBeUndefined();
    expect(addEvent(asked, { kind: "end", changes: [] })).not.toHaveProperty("asking");
  });
});
