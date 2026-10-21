// Markdown structure, ported from the old NotesCore. This module is pure (no Node APIs), so the
// renderer may bundle it directly for per-keystroke work such as 字数.

/** What a line is. Fenced code and front matter span lines: see `literalBlocks`. */
export type BlockType =
  | "h1"
  | "h2"
  | "h3"
  | "h4"
  | "h5"
  | "h6"
  | "task"
  | "li"
  | "ol"
  | "quote"
  | "hr"
  | "empty"
  | "p"
  | "table"
  /** A ``` or ~~~ line that opens or closes a code block, or the `$$` around a math block. */
  | "fence"
  /** A line inside a fenced code block or a `$$` math block. */
  | "code"
  /** A line of YAML front matter, delimiters included. */
  | "frontmatter";

/** Part of a line, as UTF-16 offsets into it (what both JavaScript strings and the editor count). */
export interface Range {
  from: number;
  to: number;
}

export type SpanKind = "bold" | "italic" | "code" | "strike" | "highlight" | "wikilink" | "link" | "embed" | "image" | "tag" | "math" | "footnote";

export interface InlineSpan {
  kind: SpanKind;
  /** What the span names: a link's target, an image's URL, a tag, the TeX of inline math, a footnote label. */
  value?: string;
  /** The visible content. */
  content: Range;
  /** Syntax characters, dimmed while the line is being edited and hidden otherwise. */
  marks: Range[];
}

export interface LineMarkup {
  type: BlockType;
  /** The block marker such as "# ", "\t- [ ] ", "1. ", "> " (empty when absent), indentation included. */
  prefix: Range;
  spans: InlineSpan[];
  /** Nesting of a list item (0 at top level) or of a quote ("> > " is 1). */
  depth: number;
  /** `> [!note] Title`: the callout kind, lowercased. */
  callout?: string;
  /** `> [!note]-` starts folded (true), `> [!note]+` open (false); absent when it can't fold. */
  calloutFolded?: boolean;
  /** `[^1]: text` defines footnote "1"; the prefix covers "[^1]: ". */
  footnoteLabel?: string;
}

const headingRe = /^(#{1,6}) /;
const quoteRe = /^(?:> ?)+/;
const listRe = /^([ \t]*)([-*+] \[[ xX]\] |[-*+] |\d{1,9}[.)] )/;

/** Tabs count one level each; spaces count one level per two (four-space indents read as two). */
function indentLevel(whitespace: string): number {
  const tabs = whitespace.split("\t").length - 1;
  return tabs + Math.floor((whitespace.length - tabs) / 2);
}

function parsePrefix(line: string): { type: BlockType; length: number; depth: number } {
  const first = line[0];
  if (first === undefined) return { type: "empty", length: 0, depth: 0 };
  if (first === "#") {
    const m = headingRe.exec(line);
    if (m) return { type: `h${m[1]!.length}` as BlockType, length: m[0].length, depth: 0 };
  }
  if (first === ">") {
    const m = quoteRe.exec(line);
    if (m) return { type: "quote", length: m[0].length, depth: m[0].split(">").length - 2 };
  }
  // Lists start with indentation, a bullet or a digit; everything else skips the expression.
  if (/[ \t*+\-0-9]/.test(first)) {
    const m = listRe.exec(line);
    if (m) {
      const marker = m[2]!;
      const type = marker.includes("[") ? "task" : /\d/.test(marker[0]!) ? "ol" : "li";
      return { type, length: m[0].length, depth: indentLevel(m[1]!) };
    }
  }
  return { type: "p", length: 0, depth: 0 };
}

/** Length of the block marker a line starts with: heading, quote, list or task item, else 0. */
export function blockPrefixLength(line: string): number {
  return parsePrefix(line).length;
}

function isRule(line: string): boolean {
  const s = line.replace(/^[ \t]+|[ \t]+$/g, "");
  const c = s[0];
  if (s.length < 3 || (c !== "-" && c !== "*" && c !== "_")) return false;
  return [...s].every((x) => x === c || x === " ") && s.split(c).length - 1 >= 3;
}

/** The type of a line on its own, as if it were outside any literal block. */
export function blockType(line: string): BlockType {
  if (line === "") return "empty";
  if (isFence(line) !== null) return "fence";
  if (isRule(line)) return "hr";
  const prefix = parsePrefix(line);
  if (prefix.type !== "p") return prefix.type;
  if (line.startsWith("|")) return "table";
  return line.trim() === "" ? "empty" : "p";
}

