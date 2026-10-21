// Tables and formulas drawn in place (ticket 12), and images on lines of their own (ticket 13). While the
// caret is elsewhere a table is a grid, a formula is KaTeX's and an image is its picture; with the caret
// in one its Markdown comes back to be edited, a formula or image keeping its picture below. Only
// decorations: the text is never changed.
import { Prec, StateEffect, StateField, type EditorState, type Extension, type Range as Decorated } from "@codemirror/state";
import { Decoration, EditorView, WidgetType, keymap, type DecorationSet } from "@codemirror/view";
import { linkOf, linkPath, parseLine, parseTable, renderedBlocks, shownSpan, type Link, type LiteralBlock, type RenderedBlock, type SpanKind } from "../../shared/markdown";
import { followsLink, linkHost, pressImage } from "./linkHost";
import { renderTex } from "./tex";

/** The class of each kind of inline markup typeset, in the lines and in table cells alike. */
export const inlineClasses: Partial<Record<SpanKind, string>> = {
  bold: "cm-md-bold",
  italic: "cm-md-italic",
  code: "cm-md-code",
  strike: "cm-md-strike",
  highlight: "cm-md-highlight",
  wikilink: "cm-md-link",
  link: "cm-md-link",
  embed: "cm-md-link cm-md-embed",
  image: "cm-md-link cm-md-embed",
  tag: "cm-md-tag",
};

/** Whether a press on a block widget is on its sideways scrollbar, to scroll it rather than open it. */
const onScrollbar = (wrap: HTMLElement, event: MouseEvent) =>
  event.clientY >= wrap.getBoundingClientRect().top + wrap.clientTop + wrap.clientHeight;

/** Puts the caret `offset` characters into the block a widget stands for, and the focus in the editor. */
function caretInto(view: EditorView, dom: HTMLElement, offset: number) {
  const from = view.posAtDOM(dom);
  view.dispatch({ selection: { anchor: Math.min(from + offset, view.state.doc.length) }, userEvent: "select" });
  view.focus();
}

/** One line of Markdown (a table cell) as typeset text: emphasis, code, links and formulas, the marks
 *  hidden. A link's text carries where it leads, for ⌘ / Ctrl-click. */
function inlineMarkdown(text: string, into: HTMLElement, view: EditorView) {
  // One list per UTF-16 unit, as the spans count them (an emoji is two).
  const classes = Array.from({ length: text.length }, (): string[] => []);
  const links: (Link | undefined)[] = [];
  const hidden = new Set<number>();
  const formulas = new Map<number, { tex: string; end: number }>();
  for (const span of parseLine(text, "p").spans) {
    if (span.kind === "math") {
      const from = span.marks[0]!.from;
      const end = span.marks[1]!.to;
      formulas.set(from, { tex: span.value ?? "", end });
      continue;
    }
    const cls = inlineClasses[span.kind];
    if (cls) {
      const { content, marks } = shownSpan(span);
      const link = linkOf(span) ?? undefined;
      for (let i = content.from; i < content.to; i++) {
        classes[i]!.push(cls);
        if (link) links[i] = link;
      }
      for (const r of marks) for (let i = r.from; i < r.to; i++) hidden.add(i);
    }
  }
  let run = "";
  let runClass = "";
  let runLink: Link | undefined;
  const flush = () => {
    if (run && (runClass || runLink)) {
      const el = Object.assign(document.createElement("span"), { className: runClass, textContent: run });
      if (runLink) Object.assign(el.dataset, { target: runLink.target, wiki: String(runLink.wiki) });
      into.append(el);
    } else if (run) into.append(run);
    run = "";
  };
  for (let i = 0; i < text.length; i++) {
    const formula = formulas.get(i);
    if (formula) {
      flush();
      const el = document.createElement("span");
      el.className = "cm-md-math";
      renderTex(el, formula.tex, false, view);
      into.append(el);
      i = formula.end - 1;
      continue;
    }
    if (hidden.has(i)) continue;
    const cls = classes[i]!.join(" ");
    if (cls !== runClass || links[i] !== runLink) flush();
    runClass = cls;
    runLink = links[i];
    run += text[i];
  }
  flush();
}

/** The link a table cell's text carries under a ⌘ / Ctrl-click, followed; false when there is none. */
function followFromCell(view: EditorView, event: MouseEvent): boolean {
  const el = (event.target as HTMLElement).closest<HTMLElement>("[data-target]");
  const host = view.state.facet(linkHost);
  if (!el || !host || !followsLink(event)) return false;
  host.follow({ target: el.dataset.target!, wiki: el.dataset.wiki === "true" });
  return true;
}

