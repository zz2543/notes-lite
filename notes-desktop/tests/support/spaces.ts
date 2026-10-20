import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { spaceLibrary, spaceRequests, type SpaceReply } from "../../src/core";
import { fakeTrash, library } from "./library";

// The library the space request tests share, after the old SpaceAPITestCase.

/** 2026-10-18 (Sunday, ISO week 42) at noon, local time. */
export const today = new Date(2026, 9, 18, 12);

export const fitnessNote = `# 训练记录

## 卧推
| 日期 | 动作 | 重量 | 组数 |
|---|---|---|---|
| 2026-10-12 | 卧推 | 55 | 5 |
| 2026-10-14 | 卧推 | 57.5 |  |
| 2026-10-16 | 卧推 | 60 | 5 |

## 深蹲
| 日期 | 重量 |
|---|---|
| 2026-10-15 | 80 |`;

/** The old tests' library: a space “健身” over 健身/ and 日记/, and a note outside it. */
export async function fitnessLibrary(extra: Record<string, string> = {}) {
  const root = await library({
    "健身/训练记录.md": fitnessNote,
    "日记/2026-10.md": "| 日期 | 心情 |\n|---|---|\n| 2026-10-18 | 好 |\n",
    "别处/秘密.md": "不在范围内",
    ...extra,
  });
  await spaceLibrary(root).create({ name: "健身", icon: "🏋️", scope: { library: false, folders: ["健身", "日记"] } });
  const trash = await fakeTrash();
  let clock = today;
  const options = { now: () => clock, trash: trash.trash };
  return {
    root,
    trash,
    options,
    setClock: (date: Date) => (clock = date),
    read: (path: string) => readFile(join(root, path), "utf8"),
    /** Sends one request as the page would, for the space `space`. */
    call: (method: string, ...args: unknown[]) => spaceRequests(root, "健身", options).handle({ method, args }),
    callAs: (space: string, method: string, ...args: unknown[]) => spaceRequests(root, space, options).handle({ method, args }),
  };
}

export function result<T = unknown>(reply: SpaceReply): T {
  if (!reply.ok) throw new Error(`${reply.error.code}: ${reply.error.message}`);
  return reply.result as T;
}

export const code = (reply: SpaceReply) => (reply.ok ? "ok" : reply.error.code);