const calloutRe = /^\[!([A-Za-z-]+)\]([+-]?)/;
const footnoteDefRe = /^\[\^([^\]\s]+)\]:[ \t]?/;
const codeRe = /`([^`]+)`/dg;
/** `$…$` as Obsidian and Pandoc read it: no space inside either `$`, and no digit right after the
 *  closing one, so prices ("$5 and $6") stay text. */
const mathRe = /(?<![\\$0-9A-Za-z])\$(?![\s$])((?:\\.|[^$\\])+?)(?<![\s\\])\$(?![0-9$])/dg;
const footnoteRe = /\[\^([^\]\s]+)\]/dg;
const embedRe = /!\[\[(.+?)\]\]/dg;
const imageRe = /!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/dg;
const wikiRe = /\[\[(.+?)\]\]/dg;
const linkRe = /\[([^\]\[]+)\]\(([^)]+)\)/dg;
const urlRe = /https?:\/\/[^\s<>()（）\[\]，。、；：“”]+/dg;
const tagRe = /(?<![\p{L}\p{N}_&#\/\-])#([\p{L}\p{N}_\/\-]*[\p{L}_][\p{L}\p{N}_\/\-]*)/dgu;
const boldRe = /\*\*(.+?)\*\*|__(.+?)__/dg;
const italicRe = /(?<!\*)\*([^*\s](?:[^*]*[^*\s])?)\*(?!\*)|(?<![_\p{L}\p{N}])_([^_\s](?:[^_]*[^_\s])?)_(?![_\p{L}\p{N}])/dgu;
const strikeRe = /~~(.+?)~~/dg;
const highlightRe = /==(.+?)==/dg;

const overlaps = (a: Range, b: Range) => a.from < b.to && b.from < a.to;

/** Inline markup of one line whose type is known (from `blockType`, or `literalBlocks` for literal lines). */
export function parseLine(line: string, type: BlockType = blockType(line)): LineMarkup {
  if (type === "fence" || type === "code" || type === "frontmatter" || type === "hr" || type === "empty" || type === "table") {
    return { type, prefix: { from: 0, to: 0 }, spans: [], depth: 0 };
  }
  const pre = parsePrefix(line);
  const markup: LineMarkup = { type, prefix: { from: 0, to: pre.type === type ? pre.length : 0 }, spans: [], depth: pre.depth };
  const callout = type === "quote" && line[markup.prefix.to] === "[" ? calloutRe.exec(line.slice(markup.prefix.to)) : null;
  if (callout) {
    markup.callout = callout[1]!.toLowerCase();
    if (callout[2]) markup.calloutFolded = callout[2] === "-";
    markup.prefix.to += callout[0].length;
    // One space after the marker goes with it.
    if (line[markup.prefix.to] === " ") markup.prefix.to += 1;
  }
  const definition = type === "p" && markup.prefix.to === 0 && line.startsWith("[^") ? footnoteDefRe.exec(line) : null;
  if (definition) {
    markup.footnoteLabel = definition[1];
    markup.prefix.to = definition[0].length;
  }
  const start = markup.prefix.to;
  const body = line.slice(start);
  if (body === "") return markup;

  // Matches within the body, in line offsets: the whole match and each group (undefined when it took no part).
  const matches = (re: RegExp) =>
    [...body.matchAll(re)].map((m) => m.indices!.map((r) => r && { from: r[0] + start, to: r[1] + start }));
  const taken: Range[] = [];
  const free = (r: Range) => !taken.some((t) => overlaps(t, r));
  const edges = (r: Range, open: number, close: number): Range[] => [
    { from: r.from, to: r.from + open },
    { from: r.to - close, to: r.to },
  ];

  if (body.includes("`")) {
    for (const [whole, content] of matches(codeRe)) {
      taken.push(whole!);
      markup.spans.push({ kind: "code", content: content!, marks: edges(whole!, 1, 1) });
    }
  }
  const add = (kind: SpanKind, value: string, content: Range, marks: Range[], whole: Range) => {
    taken.push(whole);
    markup.spans.push({ kind, value, content, marks });
  };
  const slice = (r: Range) => line.slice(r.from, r.to);
  // Math before links and emphasis: `_` and `*` inside TeX are not Markdown.
  if (body.includes("$")) {
    for (const [whole, tex] of matches(mathRe)) if (free(whole!)) add("math", slice(tex!), tex!, edges(whole!, 1, 1), whole!);
  }
  const bracket = body.includes("[");
  if (bracket && body.includes("^")) {
    for (const [whole, label] of matches(footnoteRe)) if (free(whole!)) add("footnote", slice(label!), label!, edges(whole!, 2, 1), whole!);
  }
  if (bracket && body.includes("!")) {
    for (const [whole, target] of matches(embedRe)) if (free(whole!)) add("embed", slice(target!), target!, edges(whole!, 3, 2), whole!);
    // The alt text stays visible; everything else is syntax.
    for (const [whole, alt, url] of matches(imageRe)) {
      if (free(whole!)) add("image", slice(url!), alt!, [{ from: whole!.from, to: whole!.from + 2 }, { from: alt!.to, to: whole!.to }], whole!);
    }
  }
  if (bracket) {
    for (const [whole, target] of matches(wikiRe)) if (free(whole!)) add("wikilink", slice(target!), target!, edges(whole!, 2, 2), whole!);
  }
  if (bracket && body.includes("(")) {
    for (const [whole, label, url] of matches(linkRe)) {
      if (free(whole!)) add("link", slice(url!), label!, [{ from: whole!.from, to: whole!.from + 1 }, { from: label!.to, to: whole!.to }], whole!);
    }
  }
  if (body.includes("http://") || body.includes("https://")) {
    for (const [whole] of matches(urlRe)) if (free(whole!)) add("link", slice(whole!), whole!, [], whole!);
  }
  // Emphasis may nest in each other, but not inside the spans above.
  const locked = [...taken];
  const markers: Range[] = [];
  const emphasis = (re: RegExp, kind: SpanKind, width: number, triggers: string) => {
    if (![...triggers].some((t) => body.includes(t))) return;
    for (const [whole, ...groups] of matches(re)) {
      if (locked.some((t) => overlaps(t, whole!))) continue;
      const marks = edges(whole!, width, width);
      if (marks.some((m) => markers.some((k) => overlaps(k, m)))) continue;
      markers.push(...marks);
      markup.spans.push({ kind, content: groups.find(Boolean) ?? whole!, marks });
    }
  };
  emphasis(boldRe, "bold", 2, "*_");
  emphasis(strikeRe, "strike", 2, "~");
  emphasis(highlightRe, "highlight", 2, "=");
  emphasis(italicRe, "italic", 1, "*_");
  taken.push(...markers);
  if (body.includes("#")) {
    for (const [whole, name] of matches(tagRe)) {
      if (free(whole!)) markup.spans.push({ kind: "tag", value: slice(name!), content: whole!, marks: [] });
    }
  }
  return markup;
}

