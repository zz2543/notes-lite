import React from "react";
import { AnimatePresence, motion } from "motion/react";
import { Paperclip, TextAa, Code, ArrowsOut, ArrowsIn, Plus } from "@phosphor-icons/react";
import { Doc } from "./Doc.jsx";
import { pathOf, spaces } from "./data.js";
import { useSpring } from "./motion.js";

function words(note) {
  return note ? (note.title + note.blocks.map((b) => b[1]).join("")).replace(/\s/g, "").length : 0;
}

export function EditorCard({ note, dir, typo, source, setSource, focus, setFocus, openTypography }) {
  const spring = useSpring();
  const [hover, setHover] = React.useState(false);
  const [typing, setTyping] = React.useState(false);
  const showTools = hover && !typing;

  return (
    <>
      <div
        className="card-top"
        onMouseEnter={() => { setHover(true); setTyping(false); }}
        onMouseLeave={() => setHover(false)}
        onMouseMove={() => typing && setTyping(false)}
      >
        {!focus && <span>{note ? `${pathOf(note)} / ${note.title}.md` : ""}</span>}
        <AnimatePresence>
          {showTools && !focus && (
            <motion.div
              className="tools"
              initial={{ opacity: 0, y: -4, filter: "blur(4px)" }}
              animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
              exit={{ opacity: 0, y: -2, filter: "blur(2px)", transition: { duration: 0.12 } }}
              transition={{ ...spring.浮现, filter: spring.blur }}
            >
              {[
                [Paperclip, "插入附件", () => {}],
                [TextAa, "排版设置", openTypography],
                [Code, source ? "退出源码" : "显示源码", () => setSource(!source)],
                [ArrowsOut, "专注模式 ⌘⇧F", () => setFocus(true)],
              ].map(([I, t, f]) => (
                <motion.button key={t} className="icon-btn" title={t} onClick={f} whileTap={{ scale: 0.88 }} transition={spring.轻弹}>
                  <I size={17} weight={t.includes("源码") && source ? "fill" : "regular"} />
                </motion.button>
              ))}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
      {focus && (
        <motion.button
          className="icon-btn focus-exit"
          title="退出专注 Esc"
          onClick={() => setFocus(false)}
          initial={{ opacity: 0 }}
          animate={{ opacity: 0.6 }}
          whileHover={{ opacity: 1 }}
          transition={{ delay: 0.25 }}
        >
          <ArrowsIn size={17} />
        </motion.button>
      )}
      <div className="card-scroll">
        <AnimatePresence initial={false} mode="popLayout" custom={dir}>
          <motion.div
            key={(note?.id ?? "none") + (source ? "-src" : "")}
            custom={dir * spring.amp}
            variants={{
              enter: (d) => ({ opacity: 0, y: d * 8 }),
              center: { opacity: 1, y: 0 },
              exit: (d) => ({ opacity: 0, y: -d * 4, transition: { duration: 0.1 } }),
            }}
            initial="enter"
            animate="center"
            exit="exit"
            transition={spring.滑移}
          >
            <Doc note={note} typo={typo} source={source} editable onTyping={() => setTyping(true)} />
          </motion.div>
        </AnimatePresence>
      </div>
      {!focus && (
        <div className="card-foot">
          <span>● 已保存 · 本地 Markdown</span>
          <span>{words(note)} 字</span>
        </div>
      )}
    </>
  );
}

export function SpaceHome({ spaceId }) {
  const spring = useSpring();
  const s = spaces.find((x) => x.id === spaceId);
  const bars = [3, 5, 2, 6, 4, 7, 5];
  const tiles = [["本周训练", "4", "次"], ["卧推最佳", "62.5", "kg"], ["连续打卡", "12", "天"]];
  return (
    <div className="card-scroll">
      <div className="space-home">
        <motion.h1 initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={spring.浮现}>
          {s.icon} {s.name}
        </motion.h1>
        <div className="scope">范围：{s.scope}</div>
        <div className="tiles">
          {tiles.map(([k, v, u], i) => (
            <motion.div
              key={k}
              className="tile"
              initial={{ opacity: 0, y: 14 * spring.amp, scale: 1 - 0.04 * spring.amp, filter: "blur(6px)" }}
              animate={{ opacity: 1, y: 0, scale: 1, filter: "blur(0px)" }}
              transition={{ ...spring.浮现, filter: { ...spring.blur, delay: 0.05 + i * 0.06 }, delay: 0.05 + i * 0.06 }}
            >
              <div className="k">{k}</div>
              <div className="v">{v}<small>{u}</small></div>
            </motion.div>
          ))}
        </div>
        <motion.div
          className="chart"
          initial={{ opacity: 0, y: 14, filter: "blur(6px)" }}
          animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
          transition={{ ...spring.浮现, filter: { ...spring.blur, delay: 0.24 }, delay: 0.24 }}
        >
          {bars.map((b, i) => (
            <motion.div
              key={i}
              className="bar"
              style={{ height: `${b * 12}%` }}
              initial={{ scaleY: 0 }}
              animate={{ scaleY: 1 }}
              transition={{ ...spring.展开, delay: 0.3 + i * 0.04 }}
            />
          ))}
        </motion.div>
        <motion.button
          className="chip"
          style={{ marginTop: 14, display: "inline-flex", alignItems: "center", gap: 6 }}
          whileTap={{ scale: 0.95 }}
          transition={spring.轻弹}
        >
          <Plus size={14} weight="bold" /> 快速记录
        </motion.button>
      </div>
    </div>
  );
}
