// Links between notes, as the old NotesCore `References` finds them. Pure (no Node APIs).

/** A local link's target inside a note: `[[目标#小节|别名]]`, `[文字](目标.md)`, `![图](附件/图.png)`. */
export interface LinkTarget {
  /** Where the target starts and ends in the note's text; an anchor or alias after it is not part of it. */
  from: number;
  to: number;
  /** The target as written, before any `#` or `|`. */
  target: string;
  wiki: boolean;
}

const wikiLink = /\[\[([^\]\n]+)\]\]/dg;
const markdownLink = /!?\[[^\]\n]*\]\(([^)\n]+)\)/dg;
const inlineCode = /`([^`]+)`/dg;

/** The fence a line opens or closes a code block with (``` or ~~~, at least three), if any. */
function fenceOf(line: string): string | undefined {
  const match = /^ {0,3}(`{3,}|~{3,})(.*)$/.exec(line);
  if (!match) return undefined;
  const [, fence, info] = match;
  // A backtick fence's info string may not contain backticks.
  if (fence!.startsWith("`") && info!.includes("`")) return undefined;
  return fence;
}

type Block = { kind: "text" } | { kind: "code"; fence: string } | { kind: "math" } | { kind: "frontmatter" };

/**
 * Ranges whose text is literal, so a link written there is an example rather than a link: fenced
 * code, `$$` math blocks, front matter and inline code.
 */
function literalRanges(text: string): Array<[number, number]> {
  const ranges: Array<[number, number]> = [];
  let block: Block = { kind: "text" };
  let offset = 0;
  text.split("\n").forEach((raw, index) => {
    const start = offset;
    offset += raw.length + 1;
    // A CRLF note's lines end in "\r", which is no part of a fence.
    const line = raw.endsWith("\r") ? raw.slice(0, -1) : raw;
    const literal = () => ranges.push([start, start + raw.length]);
    switch (block.kind) {
      case "text": {
        const fence = fenceOf(line);
        if (index === 0 && line === "---") block = { kind: "frontmatter" };
        else if (fence) block = { kind: "code", fence };
        else if (line.trim() === "$$") block = { kind: "math" };
        else {
          for (const match of raw.matchAll(inlineCode)) {
            const [from, to] = match.indices![1]!;
            ranges.push([start + from, start + to]);
          }
          return;
        }
        return literal();
      }
      case "code": {
        const fence = fenceOf(line);
        if (fence && fence[0] === block.fence[0] && fence.length >= block.fence.length && line.trim() === fence) block = { kind: "text" };
        return literal();
      }
      case "math":
        if (line.trim() === "$$") block = { kind: "text" };
        return literal();
      case "frontmatter":
        if (line === "---" || line === "...") block = { kind: "text" };
        return literal();
    }
  });
  return ranges;
}

/** Every local link in a note, leaving out code examples and web, mail and data links. */
export function linkTargets(text: string): LinkTarget[] {
  const literal = literalRanges(text);
  const links: LinkTarget[] = [];
  for (const [pattern, wiki] of [[wikiLink, true], [markdownLink, false]] as const) {
    for (const match of text.matchAll(pattern)) {
      const [from, end] = match.indices![1]!;
      if (literal.some(([a, b]) => a < end && from < b)) continue;
      if (links.some((link) => link.from < end && from < link.to)) continue;
      const target = match[1]!.split("|")[0]!.split("#")[0]!;
      if (!target || target.includes("://") || target.startsWith("mailto:") || target.startsWith("data:")) continue;
      links.push({ from, to: from + target.length, target, wiki });
    }
  }
  return links.sort((a, b) => a.from - b.from);
}

/** `text` with the given link targets replaced; anchors, aliases and everything else stay as they were. */
export function replaceTargets(text: string, replacements: ReadonlyArray<{ link: LinkTarget; target: string }>): string {
  let output = "";
  let last = 0;
  for (const { link, target } of [...replacements].sort((a, b) => a.link.from - b.link.from)) {
    output += text.slice(last, link.from) + target;
    last = link.to;
  }
  return output + text.slice(last);
}
