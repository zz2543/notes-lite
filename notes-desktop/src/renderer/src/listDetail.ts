import type { ListDetail } from "../../shared/preferences";

/** 笔记列表详细程度, as the settings panel and the list's “…” menu both name them. */
export const listDetails: ReadonlyArray<{ value: ListDetail; label: string; hint: string }> = [
  { value: "compact", label: "简洁", hint: "只有标题" },
  { value: "standard", label: "标准", hint: "标题和日期" },
  { value: "detailed", label: "详细", hint: "标题、一行摘要和日期" },
];

const time = new Intl.DateTimeFormat("zh-CN", { hour: "2-digit", minute: "2-digit", hour12: false });
const dayThisYear = new Intl.DateTimeFormat("zh-CN", { month: "long", day: "numeric" });
const day = new Intl.DateTimeFormat("zh-CN", { year: "numeric", month: "long", day: "numeric" });

/** A note's date in the list: the time for today, the day for this year, else the full date. */
export function listDate(modified: number, now = new Date()): string {
  const date = new Date(modified);
  if (date.toDateString() === now.toDateString()) return time.format(date);
  return (date.getFullYear() === now.getFullYear() ? dayThisYear : day).format(date);
}
