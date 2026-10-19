import React from "react";
import { AnimatePresence, motion } from "motion/react";
import { TextAa, X, Sparkle, SlidersHorizontal } from "@phosphor-icons/react";
import { useSpring } from "./motion.js";
import { Doc, fontStacks } from "./Doc.jsx";

export function useFloat() {
  const spring = useSpring();
  return {
    initial: { opacity: 0, scale: 1 - 0.06 * spring.amp, y: -10 * spring.amp, filter: "blur(10px)" },
    animate: { opacity: 1, scale: 1, y: 0, filter: "blur(0px)" },
    exit: { opacity: 0, scale: 0.97, y: -4, filter: "blur(6px)", transition: { duration: 0.16 } },
    transition: { ...spring.浮现, filter: spring.blur },
  };
}

function Scrim({ onClick }) {
  return (
    <motion.div className="scrim" onClick={onClick} initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.2 }} />
  );
}

const accents = [["跟随系统", null], ["蓝", "#0a84ff"], ["紫", "#8e5cf7"], ["粉", "#ff375f"], ["橙", "#ff9f0a"], ["绿", "#30d158"]];

function Chips({ value, options, onChange, id }) {
  const spring = useSpring();
  return (
    <div className="chips">
      {options.map(([k, l]) => (
        <motion.button key={k} className={`chip ${value === k ? "on" : ""}`} onClick={() => onChange(k)} whileTap={{ scale: 0.95 }} transition={spring.轻弹}>
          {value === k && <motion.span layoutId={id} className="pill" transition={spring.滑移} />}
          {l}
        </motion.button>
      ))}
    </div>
  );
}

function Switch({ on, onChange }) {
  const spring = useSpring();
  return (
    <button className={`switch ${on ? "on" : ""}`} onClick={() => onChange(!on)}>
      <motion.i layout transition={spring.轻弹} />
    </button>
  );
}

function Slider({ value, min, max, step, onChange, fmt }) {
  return (
    <div className="slider">
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />
      <span>{fmt ? fmt(value) : value}</span>
    </div>
  );
}

