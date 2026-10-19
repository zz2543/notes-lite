import React from "react";
import { AnimatePresence, motion } from "motion/react";
import {
  MagnifyingGlass, NotePencil, Folder, FolderOpen, CaretRight, HardDrives, CaretUpDown,
} from "@phosphor-icons/react";
import { folders, spaces } from "./data.js";
import { useSpring } from "./motion.js";

function Row({ on, onClick, icon, label, count, caret, depth = 0, pillId, trailing, onHover }) {
  const spring = useSpring();
  return (
    <motion.button
      className={`row ${on ? "on" : ""}`}
      style={{ paddingLeft: 10 + depth * 16, isolation: "isolate" }}
      onClick={onClick}
      onHoverStart={() => onHover?.(true)}
      onHoverEnd={() => onHover?.(false)}
      whileTap={{ scale: 0.97 }}
      transition={spring.轻弹}
    >
      {on && <motion.span layoutId={pillId} className="pill" transition={spring.滑移} />}
      {caret}
      {icon}
      <span>{label}</span>
      {count != null && <span className="count">{count}</span>}
      {trailing}
    </motion.button>
  );
}

function FolderRow({ f, depth, isOn, isOpen, setSel, toggle, newIn }) {
  const spring = useSpring();
  const [hover, setHover] = React.useState(false);
  const Icon = isOn ? FolderOpen : Folder;
  const click = () => {
    // Click selects and opens; clicking the selected, open folder closes it; clicking again reopens.
    if (!isOn) { setSel(f.id); if (!isOpen) toggle(f.id); return; }
    toggle(f.id);
  };
  return (
    <Row
      on={isOn}
      pillId="sidePill"
      depth={depth}
      onClick={click}
      onHover={setHover}
      caret={
        <span
          className="caret"
          style={{ visibility: f.children.length ? "visible" : "hidden" }}
          onClick={(e) => { e.stopPropagation(); toggle(f.id); }}
        >
          <motion.span animate={{ rotate: isOpen ? 90 : 0 }} transition={spring.展开} style={{ display: "grid" }}>
            <CaretRight size={11} weight="bold" />
          </motion.span>
        </span>
      }
      icon={<Icon size={17} weight={isOn ? "fill" : "regular"} />}
      label={f.name}
      trailing={
        <AnimatePresence>
          {hover && (
            <motion.span
              className="row-new"
              title={`在“${f.name}”中新建笔记`}
              initial={{ opacity: 0, scale: 0.6 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.6, transition: { duration: 0.1 } }}
              transition={spring.轻弹}
              whileTap={{ scale: 0.85 }}
              onClick={(e) => { e.stopPropagation(); newIn(f.id); }}
            >
              <NotePencil size={15} />
            </motion.span>
          )}
        </AnimatePresence>
      }
    />
  );
}

function Tree({ nodes, depth, sel, setSel, open, toggle, newIn }) {
  const spring = useSpring();
  return nodes.map((f) => {
    const isOn = sel === f.id;
    const isOpen = open.has(f.id);
    return (
      <div key={f.id}>
        <FolderRow f={f} depth={depth} isOn={isOn} isOpen={isOpen} setSel={setSel} toggle={toggle} newIn={newIn} />
        <AnimatePresence initial={false}>
          {isOpen && f.children.length > 0 && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={spring.展开}
              style={{ overflow: "hidden" }}
            >
              <Tree nodes={f.children} depth={depth + 1} sel={sel} setSel={setSel} open={open} toggle={toggle} newIn={newIn} />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    );
  });
}

export function Sidebar({ view, setView, sel, setSel, space, setSpace, openSearch, newIn }) {
  const spring = useSpring();
  const [open, setOpen] = React.useState(new Set(["daily"]));
  const toggle = (id) => setOpen((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const dir = view === "spaces" ? 1 : -1;

  return (
    <div className="side">
      <div className="side-top">
        <div className="lights"><i /><i /><i /></div>
      </div>

      <div className="seg">
        {[["library", "资料库"], ["spaces", "空间"]].map(([k, l]) => (
          <button key={k} className={view === k ? "on" : ""} onClick={() => setView(k)}>
            {view === k && <motion.span layoutId="segPill" className="seg-pill" transition={spring.滑移} />}
            {l}
          </button>
        ))}
      </div>

      <div className="side-body">
        <AnimatePresence initial={false} custom={dir}>
          <motion.div
            key={view}
            className="side-pane"
            custom={dir}
            variants={{
              enter: (d) => ({ x: d * 60 * spring.amp, opacity: 0 }),
              center: { x: 0, opacity: 1 },
              exit: (d) => ({ x: -d * 60 * spring.amp, opacity: 0 }),
            }}
            initial="enter"
            animate="center"
            exit="exit"
            transition={spring.滑移}
          >
            {view === "library" ? (
              <>
                <div className="side-label side-label-row">
                  <span>文件夹</span>
                  <motion.button className="icon-btn sm" whileTap={{ scale: 0.88 }} transition={spring.轻弹} onClick={openSearch} title="搜索 ⌘K">
                    <MagnifyingGlass size={15} />
                  </motion.button>
                </div>
                <Tree nodes={folders} depth={0} sel={sel} setSel={setSel} open={open} toggle={toggle} newIn={newIn} />
              </>
            ) : (
              <>
                <div className="side-label">空间</div>
                {spaces.map((s) => (
                  <Row key={s.id} on={space === s.id} pillId="spacePill" onClick={() => setSpace(s.id)} icon={<span style={{ width: 17, textAlign: "center" }}>{s.icon}</span>} label={s.name} />
                ))}
              </>
            )}
          </motion.div>
        </AnimatePresence>
      </div>

      <div className="side-foot">
        <HardDrives size={15} />
        <span>我的笔记库</span>
        <CaretUpDown size={13} style={{ marginLeft: "auto" }} />
      </div>
    </div>
  );
}
