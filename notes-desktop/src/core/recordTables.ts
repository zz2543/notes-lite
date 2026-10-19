// 记录表: Markdown tables inside notes, where the header names the fields and each row is a
// record. Pure, like markdown.ts. Ticket 19 adds typed reading and writing on top of this.
import { blockType, literalBlocks } from "./markdown";

export interface RecordTable {
  /** The nearest heading above the table, without its `#` marks; null when there is none. */
  heading: string | null;
  header: string[];
  rows: string[][];
  /** Line indices (0-based) of the header line and of the last row, inclusive. */
  first: number;
  last: number;
}

const separatorCell = /^\s*:?-+:?\s*$/;

/** The cells of one `| a | b |` line; `\|` stays a bar inside its cell. */
export function tableCells(line: string): string[] {
  let inner = line.trim();
  if (inner.startsWith("|")) inner = inner.slice(1);
  if (inner.endsWith("|") && !inner.endsWith("\\|")) inner = inner.slice(0, -1);
  const cells: string[] = [];
  let cell = "";
  for (let i = 0; i < inner.length; i++) {
    const c = inner[i]!;
    if (c === "\\" && inner[i + 1] === "|") {
      cell += "|";
      i++;
    } else if (c === "|") {
      cells.push(cell.trim());
      cell = "";
    } else cell += c;
  }
  cells.push(cell.trim());
  return cells;
}

/** Every table in a note, outside code blocks and front matter, in order. */
export function recordTables(text: string): RecordTable[] {
  const lines = text.split(/\r\n|\r|\n/);
  const literal = new Set<number>();
  for (const block of literalBlocks(lines)) for (let i = block.first; i <= block.last; i++) literal.add(i);
  const type = (i: number) => (literal.has(i) ? "code" : blockType(lines[i]!));

  const tables: RecordTable[] = [];
  let heading: string | null = null;
  for (let i = 0; i < lines.length; i++) {
    const t = type(i);
    if (/^h[1-6]$/.test(t)) {
      heading = lines[i]!.replace(/^\s*#{1,6}\s*/, "").replace(/\s+#+\s*$/, "").trim();
      continue;
    }
    if (t !== "table") continue;
    let end = i;
    while (end + 1 < lines.length && type(end + 1) === "table") end++;
    const header = tableCells(lines[i]!);
    const separator = i + 1 <= end ? tableCells(lines[i + 1]!) : [];
    if (separator.length === header.length && separator.every((cell) => separatorCell.test(cell))) {
      const rows = lines.slice(i + 2, end + 1).map(tableCells);
      tables.push({ heading, header, rows, first: i, last: end });
    }
    i = end;
  }
  return tables;
}

/**
 * The tables a note offers as record tables, as `路径#标题` (or the bare path for a first table
 * with no heading) with their header. A table is addressable when it is the note's first, or the
 * first under its heading.
 */
export function addressableTables(path: string, text: string): { source: string; header: string[] }[] {
  const tables = recordTables(text);
  return tables.flatMap((table, index) => {
    const addressable = index === 0 || (table.heading !== null && tables.find((t) => t.heading === table.heading) === table);
    if (!addressable) return [];
    const source = index === 0 && table.heading === null ? path : `${path}${table.heading !== null ? `#${table.heading}` : ""}`;
    return [{ source, header: table.header }];
  });
}
