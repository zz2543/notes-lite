// The note's title at the top of its text (方案 A, as Obsidian's inline title): the file's name without
// ".md", edited in place. Enter or leaving the field renames the note by the same rules as 重命名…; a
// name that cannot be used says why under the field and the old one comes back. Esc puts it back.
import { type Extension } from "@codemirror/state";
import { EditorView, ViewPlugin } from "@codemirror/view";

/** Renames the open note to `name`; the reason when it could not. */
export type RenameNote = (name: string) => Promise<string | undefined>;

/** The title's field and its problem line, for `view`. */
function titleField(view: EditorView, title: string, where: string, rename: RenameNote): HTMLElement {
  const wrap = document.createElement("div");
  wrap.className = "cm-note-title";
  const field = Object.assign(document.createElement("input"), { value: title, spellcheck: false, type: "text" });
  field.setAttribute("aria-label", "笔记标题");
  // Where the note lives, now that the card's head no longer says.
  field.title = where;
  const problem = Object.assign(document.createElement("p"), { className: "cm-note-title-problem" });
  problem.setAttribute("role", "alert");
  problem.hidden = true;
  wrap.append(field, problem);
  const say = (message: string | undefined) => {
    problem.textContent = message ?? "";
    problem.hidden = !message;
  };
  let busy = false;
  const commit = async () => {
    const name = field.value.trim();
    if (busy || name === title) {
      field.value = title;
      return;
    }
    busy = true;
    const reason = name ? await rename(name) : "标题不能为空。";
    busy = false;
    // Renamed, the note opens again under its new name; otherwise its old name comes back.
    if (reason) field.value = title;
    say(reason);
  };
  // Into the text, at its start.
  const toText = () => {
    view.focus();
    view.dispatch({ selection: { anchor: 0 }, scrollIntoView: true });
  };
  field.addEventListener("input", () => say(undefined));
  field.addEventListener("keydown", (event) => {
    if (event.isComposing) return;
    if (event.key === "Enter") {
      event.preventDefault();
      void commit();
      toText();
    } else if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      field.value = title;
      say(undefined);
      toText();
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      toText();
    }
  });
  field.addEventListener("blur", () => void commit());
  return wrap;
}

/** The editable title above the text of the note at `path`: in the editor's scroller, so it scrolls
 *  with the text, but outside the text itself, which stays the note's lines alone. */
export function inlineTitle(path: string, rename: RenameNote): Extension {
  const title = path.slice(path.lastIndexOf("/") + 1).replace(/\.md$/i, "");
  return ViewPlugin.define((view) => {
    const dom = titleField(view, title, path.split("/").join(" / "), rename);
    view.scrollDOM.insertBefore(dom, view.contentDOM);
    return { destroy: () => dom.remove() };
  });
}