/** A table as a grid. A click in a cell puts the caret at the end of that cell's text. */
class TableWidget extends WidgetType {
  private readonly source: string;
  constructor(readonly lines: readonly string[]) {
    super();
    this.source = lines.join("\n");
  }
  eq(other: TableWidget) {
    return other.source === this.source;
  }
  get estimatedHeight() {
    // Its shown rows (all lines but the separator) at about a cell's height each.
    return (this.lines.length - 1) * 30;
  }
  toDOM(view: EditorView) {
    const wrap = document.createElement("div");
    wrap.className = "cm-md-grid";
    const table = parseTable(this.lines);
    if (!table) return wrap;
    const grid = document.createElement("table");
    // Where each shown row's line starts, from the table's start (the separator line is not shown).
    const starts: number[] = [];
    for (let i = 0, at = 0; i < this.lines.length; at += this.lines[i]!.length + 1, i++) if (i !== 1) starts.push(at);
    [table.header, ...table.rows].forEach((cells, r) => {
      const row = document.createElement("tr");
      cells.forEach((cell, c) => {
        const el = document.createElement(r === 0 ? "th" : "td");
        el.style.textAlign = table.aligns[c]!;
        inlineMarkdown(cell.text, el, view);
        const line = this.lines[r === 0 ? 0 : r + 1]!;
        el.dataset.offset = String(starts[r]! + (cell.range ? cell.range.to : line.length));
        row.append(el);
      });
      (r === 0 ? grid.createTHead() : (grid.tBodies[0] ?? grid.createTBody())).append(row);
    });
    wrap.append(grid);
    wrap.addEventListener("mousedown", (event) => {
      if (onScrollbar(wrap, event)) return;
      if (event.button === 0 && followFromCell(view, event)) return event.preventDefault();
      const cell = (event.target as HTMLElement).closest<HTMLElement>("th, td");
      event.preventDefault();
      caretInto(view, wrap, cell ? Number(cell.dataset.offset) : 0);
    });
    return wrap;
  }
}

/** A formula on its own lines, centred. Drawn for the block it stands for, a click goes into its TeX;
 *  as the preview under the TeX being edited, it is only a picture. */
class MathWidget extends WidgetType {
  constructor(
    readonly tex: string,
    /** Where a click puts the caret, from the block's start; null for the preview. */
    readonly caret: number | null,
  ) {
    super();
  }
  eq(other: MathWidget) {
    return other.tex === this.tex && other.caret === this.caret;
  }
  get estimatedHeight() {
    return 60;
  }
  toDOM(view: EditorView) {
    const el = document.createElement("div");
    el.className = this.caret === null ? "cm-md-math-block cm-md-math-preview" : "cm-md-math-block";
    renderTex(el, this.tex, true, view);
    const caret = this.caret;
    if (caret !== null) {
      el.addEventListener("mousedown", (event) => {
        if (onScrollbar(el, event)) return;
        event.preventDefault();
        caretInto(view, el, caret);
      });
    }
    return el;
  }
}

/** An image on a line of its own, as large as it is up to the column's width and 480px high. Drawn for
 *  its line, a click puts the caret at the line's end (its Markdown comes back above it); as the preview
 *  under the Markdown being edited, it is only a picture. A double click opens it either way. */
class ImageWidget extends WidgetType {
  constructor(
    readonly link: Link,
    /** Where a click puts the caret, from the line's start; null for the preview. */
    readonly caret: number | null,
  ) {
    super();
  }
  eq(other: ImageWidget) {
    return other.link.target === this.link.target && other.link.wiki === this.link.wiki && other.caret === this.caret;
  }
  get estimatedHeight() {
    return 240;
  }
  toDOM(view: EditorView) {
    const el = document.createElement("div");
    el.className = this.caret === null ? "cm-md-image cm-md-image-preview" : "cm-md-image";
    el.dataset.target = this.link.target;
    const note = (text: string, failed: boolean) => {
      const label = Object.assign(document.createElement("span"), { className: failed ? "cm-md-image-note cm-md-image-failed" : "cm-md-image-note", textContent: text });
      el.replaceChildren(label);
      view.requestMeasure();
    };
    const name = linkPath(this.link.target);
    note(`正在载入 ${name}…`, false);
    const host = view.state.facet(linkHost);
    void host?.image(this.link).then((result) => {
      if (!result.ok) return note(result.message, true);
      const img = new Image();
      img.alt = name;
      img.draggable = false;
      img.onload = () => {
        el.replaceChildren(img);
        view.requestMeasure();
      };
      img.onerror = () => note(`无法显示图片：${name}`, true);
      img.src = result.value;
    });
    el.addEventListener("mousedown", (event) => {
      if (event.button !== 0) return;
      event.preventDefault();
      if (event.detail >= 2 || followsLink(event)) return host?.open(this.link);
      pressImage(view, this.link);
      if (this.caret !== null) caretInto(view, el, this.caret);
    });
    return el;
  }
}

/** Inline `$…$` drawn as its formula; a click on it places the caret and brings the TeX back. */
export class InlineMath extends WidgetType {
  constructor(readonly tex: string) {
    super();
  }
  eq(other: InlineMath) {
    return other.tex === this.tex;
  }
  toDOM(view: EditorView) {
    const el = document.createElement("span");
    el.className = "cm-md-math";
    renderTex(el, this.tex, false, view);
    return el;
  }
  ignoreEvent() {
    return false;
  }
}

