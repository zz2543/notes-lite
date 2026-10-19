// PROTOTYPE 助手栏 and 形象实验台. The conversation is scripted; no agent runs.
import React from "react";
import { AnimatePresence, motion } from "motion/react";
import { CaretDown, ClockCounterClockwise, Folder, X, ArrowUp, CheckCircle, FileText, MagnifyingGlass, PencilSimple, CaretRight, ArrowCounterClockwise } from "@phosphor-icons/react";
import { Figure, FIGURE_STATES } from "./Figure.jsx";
import { useSpring } from "./motion.js";

const AGENTS = ["Claude Code", "Codex", "DeepSeek Harness", "Pi"];

// One scripted turn: the figure walks through the working states, steps land on the timeline.
const SCRIPT = [
  ["think", 1400, null],
  ["search", 1300, [MagnifyingGlass, "搜索“散步”相关笔记"]],
  ["read", 1300, [FileText, "读取 3 篇笔记"]],
  ["write", 1600, [PencilSimple, "修改《雨后的散步》《清晨的片段》"]],
  ["done", 1400, null],
];

export function AssistantPanel({ figureState, setFigureState, note, workdir, look, reduced, onClose, floating }) {
  const spring = useSpring();
  const [agent, setAgent] = React.useState(AGENTS[0]);
  const [menu, setMenu] = React.useState(false);
  const [msgs, setMsgs] = React.useState([
    { who: "user", text: "帮我把这周的散步记录整理成一段小结。" },
    { who: "agent", text: "已整理：两篇笔记里的散步片段合并成一段，放在《雨后的散步》末尾。", steps: [[FileText, "读取 2 篇笔记"], [PencilSimple, "修改《雨后的散步》"]], review: "kept" },
  ]);
  const [draft, setDraft] = React.useState("");
  const [ctxNote, setCtxNote] = React.useState(true);
  const busy = figureState !== "idle" && figureState !== "done" && figureState !== "wait" && figureState !== "error";
  const scroller = React.useRef(null);

  React.useEffect(() => { scroller.current?.scrollTo({ top: 1e6, behavior: "smooth" }); }, [msgs]);
  React.useEffect(() => {
    if (!menu) return;
    const close = () => setMenu(false);
    window.addEventListener("pointerdown", close);
    return () => window.removeEventListener("pointerdown", close);
  }, [menu]);

  const send = () => {
    if (!draft.trim() || busy) return;
    const text = draft.trim();
    setDraft("");
    setMsgs((m) => [...m, { who: "user", text }, { who: "agent", text: "", steps: [], pending: true }]);
    let at = 0;
    SCRIPT.forEach(([st, ms, step]) => {
      setTimeout(() => {
        setFigureState(st);
        if (step) setMsgs((m) => { const c = [...m]; const last = { ...c[c.length - 1] }; last.steps = [...last.steps, step]; c[c.length - 1] = last; return c; });
        if (st === "done") {
          setMsgs((m) => { const c = [...m]; c[c.length - 1] = { ...c[c.length - 1], pending: false, text: "改好了：两篇笔记的结尾各补了一句今天的观察，并统一了日期格式。", review: "open" }; return c; });
        }
      }, at);
      at += ms;
    });
    setTimeout(() => setFigureState("idle"), at);
  };

  const setReview = (i, v) => setMsgs((m) => m.map((x, j) => (j === i ? { ...x, review: v } : x)));

  return (
    <div className={`assistant ${floating ? "glass floating" : ""}`}>
      <div className="as-head">
        <Figure state={figureState} size={48} {...look} reduced={reduced} />
        <div className="as-title">
          <div className="as-name">助手</div>
          <button className="as-agent" onPointerDown={(e) => e.stopPropagation()} onClick={() => setMenu((x) => !x)}>
            {agent}<CaretDown size={11} weight="bold" />
          </button>
        </div>
        <motion.button className="icon-btn" whileTap={{ scale: 0.88 }} transition={spring.轻弹} title="对话历史"><ClockCounterClockwise size={17} /></motion.button>
        <motion.button className="icon-btn" whileTap={{ scale: 0.88 }} transition={spring.轻弹} title="收起助手栏 ⌘J" onClick={onClose}><X size={16} /></motion.button>
        <AnimatePresence>
          {menu && (
            <motion.div className="menu" style={{ top: 58, left: 62, transformOrigin: "top left" }} onPointerDown={(e) => e.stopPropagation()}
              initial={{ opacity: 0, scale: 0.92, y: -4 }} animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96, transition: { duration: 0.12 } }} transition={spring.展开}>
              <div className="lbl">本机已安装</div>
              {AGENTS.map((a) => (
                <button key={a} className="mi" onClick={() => { setAgent(a); setMenu(false); }}>
                  <span className="ck">{a === agent && <CheckCircle size={13} weight="fill" />}</span>{a}
                </button>
              ))}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
      <button className="as-dir" title="跳到工作目录"><Folder size={13} />工作目录：{workdir}</button>

      <div className="as-body" ref={scroller}>
        {msgs.map((m, i) => (
          <motion.div key={i} className={`as-msg ${m.who}`} initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={spring.滑移}>
            <div className="as-bubble">
              {m.steps?.length > 0 && <Timeline steps={m.steps} />}
              {m.pending && !m.text ? <span className="as-typing">{FIGURE_STATES.find((s) => s[0] === figureState)?.[1]}…</span> : m.text}
              {m.review && <Review state={m.review} onKeep={() => setReview(i, "kept")} onRevert={() => setReview(i, "reverted")} />}
            </div>
          </motion.div>
        ))}
      </div>

      <div className="as-composer">
        <AnimatePresence>
          {ctxNote && note && (
            <motion.div className="as-chip" initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.9 }} transition={spring.轻弹}>
              <FileText size={12} />{note.title}
              <button onClick={() => setCtxNote(false)}><X size={10} weight="bold" /></button>
            </motion.div>
          )}
        </AnimatePresence>
        <div className="as-input">
          <textarea rows={2} placeholder="问助手，或用 @ 提及笔记…" value={draft} onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); } }} />
          <motion.button className="as-send" disabled={busy || !draft.trim()} whileTap={{ scale: 0.88 }} transition={spring.轻弹} onClick={send}>
            <ArrowUp size={15} weight="bold" />
          </motion.button>
        </div>
      </div>
    </div>
  );
}

