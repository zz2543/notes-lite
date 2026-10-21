// Formulas, drawn by the KaTeX that ships inside the app (with mhchem's \ce for chemistry, as in the old
// editor). It loads the first time a note has a formula, so notes without one never wait for it.
import type { EditorView } from "@codemirror/view";

type Katex = typeof import("katex").default;

let katex: Katex | null = null;
let loading: Promise<Katex> | null = null;
/** Formulas drawn as their TeX while KaTeX loads, to draw again once it is there. */
const waiting = new Set<{ el: HTMLElement; tex: string; display: boolean; view?: EditorView }>();

function load(): Promise<Katex> {
  loading ??= Promise.all([import("katex"), import("katex/dist/katex.min.css")]).then(async ([module]) => {
    await import("katex/contrib/mhchem");
    katex = module.default;
    for (const item of waiting) {
      if (item.el.isConnected) typesetTex(katex, item.el, item.tex, item.display);
      item.view?.requestMeasure();
    }
    waiting.clear();
    return katex;
  });
  // Should it fail to load, formulas keep showing their TeX, and the next one drawn tries again.
  loading.catch((error: unknown) => {
    console.error("KaTeX failed to load", error);
    for (const item of waiting) item.el.classList.remove("cm-tex-loading");
    waiting.clear();
    loading = null;
  });
  return loading;
}

function typesetTex(k: Katex, el: HTMLElement, tex: string, display: boolean) {
  el.classList.remove("cm-tex-loading");
  // A formula KaTeX can't read shows its TeX in the error colour, saying why when hovered.
  k.render(tex, el, { displayMode: display, throwOnError: false, output: "html", trust: false, strict: "ignore" });
}

/** Draws `tex` into `el`: at once when KaTeX is loaded, otherwise as its TeX until it is, after which
 *  the editor measures again for the formula's new size. */
export function renderTex(el: HTMLElement, tex: string, display: boolean, view?: EditorView) {
  if (katex) return typesetTex(katex, el, tex, display);
  el.classList.add("cm-tex-loading");
  el.textContent = tex;
  waiting.add({ el, tex, display, ...(view ? { view } : {}) });
  void load();
}
