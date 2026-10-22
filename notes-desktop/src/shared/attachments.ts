// 附件设置: where pasted, dropped and imported files go, and what they are called there. One choice for
// the whole app, stored with the other preferences; the folder is a path inside whichever library is open.

/** 附件命名: 保留原名, 笔记名-序号, 笔记名-日期, 笔记名-日期-序号. */
export type AttachmentNaming = "original" | "note-number" | "note-date" | "note-date-number";

export const attachmentNamings: readonly AttachmentNaming[] = ["original", "note-number", "note-date", "note-date-number"];

export interface AttachmentSettings {
  /** A library-relative folder ("附件", "资料/图片"), made when the first file goes in. */
  folder: string;
  naming: AttachmentNaming;
}

/** Where attachments went before there was a setting, and where they still go by default. */
export const defaultAttachmentFolder = "附件";

export const defaultAttachmentSettings: AttachmentSettings = { folder: defaultAttachmentFolder, naming: "original" };

// A library syncs between macOS and Windows, so each folder name must work on both (as organize.ts checks).
const forbidden = /[\\:*?"<>|\u0000-\u001f]/;
const reserved = /^(?:con|prn|aux|nul|com\d|lpt\d)(?:\..*)?$/i;

/**
 * A folder as typed or stored, as a library-relative path ("资料/图片"), or null when it cannot be one:
 * empty, outside the library ("..", an absolute path), hidden (".x"), or with a name Windows refuses.
 */
export function attachmentFolderOf(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const parts = value.trim().replace(/\\/g, "/").split("/").map((part) => part.trim());
  if (parts[0] === "") parts.shift();
  if (parts.at(-1) === "") parts.pop();
  if (!parts.length || parts.length > 8) return null;
  for (const part of parts) {
    if (!part || part.startsWith(".") || forbidden.test(part) || /[. ]$/.test(part) || reserved.test(part)) return null;
  }
  return parts.join("/");
}

/** A date as the file names carry it, in local time: 2026-10-22. */
export function dateStamp(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/**
 * The name to try, the `number`th time (from 1), for a file `name` going in beside note `title`.
 * A taken name moves on to the next number: "报告 2.pdf", "周一-2.png", "周一-2026-10-22 2.png".
 */
export function attachmentName(naming: AttachmentNaming, name: string, title: string, date: Date, number: number): string {
  const dot = name.lastIndexOf(".");
  const [base, ext] = dot > 0 ? [name.slice(0, dot), name.slice(dot)] : [name, ""];
  const again = number === 1 ? "" : ` ${number}`;
  switch (naming) {
    case "note-number":
      return `${title}-${number}${ext}`;
    case "note-date":
      return `${title}-${dateStamp(date)}${again}${ext}`;
    case "note-date-number":
      return `${title}-${dateStamp(date)}-${number}${ext}`;
    default:
      return `${base}${again}${ext}`;
  }
}
