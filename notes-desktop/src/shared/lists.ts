// List editing rules (列表延续与退出列表), ported from the old editor. Pure, like markdown.ts, so the
// renderer bundles it for the editor's Return key and its 分隔空行.
import { blockPrefixLength, blockType } from "./markdown";

/** What Return at the end of a list item does. */
export type ListReturn =
  /** A new line with this marker after it. */
  | { kind: "continue"; prefix: string }
  /** An empty nested item: the line becomes this marker, one level out (later items keep their numbers). */
  | { kind: "outdent"; prefix: string }
  /** An empty outermost item: its marker goes and the caret stays on the line, with no new line. */
  | { kind: "exit" };

/**
 * Return at the end of `line`, or null when it is not a list item. `above` holds the note's lines
 * above it, nearest first; it is read only as far as the item's parent.
 */
export function listReturn(line: string, above: Iterable<string>): ListReturn | null {
  const type = blockType(line);
  if (type !== "li" && type !== "ol" && type !== "task") return null;
  if (line.slice(blockPrefixLength(line)).trim() !== "") return { kind: "continue", prefix: nextMarker(line, type) };
  // An empty item: step out to its parent's list, or end the list at the outermost level.
  const parent = parentItem(line, above);
  return parent ? { kind: "outdent", prefix: parent } : { kind: "exit" };
}

const isListItem = (line: string) => {
  const type = blockType(line);
  return type === "li" || type === "ol" || type === "task";
};

/**
 * Whether `inserted`, starting the empty `line` right below `above`, needs a blank line (分隔空行) put in
 * between: Markdown ends a list only at one, or the text would continue the item. A new line is not text.
 */
export function opensListGap(above: string, line: string, inserted: string): boolean {
  return line === "" && /[^\r\n]/.test(inserted) && isListItem(above);
}

/** Whether the line below a 分隔空行 the editor put in takes it out again: the line is empty once more,
 *  or starts with a complete list marker (its space typed) and so joins the list above. */
export function closesListGap(line: string): boolean {
  return line === "" || (isListItem(line) && blockPrefixLength(line) > 0);
}

/** Indentation width, a tab counting four. */
const indentWidth = (line: string) => [.../^[ \t]*/.exec(line)![0]].reduce((n, c) => n + (c === "\t" ? 4 : 1), 0);

/** The marker following the nearest item above indented less than `line`; null at the outermost level,
 *  or when what it nests in is not a list item that would continue. */
function parentItem(line: string, above: Iterable<string>): string | null {
  const own = indentWidth(line);
  if (own === 0) return null;
  for (const text of above) {
    if (text.trim() === "") continue;
    if (indentWidth(text) >= own) continue;
    const next = listReturn(text, []);
    return next?.kind === "continue" ? next.prefix : null;
  }
  return null;
}

/** The marker of the item after `line`, at its level. */
function nextMarker(line: string, type: "li" | "ol" | "task"): string {
  const prefix = line.slice(0, blockPrefixLength(line));
  const indent = /^[ \t]*/.exec(prefix)![0];
  const marker = prefix.slice(indent.length);
  if (type === "task") return `${indent}${marker[0]} [ ] `;
  if (type === "ol") return `${indent}${parseInt(marker, 10) + 1}${marker.includes(")") ? ")" : "."} `;
  return prefix;
}

const itemRe = /^([ \t]*)([-*+]|\d{1,9}[.)])( +|\t)/;

/** A list item's indentation, marker and the room the marker takes before its text (a child's indent). */
function item(line: string) {
  if (!isListItem(line)) return null;
  const m = itemRe.exec(line)!;
  return { indent: m[1]!, marker: m[2]!, width: indentWidth(line), offset: m[2]!.length + m[3]!.length };
}

/** The marker an item gets at its new place: ordered items number on from the item before them at that
 *  level (from 1 when there is none), keeping their own delimiter; bullets keep theirs. */
function markerAt(marker: string, previous: string | undefined): string {
  if (!/\d/.test(marker[0]!)) return marker;
  const number = previous !== undefined && /^\d/.test(previous) ? parseInt(previous, 10) + 1 : 1;
  return `${number}${marker.slice(-1)}`;
}

/** `text` indented `shift` columns further in (or out, when negative); a tab counts four. */
function shifted(text: string, shift: number): string {
  if (shift >= 0) return " ".repeat(shift) + text;
  let cut = 0;
  let removed = 0;
  while (removed < -shift && (text[cut] === " " || text[cut] === "\t")) removed += text[cut++] === "\t" ? 4 : 1;
  return " ".repeat(Math.max(0, removed + shift)) + text.slice(cut);
}

/**
 * Tab (inward) or Shift-Tab (outward) on lines `first`…`last` (0-based) of a note whose lines `line(n)`
 * gives: each list item among them moves one level in, under the item before it, or one level out, to
 * its parent's level; an item's nested lines move with it. Returns the lines that change, top to
 * bottom, or null when the range holds no list item. An item that cannot move (the first at its level,
 * or one already outermost) stays as it is.
 */
export function listIndent(line: (n: number) => string, lines: number, first: number, last: number, outward: boolean): { line: number; text: string }[] | null {
  const texts = new Map<number, string>();
  const at = (n: number) => texts.get(n) ?? line(n);
  let any = false;
  for (let n = first; n <= last; n++) {
    const own = item(line(n));
    if (!own) continue;
    any = true;
    // Walking up the lines already moved: the nearest item at this level (a sibling), and the nearest
    // one further out (the parent).
    let sibling: ReturnType<typeof item> = null;
    let parent: ReturnType<typeof item> = null;
    let before: string | undefined;
    for (let k = n - 1; k >= 0; k--) {
      const text = at(k);
      if (text.trim() === "") continue;
      const other = item(text);
      if (!other) {
        if (indentWidth(text) === 0) break;
        continue;
      }
      if (other.width < own.width) {
        parent = other;
        break;
      }
      if (other.width === own.width && !sibling) sibling = other;
    }
    let indent: string;
    let marker: string;
    if (outward) {
      if (own.width === 0) continue;
      indent = parent ? parent.indent : "";
      // Numbered on from the parent when both are numbered.
      marker = markerAt(own.marker, parent?.marker);
    } else {
      if (!sibling) continue;
      indent = sibling.indent + " ".repeat(sibling.offset);
      const newWidth = indentWidth(indent);
      for (let k = n - 1; k >= 0 && before === undefined; k--) {
        const other = item(at(k));
        if (!other) continue;
        if (other.width === newWidth) before = other.marker;
        else if (other.width < newWidth) break;
      }
      marker = markerAt(own.marker, before);
    }
    const text = line(n);
    const moved = `${indent}${marker}${text.slice(own.indent.length + own.marker.length)}`;
    texts.set(n, moved);
    // Its nested lines (deeper than it, up to the next line at its level or further out) move by as much,
    // and need no moving of their own when they are selected too.
    const shift = indentWidth(moved) - own.width;
    let k = n + 1;
    for (; k < lines; k++) {
      const child = line(k);
      if (child.trim() === "") continue;
      if (indentWidth(child) <= own.width) break;
      texts.set(k, shifted(child, shift));
    }
    n = k - 1;
  }
  if (!any) return null;
  return [...texts.entries()].sort((a, b) => a[0] - b[0]).filter(([n, text]) => text !== line(n)).map(([n, text]) => ({ line: n, text }));
}
