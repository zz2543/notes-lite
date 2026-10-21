// 笔记链接、图片与附件 in the editor (ticket 13): ⌘ / Ctrl-click follows a link, pasted and dropped files
// are imported into the library and linked on lines of their own. What following and importing do is
// the host's: the editor only knows the text.
import { Prec, type Extension } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { literalBlocks, linkOf, parseLine, pastedName, snippetInsertion, type Link } from "../../shared/markdown";
import { followsLink, imagePressedBefore, linkHost } from "./linkHost";
import { literal } from "./markdownView";

/** The link at `pos`, its syntax included, outside code. */
export function linkAt(view: EditorView, pos: number): Link | null {
  const { state } = view;
  const line = state.doc.lineAt(pos);
  // The source view keeps no literal blocks of its own.
  const blocks = state.field(literal, false) ?? literalBlocks(state.doc.iterLines());
  if (blocks.some((b) => line.number - 1 >= b.first && line.number - 1 <= b.last)) return null;
  const offset = pos - line.from;
  for (const span of parseLine(line.text).spans) {
    const ranges = [span.content, ...span.marks];
    const from = Math.min(...ranges.map((r) => r.from));
    const to = Math.max(...ranges.map((r) => r.to));
    const link = linkOf(span);
    // A click lands between two characters: either side of it counts, the link's edges included.
    if (link && offset >= from && offset <= to && (offset > from || pos === line.from + from)) return link;
  }
  return null;
}

/** Puts the imported files' Markdown in place of the selection, each on a line of its own, the caret after the last. */
function insertSnippets(view: EditorView, snippets: string[]) {
  if (snippets.length === 0) return;
  const { from, to } = view.state.selection.main;
  const { doc } = view.state;
  // The line as it will be around the files' Markdown, the selection gone.
  const start = doc.lineAt(from).from;
  const around = doc.sliceString(start, from) + doc.sliceString(to, doc.lineAt(to).to);
  const { text, caret } = snippetInsertion(around, from - start, snippets);
  view.dispatch({ changes: { from, to, insert: text }, selection: { anchor: from + caret }, scrollIntoView: true, userEvent: "input.paste" });
  view.focus();
}

const randomHex = () => Array.from(crypto.getRandomValues(new Uint8Array(4)), (b) => b.toString(16).padStart(2, "0")).join("");

/** Imports files, then puts their Markdown where the selection is by then (the user may have moved it). */
async function importFiles(view: EditorView, files: readonly File[], pasted: boolean) {
  const host = view.state.facet(linkHost);
  if (!host || files.length === 0) return;
  const read = await Promise.all(
    files.map(async (file) => ({ name: pasted ? pastedName(file.name, file.type, randomHex()) : file.name, data: new Uint8Array(await file.arrayBuffer()) })),
  );
  const snippets = await host.importFiles(read);
  // The editor may have closed meanwhile (another note opened): the files are in the library anyway.
  if (snippets && view.dom.isConnected) insertSnippets(view, snippets);
}

/** Imports files the user chose (笔记 › 导入图片或附件…) at the caret. */
export async function importChosen(view: EditorView, choose: () => Promise<string[] | null>) {
  const snippets = await choose();
  if (snippets && view.dom.isConnected) insertSnippets(view, snippets);
}

/** Following links, and files pasted or dropped into the note. */
export const linkHandling: Extension = Prec.high(
  EditorView.domEventHandlers({
    mousedown(event, view) {
      if (event.button !== 0) return false;
      // The second press of a double click on an image whose Markdown came up under the pointer.
      const image = event.detail === 2 ? imagePressedBefore(view) : null;
      if (image) {
        event.preventDefault();
        view.state.facet(linkHost)?.open(image);
        return true;
      }
      if (!followsLink(event)) return false;
      const pos = view.posAtCoords({ x: event.clientX, y: event.clientY }, false);
      const link = linkAt(view, pos);
      const host = view.state.facet(linkHost);
      if (!link || !host) return false;
      event.preventDefault();
      host.follow(link);
      return true;
    },
    paste(event, view) {
      const files = [...(event.clipboardData?.files ?? [])];
      if (files.length === 0) return false;
      event.preventDefault();
      // What the paste replaces stays until the files are in the library; their Markdown takes its place.
      void importFiles(view, files, true);
      return true;
    },
    dragover(event) {
      if (!event.dataTransfer?.types.includes("Files")) return false;
      event.preventDefault();
      event.dataTransfer.dropEffect = "copy";
      return true;
    },
    drop(event, view) {
      const files = [...(event.dataTransfer?.files ?? [])];
      if (files.length === 0) return false;
      event.preventDefault();
      // The caret goes where the files were dropped, and their Markdown goes there once they are imported.
      const at = view.posAtCoords({ x: event.clientX, y: event.clientY });
      if (at !== null) view.dispatch({ selection: { anchor: at }, userEvent: "select.pointer" });
      void importFiles(view, files, false);
      return true;
    },
  }),
);
