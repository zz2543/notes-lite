// 列表延续与退出列表 in the editor: Return in a list item, by the rules in core/lists.ts. Works in both
// the typeset and the source view; inside code, math and front matter Return is just a new line.
import { Prec, type Extension } from "@codemirror/state";
import { EditorView, keymap } from "@codemirror/view";
import { listReturn } from "../../core/lists";
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

/** Return continues, steps out of or ends a list. */
export const listEditing: Extension = [literal, Prec.high(keymap.of([{ key: "Enter", run: returnInList }]))];
