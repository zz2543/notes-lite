// 联网 (spaces-spec): a homepage reaches no website unless its file names the sites it needs
// (`<meta name="space-network" content="api.example.com">`, with why in `space-network-reason`) and
// the user allowed exactly those. The decisions are kept here, in the app's data folder, by the
// space's storage key (SpaceStorage), so a rename keeps them and a new space of the same name never
// inherits them. Naming other sites asks again.
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { serialized } from "./serialized";

/** The user's answer for the sites a homepage named. */
export interface NetworkDecision {
  hosts: string[];
  allowed: boolean;
}

/** What 联网 stands at for a homepage: the sites it names, why, and whether they were allowed. */
export interface SpaceNetwork {
  hosts: string[];
  reason: string;
  /** "ask" until the user answered for these very sites. */
  decision: "ask" | "allowed" | "denied";
}

const hostRe = /^(?:\*\.)?[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*(?::\d{1,5})?$/;

/** The sites a `space-network` value names: host names (a URL is cut to its host), lower case, each once, sorted. */
export function networkHosts(value: string | undefined): string[] {
  const hosts = (value ?? "")
    .split(/[\s,，、]+/)
    .map((item) => item.trim().toLowerCase().replace(/^[a-z]+:\/\//, "").replace(/[/?#].*$/, ""))
    .filter((host) => host !== "" && hostRe.test(host));
  return [...new Set(hosts)].sort();
}

/**
 * The sites a page reaches without saying so: scripts, styles, images and frames it loads from the
 * web, and `fetch` of a written-out address. So an older homepage (a library from a CDN, say) asks too.
 */
export function referencedHosts(html: string): string[] {
  const found: string[] = [];
  for (const match of html.matchAll(/<(?:script|link|img|iframe|source|video|audio)\b[^>]*?\s(?:src|href)\s*=\s*["']?(?:https?:)?\/\/([^/"'\s>?#]+)/gi)) found.push(match[1]!);
  for (const match of html.matchAll(/\b(?:fetch|EventSource|WebSocket)\(\s*["'`](?:https?|wss?):\/\/([^/"'`\s?#]+)/g)) found.push(match[1]!);
  return networkHosts(found.join(" "));
}

/** Whether `url` goes to one of `hosts`: the host itself or, for `*.example.com`, any name under it. */
export function hostAllowed(url: string, hosts: readonly string[]): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  const host = parsed.hostname.toLowerCase();
  const withPort = parsed.port ? `${host}:${parsed.port}` : host;
  return hosts.some((entry) => {
    if (entry.startsWith("*.")) {
      const base = entry.slice(2).split(":")[0]!;
      return host === base || host.endsWith(`.${base}`);
    }
    return entry.includes(":") ? entry === withPort : entry === host;
  });
}

const same = (a: readonly string[], b: readonly string[]) => a.length === b.length && a.every((host, i) => host === b[i]);

/** Where 联网 stands, given the sites the file names now and the decision kept for the space. */
export function networkState(hosts: string[], reason: string, kept: NetworkDecision | undefined): SpaceNetwork {
  const decision = kept && same(kept.hosts, hosts) ? (kept.allowed ? "allowed" : "denied") : "ask";
  return { hosts, reason, decision };
}

export interface NetworkDecisions {
  get(key: string): Promise<NetworkDecision | undefined>;
  /** Keeps the answer for these sites; null forgets it, so the homepage asks again. */
  set(key: string, decision: NetworkDecision | null): Promise<void>;
}

export function networkDecisions(file: string): NetworkDecisions {
  const read = async (): Promise<Record<string, NetworkDecision>> => {
    try {
      const kept: unknown = JSON.parse(await readFile(file, "utf8"));
      return typeof kept === "object" && kept !== null ? (kept as Record<string, NetworkDecision>) : {};
    } catch {
      return {};
    }
  };
  return {
    get: async (key) => {
      const kept = (await read())[key];
      return kept && Array.isArray(kept.hosts) && typeof kept.allowed === "boolean" ? { hosts: kept.hosts.map(String), allowed: kept.allowed } : undefined;
    },
    set: (key, decision) =>
      serialized(`space-network:${file}`, async () => {
        const all = await read();
        if (decision) all[key] = { hosts: [...decision.hosts], allowed: decision.allowed };
        else delete all[key];
        await mkdir(dirname(file), { recursive: true });
        await writeFile(`${file}.tmp`, JSON.stringify(all));
        await rename(`${file}.tmp`, file);
      }),
  };
}
