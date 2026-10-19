// Markdown structure, ported from the old NotesCore. This module is pure (no Node APIs), so the
// renderer may bundle it directly for per-keystroke work such as 字数.

const heading = /^#{1,6} /;
const quote = /^(?:> ?)+/;
const list = /^[ \t]*(?:[-*+] \[[ xX]\] |[-*+] |\d{1,9}[.)] )/;

/** Length of the block marker a line starts with: heading, quote, list or task item, else 0. */
export function blockPrefixLength(line: string): number {
  return (heading.exec(line) ?? quote.exec(line) ?? list.exec(line))?.[0].length ?? 0;
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