function Timeline({ steps }) {
  const spring = useSpring();
  const [open, setOpen] = React.useState(false);
  return (
    <div className="as-steps">
      <button className="as-steps-head" onClick={() => setOpen((o) => !o)}>
        <motion.span animate={{ rotate: open ? 90 : 0 }} transition={spring.展开} style={{ display: "grid" }}><CaretRight size={10} weight="bold" /></motion.span>
        {steps.length} 个步骤
      </button>
      <AnimatePresence initial={false}>
        {open && (
          <motion.div initial={{ height: 0, opacity: 0 }} animate={{ height: "auto", opacity: 1 }} exit={{ height: 0, opacity: 0 }} transition={spring.展开} style={{ overflow: "hidden" }}>
            {steps.map(([I, t], i) => <div key={i} className="as-step"><I size={12} />{t}</div>)}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

function Review({ state, onKeep, onRevert }) {
  const spring = useSpring();
  return (
    <AnimatePresence mode="popLayout" initial={false}>
      {state === "open" ? (
        <motion.div key="open" className="as-review" initial={{ opacity: 0, y: 6, scale: 0.97 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0, scale: 0.97 }} transition={spring.浮现}>
          <div className="as-review-title">本轮改动了 2 篇笔记</div>
          <div className="as-review-file"><FileText size={12} />雨后的散步 <span>+1 行</span></div>
          <div className="as-review-file"><FileText size={12} />清晨的片段 <span>+1 −1 行</span></div>
          <div className="as-review-actions">
            <button className="as-btn primary" onClick={onKeep}>全部保留</button>
            <button className="as-btn" onClick={onRevert}>撤回本轮</button>
          </div>
        </motion.div>
      ) : (
        <motion.div key={state} className="as-review-done" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={spring.滑移}>
          {state === "kept" ? <><CheckCircle size={12} weight="fill" />已保留 · 可在操作记录中撤销</> : <><ArrowCounterClockwise size={12} />已撤回本轮改动</>}
        </motion.div>
      )}
    </AnimatePresence>
  );
}

export function FigureLab({ look, reduced, onClose }) {
  const spring = useSpring();
  const [st, setSt] = React.useState("idle");
  const [auto, setAuto] = React.useState(false);
  React.useEffect(() => {
    if (!auto) return;
    const seq = ["idle", "think", "search", "read", "write", "run", "done", "idle", "wait", "error"];
    let i = 0;
    setSt(seq[0]);
    const id = setInterval(() => { i = (i + 1) % seq.length; setSt(seq[i]); }, 1800);
    return () => clearInterval(id);
  }, [auto]);
  return (
    <div className="overlay">
      <motion.div className="scrim" onClick={onClose} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} />
      <motion.div className="glass lab" initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.96, transition: { duration: 0.15 } }} transition={spring.浮现}>
        <button className="icon-btn close" onClick={onClose}><X size={16} /></button>
        <div className="lab-title">助手形象 · 实验台</div>
        <div className="lab-stage"><Figure state={st} size={220} {...look} reduced={reduced} /></div>
        <div className="lab-sizes">
          <div><Figure state={st} size={48} {...look} reduced={reduced} /><span>48 · 助手栏</span></div>
          <div><Figure state={st} size={22} {...look} reduced={reduced} detail="small" /><span>22 · 收起时的按钮</span></div>
        </div>
        <div className="chips lab-states">
          {FIGURE_STATES.map(([k, l]) => (
            <button key={k} className={`chip ${st === k ? "on" : ""}`} onClick={() => { setAuto(false); setSt(k); }}>
              {st === k && <motion.span layoutId="labPill" className="pill" transition={spring.滑移} />}{l}
            </button>
          ))}
          <button className={`chip ${auto ? "on" : ""}`} onClick={() => setAuto((a) => !a)}>
            {auto && <span className="pill" />}自动轮播
          </button>
        </div>
      </motion.div>
    </div>
  );
}
