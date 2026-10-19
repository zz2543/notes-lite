// Renders a sample note with the current 排版设置. Shared by the editor card and the typography preview.
import React from "react";
import { motion } from "motion/react";
import { useSpring } from "./motion.js";

export const fontStacks = {
  系统无衬线: '-apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif',
  思源宋体: '"Noto Serif SC", "Songti SC", serif',
  "Source Serif 4 + 思源宋体": '"Source Serif 4", "Noto Serif SC", "Songti SC", serif',
  等宽: 'ui-monospace, "SF Mono", Menlo, "Microsoft YaHei", monospace',
};

const cjk = /([一-鿿])([A-Za-z0-9])|([A-Za-z0-9])([一-鿿])/g;
function space(text, on) {
  if (!on) return text;
  return text.replace(cjk, (m, a, b, c, d) => (a ? `${a} ${b}` : `${c} ${d}`));
}

export function docStyle(t) {
  return {
    "--body-font": fontStacks[t.body],
    "--heading-font": fontStacks[t.heading],
    "--fs": `${t.size}px`,
    "--lh": t.lineHeight,
    "--para": `${t.para}em`,
    "--measure": `${t.measure}px`,
    "--hs": t.headingScale,
  };
}

function toMarkdown(note) {
  const out = [`# ${note.title}`, ""];
  for (const [k, v] of note.blocks) {
    if (k === "p") out.push(v, "");
    if (k === "h2") out.push(`## ${v}`, "");
    if (k === "quote") out.push(`> ${v}`, "");
    if (k === "li") out.push(`- ${v}`);
  }
  return out.join("\n");
}

export function Doc({ note, typo, source, editable, onTyping, animateStyle }) {
  const spring = useSpring();
  if (!note) return null;
  if (source) {
    return (
      <div className="doc source" contentEditable={editable} suppressContentEditableWarning spellCheck={false} onKeyDown={onTyping}>
        {toMarkdown(note)}
      </div>
    );
  }
  const items = [];
  let list = [];
  note.blocks.forEach(([k, v], i) => {
    if (k === "li") { list.push(<li key={i}>{space(v, typo.cjkSpacing)}</li>); return; }
    if (list.length) { items.push(<ul key={`u${i}`}>{list}</ul>); list = []; }
    if (k === "p") items.push(<p key={i}>{space(v, typo.cjkSpacing)}</p>);
    if (k === "h2") items.push(<h2 key={i}>{space(v, typo.cjkSpacing)}</h2>);
    if (k === "quote") items.push(<blockquote key={i}>{space(v, typo.cjkSpacing)}</blockquote>);
  });
  if (list.length) items.push(<ul key="u-end">{list}</ul>);
  const style = docStyle(typo);
  const Tag = animateStyle ? motion.div : "div";
  const motionProps = animateStyle
    ? { animate: { fontSize: `${typo.size}px`, maxWidth: `${typo.measure}px`, lineHeight: typo.lineHeight }, transition: spring.滑移 }
    : {};
  return (
    <Tag
      className="doc"
      style={style}
      contentEditable={editable}
      suppressContentEditableWarning
      spellCheck={false}
      onKeyDown={onTyping}
      {...motionProps}
    >
      <h1>{space(note.title, typo.cjkSpacing)}</h1>
      {items.length ? items : <p style={{ opacity: 0.4 }}>开始书写…</p>}
    </Tag>
  );
}
