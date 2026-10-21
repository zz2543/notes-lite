// Lines removed and added between two texts: what the operation log shows of a note's rewrite, and
// what a turn's review card counts and shows of each note the assistant changed.

export interface DiffLine {
  sign: "-" | "+";
  text: string;
}

/** Past this many line pairs left to compare, the middle counts as wholly removed and added (a long note rewritten throughout). */
const compareLimit = 4_000_000;

/** A text's lines; a final line break does not start another line. */
export const textLines = (text: string): string[] => (text === "" ? [] : text.replace(/(\r\n|\r|\n)$/, "").split(/\r\n|\r|\n/));

/** Lines removed (`-`) and added (`+`) going from `old` to `now`, in reading order. */
export function lineDiff(old: string[], now: string[]): DiffLine[] {
  // What both start and end with is never compared.
  let head = 0;
  while (head < old.length && head < now.length && old[head] === now[head]) head++;
  let tail = 0;
  while (tail < old.length - head && tail < now.length - head && old[old.length - 1 - tail] === now[now.length - 1 - tail]) tail++;
  const a = old.slice(head, old.length - tail);
  const b = now.slice(head, now.length - tail);
  if (a.length * b.length > compareLimit)
    return [...a.map((text) => ({ sign: "-" as const, text })), ...b.map((text) => ({ sign: "+" as const, text }))];
  // Longest common subsequence, then walked from the start.
  const lcs = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0));
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) lcs[i]![j] = a[i] === b[j] ? lcs[i + 1]![j + 1]! + 1 : Math.max(lcs[i + 1]![j]!, lcs[i]![j + 1]!);
  }
  const out: DiffLine[] = [];
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) {
      i++;
      j++;
    } else if (j >= b.length || (i < a.length && lcs[i + 1]![j]! >= lcs[i]![j + 1]!)) out.push({ sign: "-", text: a[i++]! });
    else out.push({ sign: "+", text: b[j++]! });
  }
  return out;
}
