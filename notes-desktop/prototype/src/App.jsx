// PROTOTYPE: three visual variants of the notes-desktop main window, switchable via ?variant=A|B|C
// and the black bar at the bottom. Throwaway — answers "what should it look and move like".
import React from "react";
import { AnimatePresence, LayoutGroup, MotionConfig, motion } from "motion/react";
import { notes as seed, inFolder, folders } from "./data.js";
import { MotionPresets, presets } from "./motion.js";
import { Sidebar } from "./Sidebar.jsx";
import { NoteList } from "./NoteList.jsx";
import { EditorCard, SpaceHome } from "./Card.jsx";
import { Settings, Toast } from "./Overlays.jsx";

const VARIANTS = [["A", "原生材质"], ["B", "渐变磨砂"], ["C", "大胆高饱和"]];
const spaceFolder = { fit: "daily", ielts: "projects", read: "reading" };

function folderName(id) {
  const walk = (nodes) => { for (const f of nodes) { if (f.id === id) return f.name; const r = walk(f.children); if (r) return r; } };
  return walk(folders);
}

function editing() {
  const el = document.activeElement;
  return el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable);
}

export default function App() {
  const [variant, setVariantState] = React.useState(() => new URLSearchParams(location.search).get("variant") ?? "A");
  const setVariant = (v) => { setVariantState(v); const u = new URL(location.href); u.searchParams.set("variant", v); history.replaceState(null, "", u); };
  const [intensity, setIntensity] = React.useState("强");
  const [reduced, setReduced] = React.useState(false);
  const [s, setS] = React.useState({ appearance: "light", accent: null, detail: "simple", nav: "double", caretAnim: true, typeAnim: true });
  const set = (patch) => setS((x) => ({ ...x, ...patch }));
  const [typo, setTypo] = React.useState({ body: "系统无衬线", heading: "系统无衬线", size: 17, lineHeight: 1.8, para: 0.9, measure: 680, headingScale: 1.6, cjkSpacing: true });

  const [all, setAll] = React.useState(seed);
  const [view, setView] = React.useState("library");
  const [sel, setSel] = React.useState("daily");
  const [space, setSpace] = React.useState("fit");
  const [current, setCurrent] = React.useState("n1");
  const [spaceCurrent, setSpaceCurrent] = React.useState("home");
  const [dir, setDir] = React.useState(1);
  const [focus, setFocus] = React.useState(false);
  const [source, setSource] = React.useState(false);
  const [search, setSearch] = React.useState(null);
  const [settings, setSettings] = React.useState(null);
  const [toast, setToast] = React.useState(null);

  const sysDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  const mode = s.appearance === "system" ? (sysDark ? "dark" : "light") : s.appearance;

  const folderSel = sel;
  const q = search?.q.trim().toLowerCase();
  const items = search
    ? all.filter((n) => (search.scope === "all" || inFolder(n, folderSel)) && (!q || n.title.toLowerCase().includes(q) || n.blocks.some((b) => b[1].toLowerCase().includes(q))))
    : view === "spaces"
    ? all.filter((n) => inFolder(n, spaceFolder[space]))
    : all.filter((n) => inFolder(n, sel));
  const listTitle = search ? "搜索" : view === "spaces" ? "文件" : folderName(sel);
  const active = view === "spaces" ? spaceCurrent : current;
  const note = all.find((n) => n.id === active);

  const select = (id) => {
    if (search) {
      const n = all.find((x) => x.id === id);
      setSearch(null); setView("library"); setSel(n.folder); setDir(1); setCurrent(id);
      return;
    }
    const ids = ["home", ...items.map((n) => n.id)];
    setDir(ids.indexOf(id) >= ids.indexOf(active) ? 1 : -1);
    view === "spaces" ? setSpaceCurrent(id) : setCurrent(id);
  };

  const flash = (text) => { setToast(text); setTimeout(() => setToast(null), 1800); };

  const run = (cmd, arg) => {
    if (cmd === "new") {
      const folder = arg ?? sel;
      const n = { id: `new${Date.now()}`, folder, date: "10/19", title: "未命名笔记", blocks: [] };
      setAll((a) => [n, ...a]); setView("library"); if (arg) setSel(arg); setDir(-1); setCurrent(n.id);
    }
    if (cmd === "focus") setFocus((f) => !f);
    if (cmd === "source") setSource((x) => !x);
    if (cmd === "settings") setSettings("general");
    if (cmd === "typography") setSettings("typography");
    if (cmd === "vault") flash("原型不切换真实笔记库");
  };

  React.useEffect(() => {
    const onKey = (e) => {
      const mod = e.metaKey || e.ctrlKey;
      if (mod && e.key.toLowerCase() === "k") { e.preventDefault(); setSearch((x) => (x ? null : { q: "", scope: "all" })); return; }
      if (mod && e.shiftKey && e.key.toLowerCase() === "f") { e.preventDefault(); setFocus((f) => !f); return; }
      if (mod && e.key === ",") { e.preventDefault(); setSettings("general"); return; }
      if (mod && e.key.toLowerCase() === "n") { e.preventDefault(); run("new"); return; }
      if (e.key === "Escape") {
        if (search) { setSearch(null); return; }
        if (settings) { setSettings(null); return; }
        if (focus) { setFocus(false); return; }
      }
      if (editing() || settings) return;
      if (e.key === "ArrowLeft" || e.key === "ArrowRight") {
        const i = VARIANTS.findIndex((v) => v[0] === variant);
        const next = VARIANTS[(i + (e.key === "ArrowRight" ? 1 : VARIANTS.length - 1)) % VARIANTS.length][0];
        setVariant(next);
      }
      if ((e.key === "ArrowDown" || e.key === "ArrowUp") && !focus) {
        e.preventDefault();
        const ids = [...(view === "spaces" ? ["home"] : []), ...items.map((n) => n.id)];
        const i = ids.indexOf(active);
        const j = Math.max(0, Math.min(ids.length - 1, i + (e.key === "ArrowDown" ? 1 : -1)));
        if (j !== i) select(ids[j]);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const spring = presets(intensity);
  const stageStyle = s.accent ? { "--accent": s.accent } : {};
  const card = (
    <motion.div layoutId="card" className="card" transition={spring.浮现}>
      {view === "spaces" && spaceCurrent === "home" ? (
        <SpaceHome key={space} spaceId={space} />
      ) : (
        <EditorCard
          note={note}
          dir={dir}
          typo={typo}
          source={source}
          setSource={setSource}
          focus={focus}
          setFocus={setFocus}
          openTypography={() => setSettings("typography")}
        />
      )}
    </motion.div>
  );

  return (
    <MotionPresets.Provider value={spring}>
      <MotionConfig reducedMotion={reduced ? "always" : "never"}>
        <div className="stage" data-v={variant} data-m={mode} style={stageStyle}>
          <div className="win">
            <LayoutGroup>
              <motion.div animate={{ opacity: focus ? 0 : 1, x: focus ? -12 : 0 }} transition={spring.浮现} style={{ display: "flex", minWidth: 0, pointerEvents: focus ? "none" : "auto" }}>
                <Sidebar
                  view={view}
                  setView={(v) => setView(v)}
                  sel={sel}
                  setSel={(id) => setSel(id)}
                  space={space}
                  setSpace={(id) => { setSpace(id); setSpaceCurrent("home"); }}
                  openSearch={() => setSearch({ q: "", scope: "all" })}
                  newIn={(id) => run("new", id)}
                />
              </motion.div>
              <motion.div animate={{ opacity: focus ? 0 : 1, x: focus ? -8 : 0 }} transition={spring.浮现} style={{ display: "flex", minWidth: 0, pointerEvents: focus ? "none" : "auto" }}>
                <NoteList
                  title={listTitle}
                  items={items}
                  current={active}
                  onSelect={select}
                  detail={s.detail}
                  setDetail={(d) => set({ detail: d })}
                  crossFolder={false}
                  homeRow={view === "spaces" && !search}
                  search={search}
                  setSearch={setSearch}
                  folderLabel={folderSel ? folderName(folderSel) : null}
                />
              </motion.div>
              <div className="main">{!focus && card}</div>
              <AnimatePresence>
                {focus && (
                  <motion.div key="dim" className="focus-dim" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.3 }} />
                )}
              </AnimatePresence>
              {focus && <div className="focus-layer">{card}</div>}
            </LayoutGroup>

            <AnimatePresence>
              {settings && (
                <Settings key="set" close={() => setSettings(null)} tab={settings} setTab={setSettings} s={s} set={set} typo={typo} setTypo={setTypo} note={note ?? all[0]} intensity={intensity} setIntensity={setIntensity} />
              )}
            </AnimatePresence>
            <AnimatePresence>{toast && <Toast key="toast" text={toast} />}</AnimatePresence>
          </div>
        </div>

        <ProtoBar variant={variant} setVariant={setVariant} intensity={intensity} setIntensity={setIntensity} mode={mode} setMode={(m) => set({ appearance: m })} reduced={reduced} setReduced={setReduced} />
      </MotionConfig>
    </MotionPresets.Provider>
  );
}

function ProtoBar({ variant, setVariant, intensity, setIntensity, mode, setMode, reduced, setReduced }) {
  const i = VARIANTS.findIndex((v) => v[0] === variant);
  const go = (d) => setVariant(VARIANTS[(i + d + VARIANTS.length) % VARIANTS.length][0]);
  return (
    <div className="protobar">
      <span className="tag">PROTOTYPE</span>
      <button onClick={() => go(-1)}>←</button>
      <span className="vl">{variant} · {VARIANTS[i]?.[1]}</span>
      <button onClick={() => go(1)}>→</button>
      <span className="div" />
      <span style={{ opacity: 0.6 }}>动效</span>
      {["轻", "标准", "强"].map((k) => (
        <button key={k} className={intensity === k ? "on" : ""} onClick={() => setIntensity(k)}>{k}</button>
      ))}
      <span className="div" />
      <button className={mode === "light" ? "on" : ""} onClick={() => setMode("light")}>浅</button>
      <button className={mode === "dark" ? "on" : ""} onClick={() => setMode("dark")}>深</button>
      <span className="div" />
      <button className={reduced ? "on" : ""} onClick={() => setReduced(!reduced)}>减弱动态</button>
    </div>
  );
}