export function Settings({ close, tab, setTab, s, set, typo, setTypo, note, intensity, setIntensity }) {
  const spring = useSpring();
  const float = useFloat();
  const tabs = [["general", "通用", SlidersHorizontal], ["typography", "排版", TextAa], ["motion", "动画", Sparkle]];
  const t = (k) => (v) => setTypo({ ...typo, [k]: v });
  const fontOpts = Object.keys(fontStacks).map((k) => [k, k]);

  return (
    <div className="overlay">
      <Scrim onClick={close} />
      <motion.div className="glass settings" {...float}>
        <nav>
          <h3>设置</h3>
          {tabs.map(([k, l, I]) => (
            <motion.button key={k} className={`row ${tab === k ? "on" : ""}`} style={{ isolation: "isolate" }} onClick={() => setTab(k)} whileTap={{ scale: 0.97 }} transition={spring.轻弹}>
              {tab === k && <motion.span layoutId="setPill" className="pill" transition={spring.滑移} />}
              <I size={17} weight={tab === k ? "fill" : "regular"} />{l}
            </motion.button>
          ))}
        </nav>
        <div className="pane">
          <button className="icon-btn close" onClick={close}><X size={16} /></button>
          <AnimatePresence initial={false} mode="popLayout">
            <motion.div
              key={tab}
              className="pane-inner"
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6, transition: { duration: 0.1 } }}
              transition={spring.滑移}
            >
              {tab === "general" && (
                <>
                  <div className="field"><div className="fl">外观</div>
                    <Chips id="appearance" value={s.appearance} onChange={(v) => set({ appearance: v })} options={[["system", "跟随系统"], ["light", "浅色"], ["dark", "深色"]]} />
                  </div>
                  <div className="field"><div className="fl">强调色</div>
                    <div className="swatches">
                      {accents.map(([l, c]) => (
                        <motion.button key={l} title={l} className="swatch" whileTap={{ scale: 0.85 }} transition={spring.轻弹} onClick={() => set({ accent: c })}
                          style={{ background: c ?? "conic-gradient(#0a84ff, #8e5cf7, #ff375f, #ff9f0a, #30d158, #0a84ff)", color: c ?? "var(--card-fg)" }}>
                          {s.accent === c && <motion.span layoutId="accentRing" className="ring" transition={spring.轻弹} />}
                        </motion.button>
                      ))}
                    </div>
                    <div className="hint">“跟随系统”在原型里用各变体的默认色代替。</div>
                  </div>
                  <div className="field"><div className="fl">笔记列表</div>
                    <Chips id="detail" value={s.detail} onChange={(v) => set({ detail: v })} options={[["simple", "简洁"], ["standard", "标准"], ["detail", "详细"]]} />
                  </div>
                  <div className="field"><div className="fl">导航模式</div>
                    <Chips id="nav" value={s.nav} onChange={(v) => set({ nav: v })} options={[["double", "双栏：文件夹与目录内容"], ["single", "单栏：文件夹与笔记树"]]} />
                    <div className="hint">原型只实现了双栏导航。</div>
                  </div>
                </>
              )}
              {tab === "motion" && (
                <>
                  <div className="field"><div className="fl">动效强度</div>
                    <Chips id="intensity" value={intensity} onChange={setIntensity} options={[["轻", "轻"], ["标准", "标准"], ["强", "强（默认）"]]} />
                    <div className="hint">强度主要放大展开、浮现等转场；悬停、选中等高频反馈始终保持轻快。</div>
                  </div>
                  <div className="toggle-row">光标动画<Switch on={s.caretAnim} onChange={(v) => set({ caretAnim: v })} /></div>
                  <div className="toggle-row">输入动画<Switch on={s.typeAnim} onChange={(v) => set({ typeAnim: v })} /></div>
                  <div className="hint">光标与输入动效要在 CodeMirror 编辑器里单独验证，这个原型只保存开关。系统开启“减弱动态效果”时两者强制关闭。</div>
                </>
              )}
              {tab === "typography" && (
                <div className="typo">
                  <div className="controls">
                    <div className="field"><div className="fl">正文字体</div><Chips id="fbody" value={typo.body} onChange={t("body")} options={fontOpts} /></div>
                    <div className="field"><div className="fl">标题字体</div><Chips id="fhead" value={typo.heading} onChange={t("heading")} options={fontOpts} /></div>
                    <div className="field"><div className="fl">字号</div><Slider value={typo.size} min={14} max={22} step={1} onChange={t("size")} fmt={(v) => `${v}px`} /></div>
                    <div className="field"><div className="fl">行距</div><Slider value={typo.lineHeight} min={1.4} max={2.2} step={0.05} onChange={t("lineHeight")} fmt={(v) => v.toFixed(2)} /></div>
                    <div className="field"><div className="fl">段距</div><Slider value={typo.para} min={0} max={1.6} step={0.1} onChange={t("para")} fmt={(v) => `${v.toFixed(1)}em`} /></div>
                    <div className="field"><div className="fl">版心宽度</div><Slider value={typo.measure} min={480} max={900} step={10} onChange={t("measure")} fmt={(v) => `${v}px`} /></div>
                    <div className="field"><div className="fl">标题大小比例</div><Slider value={typo.headingScale} min={1.2} max={2} step={0.05} onChange={t("headingScale")} fmt={(v) => `${v.toFixed(2)}×`} /></div>
                    <div className="toggle-row">中英文自动间距<Switch on={typo.cjkSpacing} onChange={t("cjkSpacing")} /></div>
                  </div>
                  <div className="preview">
                    <Doc note={note} typo={typo} animateStyle />
                  </div>
                </div>
              )}
            </motion.div>
          </AnimatePresence>
        </div>
      </motion.div>
    </div>
  );
}

export function Toast({ text }) {
  const float = useFloat();
  return (
    <motion.div className="glass toast" {...float}>{text}</motion.div>
  );
}

