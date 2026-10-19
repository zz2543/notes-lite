// How the editor shows a note: typeset in place (the default) or as its Markdown source. Both are
// views of the same document; typesetting only adds decorations, so the text never changes.
import { StateField, type Extension, type Range as Decorated } from "@codemirror/state";
import { Decoration, EditorView, ViewPlugin, type DecorationSet, type ViewUpdate } from "@codemirror/view";
import { blockType, literalBlocks, parseLine, type LiteralBlock, type SpanKind } from "../../core/markdown";
import "./markdown.css";

/** The note's literal blocks (code, math, front matter), kept current as it changes. */
const literal = StateField.define<LiteralBlock[]>({
  create: (state) => literalBlocks(state.doc.iterLines()),
  update: (blocks, tr) => (tr.docChanged ? literalBlocks(tr.state.doc.iterLines()) : blocks),
});

/** The block holding line `index` (0-based), if any. */
function blockAt(blocks: readonly LiteralBlock[], index: number): LiteralBlock | undefined {
  let lo = 0;
  let hi = blocks.length - 1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const block = blocks[mid]!;
    if (index < block.first) hi = mid - 1;
    else if (index > block.last) lo = mid + 1;
    else return block;
  }
  return undefined;
}

/** Lines holding part of the selection: their syntax shows, dimmed, while elsewhere it hides. */
function editedLines(view: EditorView): Set<number> {
  const lines = new Set<number>();
  if (!view.hasFocus) return lines;
  const { doc, selection } = view.state;
  for (const range of selection.ranges) {
    for (let n = doc.lineAt(range.from).number, last = doc.lineAt(range.to).number; n <= last; n++) lines.add(n);
  }
  return lines;
}

const hidden = Decoration.replace({});
const mark = (className: string) => Decoration.mark({ class: className });
const syntax = mark("cm-md-mark");
const hangingSyntax = mark("cm-md-mark cm-md-hang");

function typeset(view: EditorView): DecorationSet {
  const { state } = view;
  const blocks = state.field(literal);
  const edited = editedLines(view);
  const out: Decorated<Decoration>[] = [];
  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to; ) {
      const line = state.doc.lineAt(pos);
      pos = line.to + 1;
      if (blockAt(blocks, line.number - 1)) continue;
      const type = blockType(line.text);
      const markup = parseLine(line.text, type);
      const isEdited = edited.has(line.number);
      if (/^h[1-6]$/.test(type)) {
        out.push(Decoration.line({ class: `cm-md-heading cm-md-${type}${line.number === 1 ? " cm-md-first" : ""}` }).range(line.from));
        out.push((isEdited ? hangingSyntax : hidden).range(line.from, line.from + markup.prefix.to));
      }
      for (const span of markup.spans) {
        const style = inlineStyles[span.kind];
        if (!style) continue;
        out.push(style.range(line.from + span.content.from, line.from + span.content.to));
        for (const r of span.marks) out.push((isEdited ? syntax : hidden).range(line.from + r.from, line.from + r.to));
      }
    }
  }
  return Decoration.set(out, true);
}

/** Inline markup typeset here; links, math and the rest stay as written until they are rendered too. */
const inlineStyles: Partial<Record<SpanKind, Decoration>> = {
  bold: mark("cm-md-bold"),
  italic: mark("cm-md-italic"),
  code: mark("cm-md-code"),
};

const typesetter = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = typeset(view);
    }
    update(update: ViewUpdate) {
      if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged) {
        this.decorations = typeset(update.view);
      }
    }
  },
  { decorations: (plugin) => plugin.decorations },
);

/** The note typeset in place: headings, emphasis, quotes, lists and code, with their syntax hidden. */
export const typesetView: Extension = [literal, typesetter, EditorView.editorAttributes.of({ class: "cm-typeset" })];

/** The note as its Markdown source, every character shown as it is saved. */
export const sourceView: Extension = EditorView.editorAttributes.of({ class: "cm-source" });

export const markdownView = (showSource: boolean): Extension => (showSource ? sourceView : typesetView);
