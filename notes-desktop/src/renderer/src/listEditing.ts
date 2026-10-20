// 列表延续与退出列表 in the editor: Return in a list item, by the rules in core/lists.ts. Works in both
// the typeset and the source view; inside code, math and front matter Return is just a new line.
import {
  EditorState,
  Prec,
  StateEffect,
  StateField,
  type Extension,
  type Text,
  type Transaction,
  type TransactionSpec,
} from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { closesListGap, listReturn, opensListGap } from "../../core/lists";
import { blockPrefixLength } from "../../core/markdown";
import { inLiteralBlock, literal } from "./markdownView";

/** The note's lines above line `number` (1-based), nearest first. */
function* linesAbove(view: EditorView, number: number) {
  for (let n = number - 1; n >= 1; n--) yield view.state.doc.line(n).text;
}

function returnInList(view: EditorView): boolean {
  const { state } = view;
  if (view.composing || state.selection.ranges.length > 1) return false;
  const { from, to } = state.selection.main;
  const line = state.doc.lineAt(from);
  if (to > line.to || inLiteralBlock(state, line.number)) return false;
  const action = listReturn(line.text, linesAbove(view, line.number));
  if (!action) return false;
  if (action.kind === "continue") {
    // With the caret in the marker itself, Return is an ordinary new line.
    if (from < line.from + blockPrefixLength(line.text)) return false;
    view.dispatch(state.replaceSelection(state.lineBreak + action.prefix), { scrollIntoView: true, userEvent: "input" });
  } else {
    const insert = action.kind === "outdent" ? action.prefix : "";
    view.dispatch({
      changes: { from: line.from, to: line.to, insert },
      selection: { anchor: line.from + insert.length },
      scrollIntoView: true,
      userEvent: "input",
    });
  }
  return true;
}

const setGap = StateEffect.define<number | null>();

/** The blank line starting at `at` in `doc`, if it is still one with a line below it. */
function blankAt(doc: Text, at: number) {
  const blank = doc.lineAt(at);
  return blank.from === at && blank.length === 0 && blank.number < doc.lines ? blank : null;
}

/**
 * The 分隔空行 this editor put in, by where its line starts, while the caret stays on the line below it.
 * Undo, redo and leaving that line forget it (a new note starts with none); the blank line itself stays.
 */
const listGap = StateField.define<number | null>({
  create: () => null,
  update(gap, tr) {
    for (const effect of tr.effects) if (effect.is(setGap)) return effect.value;
    if (gap === null || tr.isUserEvent("undo") || tr.isUserEvent("redo")) return null;
    const at = tr.changes.mapPos(gap, -1);
    const blank = blankAt(tr.newDoc, at);
    return blank && tr.newDoc.lineAt(tr.newSelection.main.head).number === blank.number + 1 ? at : null;
  },
});

/** Typing, composing or pasting text on an empty line right below a list item puts a blank line in
 *  between first; the text's line ending empty or as a list item again takes it out. Either way in the
 *  same transaction as the input, so undo never sees the blank line on its own. */
const separateFromList = EditorState.transactionFilter.of((tr): Transaction | readonly TransactionSpec[] => {
  if (!tr.docChanged || !(tr.isUserEvent("input") || tr.isUserEvent("delete"))) return tr;
  const start = tr.startState;
  const gap = start.field(listGap);
  if (gap !== null) {
    const at = tr.changes.mapPos(gap, -1);
    const blank = blankAt(tr.newDoc, at);
    if (!blank || !closesListGap(tr.newDoc.line(blank.number + 1).text)) return tr;
    return [tr, { changes: { from: at - 1, to: at }, effects: setGap.of(null), sequential: true }];
  }
  if (start.selection.ranges.length > 1) return tr;
  let opening: TransactionSpec | null = null;
  let changes = 0;
  tr.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
    changes += 1;
    const line = start.doc.lineAt(fromA);
    if (toA !== fromA || line.number === 1) return;
    const above = start.doc.line(line.number - 1);
    if (!opensListGap(above.text, line.text, inserted.toString()) || inLiteralBlock(start, above.number)) return;
    // Text that is itself a list item joins the list above.
    if (closesListGap(inserted.line(1).text)) return;
    opening = { changes: { from: above.to, insert: start.lineBreak }, effects: setGap.of(line.from) };
  });
  return opening && changes === 1 ? [tr, opening] : tr;
});

/** Return continues, steps out of or ends a list; text after a list is kept apart from it. */
export const listEditing: Extension = [
  literal,
  listGap,
  separateFromList,
  Prec.high(keymap.of([{ key: "Enter", run: returnInList }])),
];