/** The fence a line opens or closes a code block with ("```", "~~~~"…), or null. */
export function isFence(line: string): string | null {
  const indent = line.length - line.replace(/^ +/, "").length;
  const rest = line.slice(indent);
  const char = rest[0];
  if (indent > 3 || (char !== "`" && char !== "~")) return null;
  const run = /^(`+|~+)/.exec(rest)![0];
  if (run.length < 3) return null;
  // A backtick fence's info string may not contain backticks.
  if (char === "`" && rest.slice(run.length).includes("`")) return null;
  return run;
}

/** The language named after an opening fence ("```mermaid" → "mermaid"), lowercased; "" when none. */
export function fenceInfo(line: string): string {
  const fence = isFence(line);
  if (fence === null) return "";
  const word = line.trimStart().slice(fence.length).trim().split(/\s/)[0] ?? "";
  return word.replace(/^[{}.]+|[{}.]+$/g, "").toLowerCase();
}

/** Lines shown as they are, with no inline markup: fenced code, a `$$` math block, YAML front matter. */
export interface LiteralBlock {
  kind: "code" | "math" | "frontmatter";
  /** Line indices (0-based) of the opening and closing lines, delimiters included. */
  first: number;
  last: number;
  /** False when the block runs to the end of the note without its closing line. */
  closed: boolean;
  /** A code block's language, from its opening fence; "" otherwise. */
  language: string;
}

/** The literal blocks of a note, given its lines in order. */
export function literalBlocks(lines: Iterable<string>): LiteralBlock[] {
  const blocks: LiteralBlock[] = [];
  let open: LiteralBlock | null = null;
  let openFence = "";
  let i = -1;
  for (const line of lines) {
    i += 1;
    if (open) {
      open.last = i;
      if (closes(open.kind, openFence, line)) {
        open.closed = true;
        open = null;
      }
      continue;
    }
    const fence = isFence(line);
    const kind = i === 0 && line === "---" ? "frontmatter" : fence ? "code" : line.trim() === "$$" ? "math" : null;
    if (!kind) continue;
    open = { kind, first: i, last: i, closed: false, language: kind === "code" ? fenceInfo(line) : "" };
    openFence = fence ?? "";
    blocks.push(open);
  }
  return blocks;
}

function closes(kind: LiteralBlock["kind"], open: string, line: string): boolean {
  if (kind === "frontmatter") return line === "---" || line === "...";
  if (kind === "math") return line.trim() === "$$";
  const fence = isFence(line);
  return fence !== null && fence[0] === open[0] && fence.length >= open.length && line.trim().length === fence.length;
}

/** The TeX of a formula written on one line as `$$…$$`; null for anything else. */
export function displayMath(line: string): string | null {
  // Indented up to three spaces, as other blocks may be; four make it code.
  if (/^ {0,3}\S/.exec(line) === null) return null;
  const s = line.trim();
  if (s.length <= 4 || !s.startsWith("$$") || !s.endsWith("$$")) return null;
  const inner = s.slice(2, -2);
  return inner.includes("$$") || inner.trim() === "" ? null : inner;
}

export type TableAlign = "left" | "center" | "right";

export interface TableCell {
  /** The cell's Markdown, trimmed, with `\|` unescaped. */
  text: string;
  /** Where the trimmed cell sits in its line; null for a cell the row leaves out. */
  range: Range | null;
}

/** A GitHub-style pipe table: a header row, a `|---|:-:|` separator, then the body rows. */
export interface MarkdownTable {
  header: TableCell[];
  aligns: TableAlign[];
  rows: TableCell[][];
}

/** `| --- | :---: | ---: |`, with or without spaces around the cells. */
export function isTableSeparator(line: string): boolean {
  const t = line.trim();
  if (!t.startsWith("|") || !t.includes("-")) return false;
  const cells = splitRow(t).map((c) => c.text.trim());
  return cells.length > 0 && cells.every((c) => /^:?-+:?$/.test(c));
}

/** The raw cells of a row. Pipes inside inline code, `[[links|alias]]` or escaped as `\|` don't split. */
function splitRow(line: string): { text: string; from: number }[] {
  let i = 0;
  while (line[i] === " ") i++;
  if (line[i] !== "|") return [];
  i++;
  const out: { text: string; from: number }[] = [];
  let start = i;
  let code = false;
  let wiki = 0;
  while (i < line.length) {
    const c = line[i];
    if (c === "\\" && i + 1 < line.length) {
      i += 2;
      continue;
    }
    if (c === "`") code = !code;
    else if (!code && c === "[" && line[i + 1] === "[") {
      wiki++;
      i += 2;
      continue;
    } else if (!code && wiki > 0 && c === "]" && line[i + 1] === "]") {
      wiki--;
      i += 2;
      continue;
    } else if (c === "|" && !code && wiki === 0) {
      out.push({ text: line.slice(start, i), from: start });
      start = i + 1;
    }
    i++;
  }
  // A trailing cell only counts when the row doesn't end with a pipe.
  if (line.slice(start).trim() !== "") out.push({ text: line.slice(start), from: start });
  return out;
}

/** The cells of one row, trimmed, each with where it sits in the line. */
export function tableRow(line: string): TableCell[] {
  return splitRow(line).map(({ text, from }) => {
    const lead = text.length - text.replace(/^[ \t]+/, "").length;
    const trimmed = text.replace(/^[ \t]+|[ \t]+$/g, "");
    return { text: trimmed.replaceAll("\\|", "|"), range: { from: from + lead, to: from + lead + trimmed.length } };
  });
}

/** Reads a table from its lines (header, separator, rows); null when the second line isn't a separator.
 *  Every row has as many cells as the wider of the header and the separator. */
export function parseTable(lines: readonly string[]): MarkdownTable | null {
  if (lines.length < 2 || !isTableSeparator(lines[1]!)) return null;
  const header = tableRow(lines[0]!);
  const aligns = tableRow(lines[1]!).map(({ text }): TableAlign =>
    text.length > 1 && text.startsWith(":") && text.endsWith(":") ? "center" : text.endsWith(":") ? "right" : "left",
  );
  const columns = Math.max(header.length, aligns.length);
  if (columns === 0) return null;
  const pad = (row: TableCell[]) => Array.from({ length: columns }, (_, i) => row[i] ?? { text: "", range: null });
  return {
    header: pad(header),
    aligns: Array.from({ length: columns }, (_, i) => aligns[i] ?? "left"),
    rows: lines.slice(2).map((line) => pad(tableRow(line))),
  };
}

/** A block drawn as a whole while the caret is elsewhere: a table, a formula or an image on its own lines. */
export interface RenderedBlock {
  kind: "table" | "math" | "image";
  /** Line indices (0-based) of its first and last lines. */
  first: number;
  last: number;
  /** A formula's TeX; "" for a table or an image. */
  tex: string;
  /** An image's link, as `linkOf` gives it. */
  image?: Link;
}

/** A note's lines read one at a time, so an editor needn't copy them all out to have them looked at. */
export interface LineSource {
  readonly length: number;
  /** The line at a 0-based index. */
  line(index: number): string;
}

/** The tables, closed `$$` blocks and one-line `$$…$$` formulas of a note, outside code and front matter. */
export function renderedBlocks(source: readonly string[] | LineSource, literal?: readonly LiteralBlock[]): RenderedBlock[] {
  const lines: LineSource = "line" in source ? source : { length: source.length, line: (i) => source[i]! };
  literal ??= literalBlocks("line" in source ? Array.from({ length: lines.length }, (_, i) => lines.line(i)) : source);
  const out: RenderedBlock[] = [];
  let next = 0;
  for (let i = 0; i < lines.length; i++) {
    const block = literal[next];
    if (block && i >= block.first) {
      if (block.kind === "math" && block.closed) {
        const tex = Array.from({ length: block.last - block.first - 1 }, (_, j) => lines.line(block.first + 1 + j));
        out.push({ kind: "math", first: block.first, last: block.last, tex: tex.join("\n") });
      }
      i = block.last;
      next++;
      continue;
    }
    const line = lines.line(i);
    const tex = line.includes("$$") ? displayMath(line) : null;
    const image = tex === null && line.includes("![") ? embeddedImage(line) : null;
    if (tex !== null) {
      out.push({ kind: "math", first: i, last: i, tex });
    } else if (image) {
      out.push({ kind: "image", first: i, last: i, tex: "", image });
    } else if (line.startsWith("|") && i + 1 < lines.length && lines.line(i + 1).startsWith("|") && isTableSeparator(lines.line(i + 1))) {
      let last = i + 1;
      while (last + 1 < lines.length && lines.line(last + 1).startsWith("|")) last++;
      out.push({ kind: "table", first: i, last, tex: "" });
      i = last;
    }
  }
  return out;
}

// 笔记链接、图片与附件 (ticket 13).

/** What a link span leads to, as the library follows it: `[[…]]` and `![[…]]` by title, the rest by path. */
export interface Link {
  target: string;
  wiki: boolean;
}

/** The link a span is, or null for one that isn't a link: a Markdown link's destination without its
 *  "title" or <angle brackets>, a wiki link's target with its #anchor and |alias left for the library. */
export function linkOf(span: InlineSpan): Link | null {
  const value = span.value ?? "";
  if (span.kind === "wikilink" || span.kind === "embed") return { target: value, wiki: true };
  if (span.kind !== "link" && span.kind !== "image") return null;
  const trimmed = value.trim();
  const close = trimmed.indexOf(">");
  const target = trimmed.startsWith("<") ? trimmed.slice(1, close < 0 ? undefined : close) : trimmed.split(/\s/)[0]!;
  return { target, wiki: false };
}

/** The part of a span shown when typeset, and its syntax: `[[页|别名]]` shows only 别名. */
export function shownSpan(span: InlineSpan): Pick<InlineSpan, "content" | "marks"> {
  const bar = span.kind === "wikilink" ? (span.value ?? "").indexOf("|") : -1;
  if (bar < 0) return span;
  const { from, to } = span.content;
  return { content: { from: from + bar + 1, to }, marks: [...span.marks, { from, to: from + bar + 1 }] };
}

/** The file or note a link's target names: without a wiki link's |alias or any #anchor. */
export function linkPath(target: string): string {
  return target.split("|")[0]!.split("#")[0]!.trim();
}

/** A target that is an address outside the library (https:, mailto:, …), not a path in it. */
export function isAddress(target: string): boolean {
  return /^[a-z][a-z0-9+.-]*:/i.test(target.trim());
}

/** Files imported as images (`![…](…)`) and drawn in the note when the page can show them. */
export const imageName = /\.(png|jpe?g|gif|webp|svg|bmp|avif|heic|heif|tiff?)$/i;

/** The image a line shows when it holds nothing else: `![…](path)` or `![[file.png]]`. Web addresses are
 *  left as links: the page loads nothing from outside the app. */
export function embeddedImage(line: string): Link | null {
  const markup = parseLine(line, "p");
  const text = line.trim();
  const span = markup.spans.find((s) => s.kind === "image" || s.kind === "embed");
  if (!span || markup.spans.length !== 1) return null;
  const whole = span.kind === "image" ? line.slice(span.marks[0]!.from, span.marks[1]!.to) : line.slice(span.content.from - 3, span.content.to + 2);
  if (whole !== text) return null;
  const link = linkOf(span)!;
  const path = linkPath(link.target);
  return imageName.test(path) && !isAddress(path) ? link : null;
}

/**
 * What to insert at `offset` in `line` so that each snippet (an imported image or attachment) stands on a
 * line of its own, and where the caret goes after it: at the end of the last one.
 */
export function snippetInsertion(line: string, offset: number, snippets: readonly string[]): { text: string; caret: number } {
  const before = line.slice(0, offset).trim() ? "\n" : "";
  const after = line.slice(offset).trim() ? "\n" : "";
  const body = snippets.join("\n");
  return { text: before + body + after, caret: before.length + body.length };
}

/** The name a pasted file is imported under: an image off the clipboard, which Chromium calls
 *  "image.png", becomes 图片-<8 hex>.png as in the old app; anything else keeps its name. */
export function pastedName(name: string, type: string, hex: string): string {
  if (name && !/^image\.\w+$/i.test(name)) return name;
  const ext = /^image\/(\w+)/.exec(type)?.[1]?.replace("jpeg", "jpg") ?? /\.(\w+)$/.exec(name)?.[1] ?? "png";
  return `图片-${hex}.${ext}`;
}

const isCjk = (code: number) => (code >= 0x4e00 && code <= 0x9fff) || (code >= 0x3400 && code <= 0x4dbf);
const isWordChar = (code: number) => (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
/** Inside a word these keep it going: 2.0, 3,200, 50%. */
const continuesWord = (code: number) => code === 0x2e || code === 0x2c || code === 0x25;

/** 字数: each CJK character counts once, each run of ASCII letters or digits once; markers don't count. */
export function countWords(text: string): number {
  let count = 0;
  for (const line of text.split("\n")) {
    let inWord = false;
    for (const char of line.slice(blockPrefixLength(line))) {
      const code = char.codePointAt(0)!;
      if (isCjk(code)) {
        count += 1;
        inWord = false;
      } else if (isWordChar(code)) {
        if (!inWord) count += 1;
        inWord = true;
      } else if (!(inWord && continuesWord(code))) {
        inWord = false;
      }
    }
  }
  return count;
}

/** The line is nothing but one embed (`![[a.png]]`) or image (`![](a.png)`). */
function isAttachmentLine(line: string, spans: InlineSpan[]): boolean {
  const [only] = spans;
  if (spans.length !== 1 || !only || (only.kind !== "embed" && only.kind !== "image")) return false;
  const ends = [only.content, ...only.marks];
  const from = Math.min(...ends.map((r) => r.from));
  const to = Math.max(...ends.map((r) => r.to));
  return line.slice(from, to) === line.trim();
}

const summaryLength = { enough: 100, max: 110 };
const skippedInSummary = new Set<BlockType>(["h1", "h2", "h3", "h4", "h5", "h6", "empty", "hr", "table", "fence"]);

/**
 * 摘要: the one line of prose the 详细 list shows under a title. Headings, code, math, front matter,
 * tables, rules and lines that are only an attachment are left out; Markdown syntax is removed.
 */
export function noteSummary(text: string): string {
  const lines = text.split(/\r?\n/);
  const literal = new Set(literalBlocks(lines).flatMap((b) => Array.from({ length: b.last - b.first + 1 }, (_, i) => b.first + i)));
  const parts: string[] = [];
  for (const [i, line] of lines.entries()) {
    if (literal.has(i)) continue;
    const type = blockType(line);
    if (skippedInSummary.has(type)) continue;
    const { prefix, spans } = parseLine(line, type);
    if (isAttachmentLine(line, spans)) continue;
    const marks = [prefix, ...spans.flatMap((s) => s.marks)].sort((a, b) => b.from - a.from);
    let clean = line;
    for (const mark of marks) clean = clean.slice(0, mark.from) + clean.slice(mark.to);
    clean = clean.trim();
    if (clean) parts.push(clean);
    if (parts.join(" ").length >= summaryLength.enough) break;
  }
  return parts.join(" ").slice(0, summaryLength.max);
}
