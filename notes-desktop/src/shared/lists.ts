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
