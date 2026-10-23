// space.load("react"): React, htm (JSX without a build step) and Recharts, bundled with the app and
// served offline like ECharts, plus a few hooks and props that keep the charts on the app's design.
import htm from "htm";
import * as React from "react";
import * as ReactDOM from "react-dom/client";
import * as Recharts from "recharts";

// Written as in HTML: `class` and `for`, and `style` as a string ("height: 170px"), are taken as React
// wants them, so markup copied from the rest of the page works unchanged.
const camel = (name) => (name.startsWith("--") ? name : name.replace(/-([a-z])/g, (_, c) => c.toUpperCase()));
const styleObject = (text) => {
  const style = {};
  for (const part of text.split(";")) {
    const at = part.indexOf(":");
    if (at > 0) style[camel(part.slice(0, at).trim())] = part.slice(at + 1).trim();
  }
  return style;
};
function h(type, props, ...children) {
  if (props && typeof type === "string") {
    const { class: className, for: htmlFor, style, ...rest } = props;
    props = rest;
    if (className !== undefined) props.className = className;
    if (htmlFor !== undefined) props.htmlFor = htmlFor;
    if (style !== undefined) props.style = typeof style === "string" ? styleObject(style) : style;
  }
  return React.createElement(type, props, ...children);
}
const html = htm.bind(h);
const space = () => window.space;

/** The app's colours, type and motion setting, drawn again when 外观, 强调色 or 动效 change. */
function useTheme() {
  const [theme, setTheme] = React.useState(() => space().theme());
  React.useEffect(() => space().on("theme", setTheme), []);
  return theme;
}

/** space.query(source, options), read again whenever the notes change; undefined until first read. */
function useQuery(source, options) {
  const [rows, setRows] = React.useState();
  const [error, setError] = React.useState(null);
  const key = JSON.stringify([source, options && { ...options, filter: undefined }]);
  React.useEffect(() => {
    let live = true;
    const read = () =>
      space()
        .query(source, options)
        .then((next) => live && (setRows(next), setError(null)), (e) => live && setError(e));
    read();
    const off = space().on("change", read);
    return () => {
      live = false;
      off();
    };
  }, [key]);
  if (error) throw error;
  return rows;
}

/** Props for Recharts' parts that match the app: quiet axes, hairline grid, frosted tooltip. */
function chartProps(t) {
  const tick = { fill: t.muted, fontSize: 11, fontFamily: t.font };
  return {
    colors: t.chart,
    animate: !t.reducedMotion,
    xAxis: { tick, tickLine: false, axisLine: false, tickMargin: 8, minTickGap: 16 },
    yAxis: { tick, tickLine: false, axisLine: false, width: 36 },
    grid: { stroke: t.line, vertical: false },
    tooltip: {
      cursor: { stroke: t.muted, strokeDasharray: "3 3" },
      contentStyle: {
        background: t.card,
        border: "none",
        borderRadius: 12,
        boxShadow: "0 0 0 .5px rgba(127,127,127,.25), 0 8px 28px rgba(0,0,0,.18)",
        padding: "8px 12px",
        fontSize: 12,
        color: t.text,
      },
      labelStyle: { color: t.muted, marginBottom: 2 },
      itemStyle: { color: t.text, padding: 0 },
    },
    legend: { iconType: "circle", iconSize: 8, wrapperStyle: { fontSize: 11, color: t.muted } },
  };
}

/** Draws a component into an element (or a selector); drawn again into the same element replaces it. */
const roots = new WeakMap();
function mount(target, Component, props) {
  const element = typeof target === "string" ? document.querySelector(target) : target;
  if (!element || element.nodeType !== 1) throw Object.assign(new Error("mount 需要一个元素或能找到元素的选择器。"), { code: "invalid" });
  let root = roots.get(element);
  if (!root) {
    root = ReactDOM.createRoot(element);
    roots.set(element, root);
  }
  root.render(React.createElement(Component, props));
  return root;
}

window.SpaceReact = Object.freeze({ React, ReactDOM, html, Recharts, useTheme, useQuery, chartProps, mount });
