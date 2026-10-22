// 记录表: Markdown tables inside notes, where the header names the fields and each row is a
// record. Pure, like markdown.ts: finding tables, typed reading, and line-level edits that leave
// the rest of the note as it was.
import { blockType, literalBlocks } from "../shared/markdown";

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
export function addressableTables(path: string, text: string): { source: string; header: string[]; dated: boolean }[] {
  const tables = recordTables(text);
  return tables.flatMap((table, index) => {
    const addressable = index === 0 || (table.heading !== null && tables.find((t) => t.heading === table.heading) === table);
    if (!addressable) return [];
    const source = index === 0 && table.heading === null ? path : `${path}${table.heading !== null ? `#${table.heading}` : ""}`;
    return [{ source, header: table.header, dated: isDated(table) }];
  });
}

/**
 * Whether a table looks like a log of progress — a date/time column or a `YYYY-MM-DD` cell —
 * rather than content (a comparison, a cheat sheet) that happens to be a table.
 */
function isDated(table: RecordTable): boolean {
  return table.header.some((cell) => /日期|时间|date|day|time/i.test(cell)) || table.rows.some((row) => row.some((cell) => /^\d{4}-\d{2}-\d{2}/.test(cell.trim())));
}

// --- typed records -------------------------------------------------------------------------

export type FieldType = "number" | "date" | "text";

/** The table under `heading`, or the note's first table when no heading is given. */
export function findTable(text: string, heading: string | null): RecordTable | undefined {
  const tables = recordTables(text);
  return heading ? tables.find((table) => table.heading === heading) : tables[0];
}

const numberRe = /^[-+]?(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?$/;
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

/** The number a cell holds, if it holds nothing but one. */
export function cellNumber(cell: string): number | undefined {
  const t = cell.trim();
  return numberRe.test(t) ? Number(t) : undefined;
}

/** Whole column numeric → number, whole column `YYYY-MM-DD` → date, otherwise text. Empty cells don't vote. */
export function inferType(column: string[]): FieldType {
  const values = column.map((cell) => cell.trim()).filter((cell) => cell !== "");
  if (values.length === 0) return "text";
  if (values.every((cell) => cellNumber(cell) !== undefined)) return "number";
  if (values.every((cell) => dateRe.test(cell))) return "date";
  return "text";
}

export function fieldTypes(table: RecordTable): FieldType[] {
  return table.header.map((_, c) => inferType(table.rows.map((row) => row[c] ?? "")));
}

/** A value as it reads back from a cell: one line, trimmed. */
export function normalizedCell(value: string): string {
  return value.replace(/\r\n|\r|\n/g, " ").trim();
}

/** One table row; bars are escaped and line breaks folded so a value can't break the table. */
export function renderRow(cells: string[]): string {
  return `| ${cells.map((cell) => cell.replaceAll("\\|", "|").replaceAll("|", "\\|").replace(/\r\n|\r|\n/g, " ")).join(" | ")} |`;
}

export function paddedRow(row: string[], width: number): string[] {
  return Array.from({ length: width }, (_, i) => row[i] ?? "");
}

/** A note's lines and the line break it uses, so an edit keeps the rest of the note as it was. */
function splitNote(text: string): { lines: string[]; eol: string } {
  return { lines: text.split(/\r\n|\r|\n/), eol: /\r\n/.test(text) ? "\r\n" : "\n" };
}

export class RecordError extends Error {
  constructor(
    readonly code: "unknown-field" | "invalid",
    message: string,
  ) {
    super(message);
    this.name = "RecordError";
  }
}

export const unknownField = (field: string) => new RecordError("unknown-field", `记录表里没有字段“${field}”。`);

/** A record's cells in header order; a field the header lacks is refused. */
function cellsOf(record: Record<string, string>, header: string[]): string[] {
  const unknown = Object.keys(record).sort().find((key) => !header.includes(key));
  if (unknown !== undefined) throw unknownField(unknown);
  return header.map((field) => normalizedCell(record[field] ?? ""));
}

/**
 * Appends records at the end of the table, creating the note (`text` null), the heading or the
 * table from `fallbackHeader` when missing. Answers with the new text, the header used and the
 * cells stored for each record.
 */
export function appendRecords(
  text: string | null,
  title: string,
  heading: string | null,
  fallbackHeader: string[],
  records: Array<Record<string, string>>,
): { text: string; header: string[]; rows: string[][] } {
  const table = text === null ? undefined : findTable(text, heading);
  if (text !== null && table) {
    const rows = records.map((record) => cellsOf(record, table.header));
    const { lines, eol } = splitNote(text);
    lines.splice(table.last + 1, 0, ...rows.map(renderRow));
    return { text: lines.join(eol), header: table.header, rows };
  }
  if (fallbackHeader.length === 0) throw new RecordError("invalid", "记录表不存在，且没有可用来新建的表头。");
  const rows = records.map((record) => cellsOf(record, fallbackHeader));
  const eol = text !== null && /\r\n/.test(text) ? "\r\n" : "\n";
  const block = [renderRow(fallbackHeader), `|${fallbackHeader.map(() => "---").join("|")}|`, ...rows.map(renderRow)].join(eol) + eol;
  const headingBlock = heading ? `## ${heading}${eol}${eol}` : "";
  if (text === null) return { text: `# ${title}${eol}${eol}${headingBlock}${block}`, header: fallbackHeader, rows };
  let before = text;
  if (before !== "" && !/[\r\n]$/.test(before)) before += eol;
  if (before !== "") before += eol;
  return { text: before + headingBlock + block, header: fallbackHeader, rows };
}

/** Replaces or deletes body rows (by index among the table's rows); `edit` answers null to delete. */
export function rewriteRows(text: string, table: RecordTable, indices: number[], edit: (index: number, before: string[]) => string[] | null): string {
  const { lines, eol } = splitNote(text);
  for (const index of [...indices].sort((a, b) => b - a)) {
    const line = table.first + 2 + index;
    const after = edit(index, paddedRow(table.rows[index] ?? [], table.header.length));
    if (after) lines[line] = renderRow(after);
    else lines.splice(line, 1);
  }
  return lines.join(eol);
}

/** Puts a row back at `index` among the table's rows. */
export function insertRow(text: string, table: RecordTable, row: string[], index: number): string {
  const { lines, eol } = splitNote(text);
  lines.splice(table.first + 2 + Math.min(Math.max(0, index), table.rows.length), 0, renderRow(row));
  return lines.join(eol);
}
