import { EditorView, ViewPlugin, type PluginValue, type ViewUpdate } from "@codemirror/view";
import { caretMotion } from "./motion";

// 光标动画 (ticket 11, 2026-10-23 用户确认): the insertion caret slides from place to place as Word's smooth
// caret does — typing, deleting, the arrow keys, a click, and pinyin as it is composed and committed. The
// browser's own caret is made transparent and one drawn caret stands for it; the browser still owns the
// selection, hit testing and the input method, so nothing about typing changes. Off (the switch in 设置 ›
// 动画, or the system's 减弱动态效果), the editor keeps the browser's caret as before.

interface Place {
  x: number;
  y: number;
  height: number;
}

/** Where the caret is, in the scroller's content: the input method's text while composing, else the head. */
function measure(view: EditorView): Place | null {
  const { main } = view.state.selection;
  if (!view.hasFocus || !main.empty) return null;
  let rect: { left: number; top: number; bottom: number } | null = null;
  if (view.composing) {
    // The composed pinyin may be ahead of the state: the browser's own selection says where it is.
    const selection = view.root instanceof Document ? view.root.getSelection() : null;
    if (selection && selection.rangeCount > 0 && view.contentDOM.contains(selection.focusNode)) {
      const range = selection.getRangeAt(0).cloneRange();
      range.collapse(false);
      const box = range.getClientRects()[0];
      if (box && box.height > 0) rect = box;
    }
  }
  rect ??= view.coordsAtPos(main.head, main.assoc || 1) ?? view.coordsAtPos(main.head, -1);
  if (!rect) return null;
  const scroller = view.scrollDOM;
  const frame = scroller.getBoundingClientRect();
  return {
    x: rect.left - frame.left + scroller.scrollLeft - scroller.clientLeft,
    y: rect.top - frame.top + scroller.scrollTop - scroller.clientTop,
    height: rect.bottom - rect.top,
  };
}

const at = ({ x, y }: Place) => `translate(${x}px, ${y}px)`;

class SmoothCaret implements PluginValue {
  private readonly caret: HTMLDivElement;
  private place: Place | null = null;
  private travel?: Animation;
  private blinking?: Animation;
  /** Whether the next move slides: one the user made (an edit, the selection, the input method). */
  private moved = false;
  private readonly onComposition = () => this.schedule(true);

  constructor(private readonly view: EditorView) {
    this.caret = document.createElement("div");
    this.caret.className = "cm-smooth-caret";
    this.caret.setAttribute("aria-hidden", "true");
    view.scrollDOM.appendChild(this.caret);
    view.contentDOM.addEventListener("compositionupdate", this.onComposition);
    view.contentDOM.addEventListener("compositionend", this.onComposition);
    this.schedule(false);
  }

  update(update: ViewUpdate) {
    const moved = update.docChanged || update.selectionSet;
    if (moved || update.focusChanged || update.geometryChanged || update.viewportChanged) this.schedule(moved);
  }

  private schedule(moved: boolean) {
    this.moved ||= moved;
    this.view.requestMeasure({ key: this, read: (view) => measure(view), write: (place) => this.draw(place) });
  }

  private draw(target: Place | null) {
    const slide = this.moved;
    this.moved = false;
    const caret = this.caret;
    if (!target) {
      this.travel?.cancel();
      this.blinking?.cancel();
      caret.style.display = "none";
      this.place = null;
      return;
    }
    const before = this.place;
    if (before && before.x === target.x && before.y === target.y && before.height === target.height) return;
    // Mid-slide, it goes on from where it is drawn now, not from where the last slide was headed.
    const shown = before && this.travel?.playState === "running" ? this.shownPlace(before) : before;
    this.travel?.cancel();
    this.place = target;
    caret.style.display = "";
    caret.style.transform = at(target);
    caret.style.height = `${target.height}px`;
    const far = shown && Math.abs(target.y - shown.y) > this.view.scrollDOM.clientHeight;
    if (slide && shown && !far) {
      this.travel = caret.animate(
        [
          { transform: at(shown), height: `${shown.height}px` },
          { transform: at(target), height: `${target.height}px` },
        ],
        { duration: caretMotion.slide * 1000, easing: "ease-out" },
      );
    }
    // Lit while it moves; it starts blinking once it rests.
    this.blinking?.cancel();
    this.blinking = caret.animate([{ opacity: 1 }, { opacity: 1, offset: 0.38 }, { opacity: 0, offset: 0.5 }, { opacity: 0, offset: 0.88 }, { opacity: 1 }], {
      duration: caretMotion.blink * 1000,
      delay: caretMotion.rest * 1000,
      iterations: Infinity,
    });
  }

  /** The place the caret is drawn at this moment, part way through a slide. */
  private shownPlace(fallback: Place): Place {
    const style = getComputedStyle(this.caret);
    const matrix = new DOMMatrixReadOnly(style.transform === "none" ? undefined : style.transform);
    const height = parseFloat(style.height);
    return { x: matrix.m41, y: matrix.m42, height: Number.isFinite(height) ? height : fallback.height };
  }

  destroy() {
    this.travel?.cancel();
    this.blinking?.cancel();
    this.view.contentDOM.removeEventListener("compositionupdate", this.onComposition);
    this.view.contentDOM.removeEventListener("compositionend", this.onComposition);
    this.caret.remove();
  }
}

/** The smooth caret, for an editor whose 光标动画 is on. */
export const smoothCaret = [
  ViewPlugin.fromClass(SmoothCaret),
  // The browser's caret stays where it is, unseen; the drawn one is seen in its place.
  EditorView.contentAttributes.of({ class: "cm-smooth-caret-on" }),
];
