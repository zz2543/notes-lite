import React from "react";
import { AnimatePresence, motion } from "motion/react";
import { DotsThree, Check, Folder, House, MagnifyingGlass, X } from "@phosphor-icons/react";
import { summary, pathOf } from "./data.js";
import { useSpring } from "./motion.js";

const levels = [["simple", "简洁：只显示标题"], ["standard", "标准：标题与日期"], ["detail", "详细：标题、摘要与日期"]];

export function NoteList({ title, items, current, onSelect, detail, setDetail, crossFolder, homeRow, search, setSearch, folderLabel }) {
  const spring = useSpring();
  const [menu, setMenu] = React.useState(false);

  React.useEffect(() => {
    if (!menu) return;
    const close = () => setMenu(false);
    window.addEventListener("pointerdown", close);
    return () => window.removeEventListener("pointerdown", close);
  }, [menu]);

  return (
    <div className="list">
      <div className="list-head" style={{ position: "relative" }}>
        <AnimatePresence initial={false} mode="popLayout">
          {search ? (
            <motion.div
              key="search"
              className="search-head"
              initial={{ opacity: 0, scaleX: 0.92, y: -4 }}
              animate={{ opacity: 1, scaleX: 1, y: 0 }}
              exit={{ opacity: 0, scaleX: 0.96, transition: { duration: 0.12 } }}
              transition={spring.展开}
            >
              <div className="search-box">
                <MagnifyingGlass size={15} style={{ opacity: 0.55 }} />
                <input
                  autoFocus
                  placeholder="搜索标题和正文"
                  value={search.q}
                  onChange={(e) => setSearch({ ...search, q: e.target.value })}
                  onKeyDown={(e) => {
                    if (e.key === "Escape") setSearch(null);
                    if (e.key === "Enter" && items[0]) onSelect(items[0].id);
                  }}
                />
                <motion.button className="icon-btn sm" whileTap={{ scale: 0.85 }} transition={spring.轻弹} onClick={() => setSearch(null)} title="退出搜索 Esc">
                  <X size={13} />
                </motion.button>
              </div>
              <div className="search-scope">
                {[["all", "全库"], ["folder", folderLabel ? `“${folderLabel}”及子文件夹` : "当前文件夹"]].map(([k, l]) => (
                  <button key={k} disabled={k === "folder" && !folderLabel} className={search.scope === k ? "on" : ""} onClick={() => setSearch({ ...search, scope: k })}>
                    {search.scope === k && <motion.span layoutId="scopePill" className="scope-pill" transition={spring.滑移} />}
                    {l}
                  </button>
                ))}
              </div>
            </motion.div>
          ) : (
            <motion.div
              key="title"
              className="title-head"
              initial={{ opacity: 0, y: 4 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, transition: { duration: 0.1 } }}
              transition={spring.滑移}
            >
              <h2>{title}</h2>
              <span className="badge">{items.length}</span>
              <motion.button className="icon-btn" whileTap={{ scale: 0.9 }} transition={spring.轻弹} onPointerDown={(e) => e.stopPropagation()} onClick={() => setMenu((m) => !m)}>
                <DotsThree size={20} weight="bold" />
              </motion.button>
            </motion.div>
          )}
        </AnimatePresence>
        <AnimatePresence>
          {menu && !search && (
            <motion.div
              className="menu"
              style={{ top: 44, right: 10 }}
              initial={{ opacity: 0, scale: 0.92, y: -4 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96, y: -2, transition: { duration: 0.12 } }}
              transition={spring.展开}
              onPointerDown={(e) => e.stopPropagation()}
            >
              <div className="lbl">列表详细程度</div>
              {levels.map(([k, l]) => (
                <button key={k} className="mi" onClick={() => { setDetail(k); setMenu(false); }}>
                  <span className="ck">{detail === k && <Check size={13} weight="bold" />}</span>
                  {l}
                </button>
              ))}
              <div className="sep" />
              <button className="mi" onClick={() => setMenu(false)}><span className="ck" />按修改时间排序</button>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
      <div className="list-body">
        {homeRow && (
          <motion.button className={`note-row ${current === "home" ? "on" : ""}`} whileTap={{ scale: 0.97 }} transition={spring.轻弹} onClick={() => onSelect("home")}>
            {current === "home" && <motion.span layoutId="listPill" className="pill" transition={spring.滑移} />}
            <div className="t"><span style={{ display: "flex", alignItems: "center", gap: 6 }}><House size={15} weight={current === "home" ? "fill" : "regular"} />主页</span></div>
          </motion.button>
        )}
        <AnimatePresence initial={false} mode="popLayout">
          {items.map((n) => (
            <motion.button
              layout="position"
              key={n.id}
              className={`note-row ${current === n.id ? "on" : ""}`}
              initial={{ opacity: 0, y: -6 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.96 }}
              whileTap={{ scale: 0.97 }}
              transition={spring.滑移}
              onClick={() => onSelect(n.id)}
            >
              {current === n.id && <motion.span layoutId="listPill" className="pill" transition={spring.滑移} />}
              <div className="t">
                <span>{n.title}</span>
                {detail !== "simple" && <span className="d">{n.date}</span>}
              </div>
              {detail === "detail" && summary(n) && <div className="s">{summary(n)}</div>}
              {search && search.q && summary(n) && detail !== "detail" && <div className="s">{summary(n)}</div>}
              {(search || (detail === "detail" && crossFolder)) && (
                <div className="p"><Folder size={12} />{pathOf(n)}</div>
              )}
            </motion.button>
          ))}
        </AnimatePresence>
        {search && search.q && items.length === 0 && <div className="list-empty">没有找到“{search.q}”</div>}
      </div>
    </div>
  );
}