const setFocused = StateEffect.define<boolean>();
/** Whether the editor has the focus: without it, every table and formula is drawn, as every line's
 *  syntax is hidden. Kept outside the display's compartment, so switching views doesn't forget it. */
const focused = StateField.define<boolean>({
  create: () => false,
  update: (value, tr) => tr.effects.reduce((v, e) => (e.is(setFocused) ? e.value : v), value),
});
export const focusTracking: Extension = [focused, EditorView.focusChangeEffect.of((_, focusing) => setFocused.of(focusing))];

/** Which blocks have the caret in them, and so show their Markdown (none without the focus). */
function openBlocks(state: EditorState, blocks: readonly RenderedBlock[]): boolean[] {
  const { doc, selection } = state;
  const editing = state.field(focused, false) ?? false;
  return blocks.map((block) => {
    const from = doc.line(block.first + 1).from;
    const to = doc.line(block.last + 1).to;
    return editing && selection.ranges.some((r) => r.from <= to && r.to >= from);
  });
}

function draw(state: EditorState, blocks: readonly RenderedBlock[], open: readonly boolean[]): DecorationSet {
  const { doc } = state;
  const out: Decorated<Decoration>[] = [];
  for (const [i, block] of blocks.entries()) {
    const from = doc.line(block.first + 1).from;
    const to = doc.line(block.last + 1).to;
    if (open[i]) {
      if (block.kind === "math") out.push(Decoration.widget({ widget: new MathWidget(block.tex, null), block: true, side: 1 }).range(to));
      if (block.kind === "image") out.push(Decoration.widget({ widget: new ImageWidget(block.image!, null), block: true, side: 1 }).range(to));
      continue;
    }
    const widget =
      block.kind === "table"
        ? new TableWidget(Array.from({ length: block.last - block.first + 1 }, (_, i) => doc.line(block.first + 1 + i).text))
        : block.kind === "image"
          ? new ImageWidget(block.image!, doc.line(block.first + 1).length)
          : // Into the TeX: past "$$" on a one-line formula, at the start of its first line in a block.
            new MathWidget(block.tex, block.first === block.last ? 2 : doc.line(block.first + 1).length + 1);
    out.push(Decoration.replace({ widget, block: true }).range(from, to));
  }
  return Decoration.set(out, true);
}

/** ↑ and ↓ go into a table or formula drawn in the way, rather than over it as over one line: its last
 *  line going up, its first going down, where its Markdown opens to be edited. */
function stepInto(blocks: StateField<RenderedBlock[]>, forward: boolean) {
  return (view: EditorView): boolean => {
    const { state } = view;
    const range = state.selection.main;
    if (state.selection.ranges.length > 1 || !range.empty) return false;
    const from = state.doc.lineAt(range.head).number - 1;
    const to = state.doc.lineAt(view.moveVertically(range, forward).head).number - 1;
    const passed = state.field(blocks).filter((b) => (forward ? b.first > from && b.first <= to : b.last < from && b.last >= to));
    const block = forward ? passed[0] : passed.at(-1);
    if (!block) return false;
    view.dispatch({ selection: { anchor: state.doc.line((forward ? block.first : block.last) + 1).from }, scrollIntoView: true, userEvent: "select" });
    return true;
  };
}

/** Tables, formulas and images drawn in place, given the note's literal blocks (which hold `$$` math). */
export function renderedView(literal: StateField<LiteralBlock[]>): Extension {
  const find = (state: EditorState) =>
    renderedBlocks({ length: state.doc.lines, line: (i) => state.doc.line(i + 1).text }, state.field(literal));
  const blocks = StateField.define<RenderedBlock[]>({
    create: find,
    update: (value, tr) => (tr.docChanged ? find(tr.state) : value),
  });
  const drawn = StateField.define<{ open: boolean[]; decorations: DecorationSet }>({
    create: (state) => {
      const open = openBlocks(state, state.field(blocks));
      return { open, decorations: draw(state, state.field(blocks), open) };
    },
    update: (value, tr) => {
      if (!tr.docChanged && !tr.selection && !tr.effects.some((e) => e.is(setFocused))) return value;
      const open = openBlocks(tr.state, tr.state.field(blocks));
      // The caret moving within the text or within one block leaves every block as it was drawn.
      if (!tr.docChanged && open.every((o, i) => o === value.open[i])) return value;
      return { open, decorations: draw(tr.state, tr.state.field(blocks), open) };
    },
    provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
  });
  return [
    blocks,
    drawn,
    Prec.high(keymap.of([
      { key: "ArrowUp", run: stepInto(blocks, false) },
      { key: "ArrowDown", run: stepInto(blocks, true) },
    ])),
  ];
}
