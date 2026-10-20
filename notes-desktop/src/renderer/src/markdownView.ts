// How the editor shows a note: typeset in place (the default) or as its Markdown source. Both are
// views of the same document; typesetting only adds decorations, so the text never changes.
import { Compartment, StateField, type EditorState, type Extension, type Range as Decorated } from "@codemirror/state";
import { Decoration, EditorView, ViewPlugin, WidgetType, type DecorationSet, type ViewUpdate } from "@codemirror/view";
import { codeTokens, type CodeToken } from "../../core/codeHighlight";
import { blockPrefixLength, blockType, literalBlocks, parseLine, type LiteralBlock, type SpanKind } from "../../core/markdown";
import "./markdown.css";

/** The note's literal blocks (code, math, front matter), kept current as it changes. */
export const literal = StateField.define<LiteralBlock[]>({
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

/** Whether line `number` (1-based) is inside code, math or front matter. */
export const inLiteralBlock = (state: EditorState, number: number) => blockAt(state.field(literal), number - 1) !== undefined;

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

/** Whether a caret or selection end sits within the first `length` characters of the line at `from`. */
function touchesPrefix(view: EditorView, from: number, length: number): boolean {
  return view.state.selection.ranges.some((r) => [r.anchor, r.head].some((p) => p >= from && p <= from + length));
}

/** A list item's bullet, number or task box, drawn in place of its marker and indentation. */
class ListMarker extends WidgetType {
  constructor(
    readonly kind: "li" | "ol" | "task",
    readonly label: string,
  ) {
    super();
  }
  eq(other: ListMarker) {
    return other.kind === this.kind && other.label === this.label;
  }
  toDOM() {
    const marker = document.createElement("span");
    marker.className = `cm-md-marker cm-md-marker-${this.kind}`;
    marker.setAttribute("aria-hidden", "true");
    if (this.kind === "task") marker.classList.toggle("cm-md-done", this.label === "x");
    else marker.append(Object.assign(document.createElement("span"), { className: "cm-md-glyph", textContent: this.label }));
    return marker;
  }
  // A click on the marker places the caret like a click on text.
  ignoreEvent() {
    return false;
  }
}

const isTaskDone = (text: string) => /^[ \t]*[-*+] \[[xX]\] /.test(text);

/** Bullets by nesting level, as in the old editor: filled, hollow, square. */
const bullets = ["•", "◦", "▪"];

const hidden = Decoration.replace({});
const mark = (className: string) => Decoration.mark({ class: className });
const syntax = mark("cm-md-mark");
const hangingSyntax = mark("cm-md-mark cm-md-hang");
const lineClass = (className: string, depth?: number) =>
  Decoration.line(depth === undefined ? { class: className } : { class: className, attributes: { style: `--depth: ${depth}` } });

function typeset(view: EditorView): DecorationSet {
  const { state } = view;
  const blocks = state.field(literal);
  const edited = editedLines(view);
  const out: Decorated<Decoration>[] = [];
  for (const { from, to } of view.visibleRanges) {
    for (let pos = from; pos <= to; ) {
      const line = state.doc.lineAt(pos);
      pos = line.to + 1;
      const block = blockAt(blocks, line.number - 1);
      if (block) {
        out.push(...literalLine(line.number - 1, line.from, line.text, block));
        continue;
      }
      const type = blockType(line.text);
      const markup = parseLine(line.text, type);
      const isEdited = edited.has(line.number);
      const prefix = (length: number) => (isEdited ? hangingSyntax : hidden).range(line.from, line.from + length);
      if (/^h[1-6]$/.test(type)) {
        out.push(lineClass(`cm-md-heading cm-md-${type}${line.number === 1 ? " cm-md-first" : ""}`).range(line.from));
        out.push(prefix(markup.prefix.to));
      } else if (type === "quote") {
        // Consecutive quote lines join their bars; the last one stops short of the space after it.
        const next = line.number < state.doc.lines ? state.doc.line(line.number + 1).text : "";
        out.push(lineClass(next.startsWith(">") ? "cm-md-quote" : "cm-md-quote cm-md-quote-end", markup.depth).range(line.from));
        // Only the "> " marks: a callout's "[!note]" stays as written until callouts are rendered.
        out.push(prefix(blockPrefixLength(line.text)));
      } else if (type === "li" || type === "ol" || type === "task") {
        const done = type === "task" && isTaskDone(line.text) ? " cm-md-task-done" : "";
        out.push(lineClass(`cm-md-list cm-md-${type}${done}`, markup.depth).range(line.from));
        const indent = /^[ \t]*/.exec(line.text)![0].length;
        const end = line.from + markup.prefix.to;
        if (isEdited && touchesPrefix(view, line.from, markup.prefix.to)) {
          // The marker as written, hanging where the bullet was; the indentation stays hidden.
          if (indent > 0) out.push(hidden.range(line.from, line.from + indent));
          out.push(hangingSyntax.range(line.from + indent, end));
        } else {
          const label =
            type === "ol" ? `${parseInt(line.text.slice(indent), 10)}.` : type === "li" ? bullets[markup.depth % 3]! : isTaskDone(line.text) ? "x" : "";
          out.push(Decoration.replace({ widget: new ListMarker(type, label) }).range(line.from, end));
        }
      } else if (type === "hr") {
        out.push(lineClass("cm-md-hr").range(line.from));
        // A rule in place of "---"; on its own line the dashes come back to be edited.
        out.push((isEdited ? syntax : hidden).range(line.from, line.to));
      } else {
        out.push(lineClass(`cm-md-${type}`).range(line.from));
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

const codeColours = Object.fromEntries(
  (["keyword", "string", "comment", "number", "type", "literal", "tag", "attribute"] as const).map((t) => [t, mark(`cm-code-${t}`)]),
) as Record<CodeToken, Decoration>;

/** A line of a literal block: code in the code font on its own ground, coloured by its language. */
function literalLine(index: number, from: number, text: string, block: LiteralBlock): Decorated<Decoration>[] {
  if (block.kind === "frontmatter") return [lineClass("cm-md-frontmatter").range(from)];
  const delimiter = index === block.first || (block.closed && index === block.last);
  const ends = `${index === block.first ? " cm-md-codeblock-first" : ""}${index === block.last ? " cm-md-codeblock-last" : ""}`;
  const out = [lineClass(`cm-md-codeblock ${delimiter ? "cm-md-fence" : "cm-md-codeline"}${ends}`).range(from)];
  if (!delimiter && block.kind === "code") {
    for (const t of codeTokens(text, block.language)) out.push(codeColours[t.token].range(from + t.from, from + t.to));
  }
  return out;
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

const display = new Compartment();
const viewFor = (showSource: boolean) => (showSource ? sourceView : typesetView);

/** The editor's display, typeset or source, switchable later with `switchMarkdownView`. */
export const markdownDisplay = (showSource: boolean): Extension => display.of(viewFor(showSource));

/** Shows the note the other way without rebuilding it. The line being edited stays where it is on
 *  screen when it is in view; otherwise the text at the top of the view stays. */
export function switchMarkdownView(view: EditorView, showSource: boolean) {
  const head = view.state.selection.main.head;
  const frame = view.scrollDOM.getBoundingClientRect();
  const caret = view.coordsAtPos(head);
  if (caret === null || caret.top < frame.top || caret.bottom > frame.bottom) {
    view.dispatch({ effects: [display.reconfigure(viewFor(showSource)), view.scrollSnapshot()] });
    return;
  }
  const margin = caret.top - frame.top;
  view.dispatch({ effects: [display.reconfigure(viewFor(showSource)), EditorView.scrollIntoView(head, { y: "start", yMargin: margin })] });
  // Lines above change height with the view, and their new heights are only known once drawn: check
  // where the caret landed and scroll again while it is off.
  const settle = (tries: number) =>
    view.requestMeasure({
      read: (v) => v.coordsAtPos(head)?.top,
      write: (top, v) => {
        if (top === undefined || Math.abs(top - caret.top) < 0.5 || tries === 0) return;
        v.dispatch({ effects: EditorView.scrollIntoView(head, { y: "start", yMargin: margin }) });
        settle(tries - 1);
      },
    });
  settle(3);
}
