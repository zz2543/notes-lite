const cjk = String.raw`\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}`;
const wordChar = String.raw`(?:(?![${cjk}])[\p{L}\p{N}])`;
const words = new RegExp(String.raw`[${cjk}]|${wordChar}+(?:['’.]${wordChar}+)*`, "gu");

/** 字数 as writers expect it: one per CJK character, one per word or number in other scripts. */
export function countWords(text: string): number {
  return text.match(words)?.length ?? 0;
}
