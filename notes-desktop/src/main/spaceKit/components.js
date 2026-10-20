// 空间主页小组件：space-stat、space-chart、space-calendar、space-records、space-quick-add，以及旧名
// lb-* 的永久别名。组件是通用的，只认识记录表和字段；数据只经过 space 接口读写，变化后自动重绘。
// 颜色、字体与动效都取样式包的变量（--space-*），入场跟随动效预设（浮现、展开、滑移、轻弹）。
// Ported from the old app's components.js (ticket 20).
(() => {
  "use strict";
  const api = window.space;
  if (!api || !window.customElements) return;

  // MARK: helpers

  const reduceMotion = () => window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  /** A motion preset (pop, slide, expand, emerge) as the style kit declares it: WAAPI timing in ms. */
  const preset = (name) => {
    const style = getComputedStyle(document.documentElement);
    const time = (value) => { const v = value.trim(); return v.endsWith("ms") ? parseFloat(v) : parseFloat(v) * 1000; };
    return {
      duration: time(style.getPropertyValue(`--space-${name}-duration`)) || 400,
      visual: time(style.getPropertyValue(`--space-${name}-visual`)) || 300,
      easing: style.getPropertyValue(`--space-${name}-easing`).trim() || "ease-out",
    };
  };
  const easeOut = (t) => 1 - Math.pow(1 - t, 3);
  const list = (value) => (value || "").split(",").map((s) => s.trim()).filter(Boolean);
  const escape = (s) => String(s == null ? "" : s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const parseDate = (s) => {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(s || ""));
    return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null;
  };
  const dayKey = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
  const format = (n, digits) => {
    if (n == null || Number.isNaN(n)) return "—";
    const max = digits != null && digits !== "" ? +digits : Math.abs(n) >= 100 ? 0 : Math.abs(n) >= 10 ? 1 : 2;
    return new Intl.NumberFormat("zh-CN", { maximumFractionDigits: max, minimumFractionDigits: digits != null && digits !== "" ? +digits : 0 }).format(n);
  };
  // To the 错误条 (the interface listens for "space:problem"), and the console.
  const report = (message) => {
    console.error(message);
    window.dispatchEvent(new CustomEvent("space:problem", { detail: { message } }));
  };
  const firstOfType = (fields, type) => (fields || []).find((f) => f.type === type);
  const inPeriod = (period) => {
    const now = new Date();
    const today = startOfDay(now);
    switch (period) {
      case "today": return (d) => d && d.getTime() === today.getTime();
      case "week": {
        const monday = new Date(today); monday.setDate(today.getDate() - ((today.getDay() + 6) % 7));
        return (d) => d && d >= monday && d <= today;
      }
      case "month": return (d) => d && d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth();
      case "year": return (d) => d && d.getFullYear() === now.getFullYear();
      default: return null;
    }
  };
  const periodLabel = { today: "今天", week: "本周", month: "本月", year: "今年" };
  const aggregate = (values, op) => {
    const nums = values.filter((v) => typeof v === "number");
    switch (op) {
      case "count": return values.length;
      case "sum": return nums.reduce((a, b) => a + b, 0);
      case "avg": return nums.length ? nums.reduce((a, b) => a + b, 0) / nums.length : null;
      case "max": return nums.length ? Math.max(...nums) : null;
      case "min": return nums.length ? Math.min(...nums) : null;
      case "last": case "latest": return values.length ? values[values.length - 1] : null;
      default: return nums.reduce((a, b) => a + b, 0);
    }
  };
  /** Tween a number with requestAnimationFrame; returns a cancel function. */
  const tween = (from, to, duration, step, done) => {
    if (reduceMotion() || document.visibilityState !== "visible" || from === to || from == null || to == null) { step(to, 1); if (done) done(); return () => {}; }
    const start = performance.now();
    let frame = 0, finished = false;
    const finish = () => { if (finished) return; finished = true; cancelAnimationFrame(frame); step(to, 1); if (done) done(); };
    const tick = (now) => {
      const t = Math.min(1, (now - start) / duration);
      if (t >= 1) { finish(); return; }
      step(from + (to - from) * easeOut(t), t);
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    // Frames stop when the page is hidden mid-tween; the final value still lands.
    const fallback = setTimeout(finish, duration + 80);
    return () => { finished = true; cancelAnimationFrame(frame); clearTimeout(fallback); };
  };

  const baseStyle = `
    :host { display: block; font: inherit; color: var(--space-text); }
    *, *::before, *::after { box-sizing: border-box; }
    .title { font-size: 0.92em; font-weight: 600; margin: 0 0 10px; color: var(--space-text); letter-spacing: -0.005em; }
    .muted { color: var(--space-muted); }
    .empty, .problem { font-size: 0.92em; color: var(--space-muted); padding: 6px 0; }
    .problem { color: var(--space-bad); }
    .fade { animation: fade var(--space-slide-duration) var(--space-ease) both; }
    @keyframes fade { from { opacity: 0; transform: translateY(3px); } to { opacity: 1; transform: none; } }
    @media (prefers-reduced-motion: reduce) { .fade { animation: none; } }
  `;

  /** Shared plumbing: shadow root, attribute-driven refresh, lb change subscription, coalesced redraws. */
  class SpaceElement extends HTMLElement {
    constructor() {
      super();
      this.root = this.attachShadow({ mode: "open" });
      this.root.innerHTML = `<style>${baseStyle}${this.constructor.style || ""}</style><div class="body"></div>`;
      this.body = this.root.querySelector(".body");
      this.pending = false;
      this.generation = 0;
    }
    connectedCallback() {
      if (!this.unsubscribe) this.unsubscribe = api.on("change", () => this.refresh());
      this.refresh();
    }
    disconnectedCallback() { if (this.unsubscribe) { this.unsubscribe(); this.unsubscribe = null; } }
    attributeChangedCallback() { if (this.isConnected) this.refresh(); }
    attr(name, fallback) { const v = this.getAttribute(name); return v == null || v === "" ? fallback : v; }
    refresh() {
      if (this.pending) return;
      this.pending = true;
      // A task rather than a frame: hidden pages pause frames, but their data must still be current.
      setTimeout(async () => {
        this.pending = false;
        const generation = ++this.generation;
        try {
          const data = await this.load();
          if (generation === this.generation) this.draw(data);
        } catch (e) {
          if (generation !== this.generation) return;
          this.body.innerHTML = `<div class="problem">${escape(this.localName)}：${escape(e && e.message ? e.message : e)}</div>`;
          report(`<${this.localName}> ${e && e.message ? e.message : e}`);
        }
      }, 0);
    }
    header() { const t = this.attr("title", ""); return t ? `<div class="title">${escape(t)}</div>` : ""; }
    async rows() {
      const source = this.attr("source", "");
      if (!source) throw new Error("缺少 source 属性。");
      return api.query(source);
    }
  }

  // MARK: <lb-stat>

  class SpaceStat extends SpaceElement {
    static get observedAttributes() { return ["source", "op", "field", "period", "date-field", "label", "unit", "digits", "color"]; }
    static style = `
      .label { font-size: 0.88em; color: var(--space-muted); display: flex; gap: 6px; align-items: baseline; }
      .period { font-size: 0.81em; padding: 1px 6px; border-radius: 99px; background: var(--space-accent-soft); color: var(--space-text); opacity: 0.8; }
      .value { font-size: 2.31em; font-weight: 650; letter-spacing: -0.02em; line-height: 1.15; margin-top: 6px; font-variant-numeric: tabular-nums; }
      .unit { font-size: 1em; font-weight: 500; color: var(--space-muted); margin-left: 4px; }
    `;
    async load() {
      const rows = await this.rows();
      const op = this.attr("op", "count");
      const field = this.attr("field", "");
      if (op !== "count" && !field) throw new Error(`op="${op}" 需要 field 属性。`);
      const period = this.attr("period", "all");
      const test = inPeriod(period);
      let picked = rows;
      if (test) {
        const dateField = this.attr("date-field", (firstOfType(rows.fields, "date") || {}).name);
        if (!dateField) throw new Error(`period="${period}" 需要日期字段，请设置 date-field。`);
        picked = rows.filter((r) => test(parseDate(r[dateField])));
      }
      const values = op === "count" ? picked : picked.map((r) => r[field]).filter((v) => v != null);
      return { value: aggregate(values, op), period };
    }
    draw({ value, period }) {
      const label = this.attr("label", "");
      const unit = this.attr("unit", "");
      const digits = this.getAttribute("digits");
      const color = this.attr("color", "");
      if (!this.valueNode) {
        this.body.innerHTML = `${this.header()}<div class="label"><span class="name"></span><span class="period"></span></div><div class="value"><span class="number"></span><span class="unit"></span></div>`;
        this.valueNode = this.body.querySelector(".number");
      }
      this.body.querySelector(".name").textContent = label;
      const p = this.body.querySelector(".period");
      p.textContent = periodLabel[period] || ""; p.style.display = periodLabel[period] ? "" : "none";
      this.body.querySelector(".unit").textContent = unit;
      this.body.querySelector(".value").style.color = color || "";
      const numeric = typeof value === "number" ? value : null;
      if (this.cancel) this.cancel();
      if (numeric == null) { this.valueNode.textContent = value == null ? "—" : String(value); this.shown = null; return; }
      const from = this.shown == null ? 0 : this.shown;
      // Counting up follows 展开; a later change glides over 滑移.
      const duration = this.shown == null ? preset("expand").visual * 1.6 : preset("slide").visual * 1.5;
      this.valueNode.textContent = format(from, digits);
      this.shown = numeric;
      this.cancel = tween(from, numeric, duration, (v) => { this.valueNode.textContent = format(v, digits); });
    }
  }

  // MARK: <lb-chart>

  const smoothPath = (points) => {
    if (points.length < 2) return points.length ? `M${points[0][0]},${points[0][1]}` : "";
    // Monotone cubic interpolation keeps the curve from overshooting between records.
    const n = points.length, dx = [], m = [], t = [];
    for (let i = 0; i < n - 1; i++) { dx[i] = points[i + 1][0] - points[i][0]; m[i] = (points[i + 1][1] - points[i][1]) / (dx[i] || 1); }
    t[0] = m[0]; t[n - 1] = m[n - 2];
    for (let i = 1; i < n - 1; i++) t[i] = m[i - 1] * m[i] <= 0 ? 0 : (m[i - 1] + m[i]) / 2;
    let d = `M${points[0][0]},${points[0][1]}`;
    for (let i = 0; i < n - 1; i++) {
      const [x0, y0] = points[i], [x1, y1] = points[i + 1], h = dx[i] / 3;
      d += ` C${x0 + h},${y0 + t[i] * h} ${x1 - h},${y1 - t[i + 1] * h} ${x1},${y1}`;
    }
    return d;
  };
  /** Dense series show only the latest point until hovered, so the line reads as one stroke. */
  const dotRadius = (count, last) => (count <= 14 ? 3.2 : last ? 3.6 : 0);
  const niceTicks = (min, max, count) => {
    if (min === max) { const pad = Math.abs(min) * 0.1 || 1; min -= pad; max += pad; }
    const span = max - min, step0 = span / count;
    const mag = Math.pow(10, Math.floor(Math.log10(step0)));
    const step = [1, 2, 2.5, 5, 10].map((k) => k * mag).find((s) => s >= step0) || step0;
    const lo = Math.floor(min / step) * step, hi = Math.ceil(max / step) * step;
    const ticks = [];
    for (let v = lo; v <= hi + step / 2; v += step) ticks.push(+v.toFixed(10));
    return ticks;
  };

  class SpaceChart extends SpaceElement {
    static get observedAttributes() { return ["source", "x", "y", "type", "agg", "limit", "height", "title", "unit", "color"]; }
    static style = `
      .wrap { position: relative; }
      svg { display: block; width: 100%; overflow: visible; }
      .grid line { stroke: var(--space-line); }
      .axis text { fill: var(--space-muted); font-size: 0.77em; font-variant-numeric: tabular-nums; }
      .line { fill: none; stroke-width: 2.2; stroke-linecap: round; stroke-linejoin: round; }
      .dot { stroke: var(--space-card, var(--space-bg)); stroke-width: 2; transition: r var(--space-pop-duration) var(--space-pop-easing); }
      .bar { transition: opacity 0.16s ease; }
      .guide { stroke: var(--space-muted); stroke-dasharray: 2 3; opacity: 0; transition: opacity 0.15s ease; }
      .legend { display: flex; gap: 12px; font-size: 0.85em; color: var(--space-muted); margin: -4px 0 8px; }
      .legend i { display: inline-block; width: 8px; height: 8px; border-radius: 3px; margin-right: 5px; vertical-align: 0; }
      .tip { position: absolute; pointer-events: none; background: var(--space-text); color: var(--space-bg); font-size: 0.85em; line-height: 1.45;
             padding: 6px 9px; border-radius: 8px; white-space: nowrap; opacity: 0; transform: translate(-50%, -6px) scale(0.96);
             transition: opacity 0.14s ease, transform var(--space-pop-duration) var(--space-pop-easing); box-shadow: 0 6px 16px rgba(0,0,0,.14); }
      .tip.on { opacity: 1; transform: translate(-50%, -10px) scale(1); }
      .tip b { font-weight: 600; }
    `;
    connectedCallback() {
      super.connectedCallback();
      if (!this.resize && window.ResizeObserver) {
        this.resize = new ResizeObserver(() => { if (this.data) this.render(this.data, false); });
        this.resize.observe(this);
      }
    }
    async load() {
      const rows = await this.rows();
      const x = this.attr("x", (firstOfType(rows.fields, "date") || (rows.fields || [])[0] || {}).name);
      const ys = list(this.attr("y", ""));
      if (!x) throw new Error("缺少 x 属性。");
      if (!ys.length) throw new Error("缺少 y 属性。");
      const xType = ((rows.fields || []).find((f) => f.name === x) || {}).type;
      const agg = this.attr("agg", "sum");
      const groups = new Map();
      for (const r of rows) {
        const key = r[x];
        if (key == null) continue;
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(r);
      }
      let keys = [...groups.keys()];
      if (xType === "date" || xType === "number") keys.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
      const limit = +this.attr("limit", 0);
      if (limit > 0) keys = keys.slice(-limit);
      const series = ys.map((y) => keys.map((k) => {
        const values = groups.get(k).map((r) => (agg === "count" ? 1 : r[y])).filter((v) => v != null);
        const v = aggregate(values, agg === "count" ? "sum" : agg);
        return typeof v === "number" ? v : null;
      }));
      return { keys, ys, series, xType };
    }
    draw(data) {
      const animate = !this.data || this.data.keys.join() !== data.keys.join() || this.data.ys.join() !== data.ys.join();
      const previous = this.data;
      this.data = data;
      this.render(data, animate, animate ? null : previous);
    }
    colors(n) {
      const custom = list(this.attr("color", ""));
      return Array.from({ length: n }, (_, i) => custom[i] || `var(--space-chart-${(i % 6) + 1})`);
    }
    render(data, animate, previous) {
      const { keys, ys, series } = data;
      const type = this.attr("type", "line") === "bar" ? "bar" : "line";
      const unit = this.attr("unit", "");
      const height = +this.attr("height", 180);
      const width = Math.max(220, this.clientWidth || 480);
      if (!keys.length) {
        this.body.innerHTML = `${this.header()}<div class="empty">还没有记录。</div>`;
        return;
      }
      const pad = { l: 38, r: 10, t: 10, b: 24 };
      const W = width - pad.l - pad.r, H = height - pad.t - pad.b;
      const all = series.flat().filter((v) => v != null);
      const lo = type === "bar" ? Math.min(0, ...all) : Math.min(...all), hi = Math.max(...all, type === "bar" ? 0 : -Infinity);
      const ticks = niceTicks(lo, hi, 4);
      const t0 = ticks[0], t1 = ticks[ticks.length - 1];
      const X = (i) => pad.l + (keys.length === 1 ? W / 2 : type === "bar" ? (i + 0.5) * (W / keys.length) : (i / (keys.length - 1)) * W);
      const Y = (v) => pad.t + H - ((v - t0) / (t1 - t0 || 1)) * H;
      const colors = this.colors(ys.length);
      const labelEvery = Math.max(1, Math.ceil(keys.length / Math.max(2, Math.floor(W / 64))));
      const shortKey = (k) => (data.xType === "date" ? String(k).slice(5) : String(k));
      let svg = `<svg viewBox="0 0 ${width} ${height}" height="${height}" role="img" aria-label="${escape(this.attr("title", ys.join("、")))}">`;
      svg += `<g class="grid">${ticks.map((t) => `<line x1="${pad.l}" x2="${width - pad.r}" y1="${Y(t)}" y2="${Y(t)}"/>`).join("")}</g>`;
      svg += `<g class="axis">${ticks.map((t) => `<text x="${pad.l - 8}" y="${Y(t) + 3.5}" text-anchor="end">${format(t)}</text>`).join("")}`;
      svg += keys.map((k, i) => (i % labelEvery === 0 || i === keys.length - 1 ? `<text x="${X(i)}" y="${height - 6}" text-anchor="middle">${escape(shortKey(k))}</text>` : "")).join("") + `</g>`;
      svg += `<defs>${colors.map((c, s) => `<linearGradient id="g${s}" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="${c}" stop-opacity="0.22"/><stop offset="1" stop-color="${c}" stop-opacity="0"/></linearGradient>`).join("")}</defs>`;
      if (type === "bar") {
        const slot = W / keys.length, groupW = Math.min(slot * 0.68, 46), barW = groupW / ys.length;
        series.forEach((values, s) => {
          values.forEach((v, i) => {
            if (v == null) return;
            const x = X(i) - groupW / 2 + s * barW, y0 = Y(Math.max(0, t0)), y = Y(v);
            const h = Math.abs(y0 - y);
            svg += `<rect class="bar" data-i="${i}" x="${x + 1}" y="${Math.min(y, y0)}" width="${Math.max(2, barW - 2)}" height="${Math.max(1, h)}" rx="${Math.min(5, barW / 3)}" fill="${colors[s]}" style="transform-origin: ${x}px ${y0}px"/>`;
          });
        });
      } else {
        series.forEach((values, s) => {
          const points = values.map((v, i) => (v == null ? null : [X(i), Y(v)])).filter(Boolean);
          const path = smoothPath(points);
          if (points.length > 1 && ys.length === 1) {
            svg += `<path class="area" d="${path} L${points[points.length - 1][0]},${pad.t + H} L${points[0][0]},${pad.t + H} Z" fill="url(#g${s})"/>`;
          }
          svg += `<path class="line" d="${path}" stroke="${colors[s]}"/>`;
          svg += points.map((p, i) => `<circle class="dot" cx="${p[0]}" cy="${p[1]}" r="${dotRadius(keys.length, i === points.length - 1)}" fill="${colors[s]}"/>`).join("");
        });
      }
      svg += `<line class="guide" x1="0" x2="0" y1="${pad.t}" y2="${pad.t + H}"/>`;
      svg += `<rect class="hit" x="${pad.l}" y="${pad.t}" width="${W}" height="${H}" fill="transparent"/></svg>`;
      const legend = ys.length > 1 ? `<div class="legend">${ys.map((y, s) => `<span><i style="background:${colors[s]}"></i>${escape(y)}</span>`).join("")}</div>` : "";
      this.body.innerHTML = `${this.header()}${legend}<div class="wrap">${svg}<div class="tip"></div></div>`;
      const root = this.body.querySelector("svg");
      if (animate && !reduceMotion()) this.enter(root, type);
      else if (previous && !reduceMotion()) this.morph(root, type, data, previous, { X, Y, t0, H, pad });
      this.hover(root, { X, Y, keys, series, ys, unit, colors, type, W });
    }
    /** Drawn in on 展开: bars grow and dots pop on its spring; the line traces without one, as a bounce would gap it. */
    enter(svg, type) {
      const expand = preset("expand");
      const ease = getComputedStyle(document.documentElement).getPropertyValue("--space-ease").trim() || "ease-out";
      if (type === "bar") {
        svg.querySelectorAll(".bar").forEach((bar, i) => {
          bar.animate([{ transform: "scaleY(0)", opacity: 0.4 }, { transform: "scaleY(1)", opacity: 1 }],
            { duration: expand.duration, delay: Math.min(i * 28, 320), easing: expand.easing, fill: "backwards" });
        });
        return;
      }
      svg.querySelectorAll(".line").forEach((line) => {
        const length = line.getTotalLength();
        line.animate([{ strokeDasharray: `${length} ${length}`, strokeDashoffset: length }, { strokeDasharray: `${length} ${length}`, strokeDashoffset: 0 }],
          { duration: expand.visual * 2, easing: ease });
      });
      svg.querySelectorAll(".area").forEach((area) => area.animate([{ opacity: 0 }, { opacity: 1 }], { duration: expand.visual * 1.6, delay: expand.visual * 0.6, easing: ease, fill: "backwards" }));
      svg.querySelectorAll(".dot").forEach((dot, i, all) => {
        dot.animate([{ opacity: 0, transform: "scale(0.4)" }, { opacity: 1, transform: "scale(1)" }],
          { duration: expand.duration, delay: expand.visual * 0.3 + (i / Math.max(1, all.length)) * expand.visual * 1.5, easing: expand.easing, fill: "backwards" });
        dot.style.transformBox = "fill-box"; dot.style.transformOrigin = "center";
      });
    }
    /** Same x values, new y values: glide from the old shape to the new one. */
    morph(svg, type, data, previous, g) {
      const duration = preset("slide").visual * 1.7;
      if (type === "bar") {
        svg.querySelectorAll(".bar").forEach((bar) => {
          const i = +bar.dataset.i;
          const before = previous.series[0] && previous.series[0][i];
          if (before == null) return;
          const toY = +bar.getAttribute("y"), toH = +bar.getAttribute("height");
          const y0 = g.Y(Math.max(0, g.t0)), fromY = Math.min(g.Y(before), y0), fromH = Math.abs(y0 - g.Y(before));
          tween(0, 1, duration, (t) => { bar.setAttribute("y", fromY + (toY - fromY) * t); bar.setAttribute("height", Math.max(1, fromH + (toH - fromH) * t)); });
        });
        return;
      }
      const lines = svg.querySelectorAll(".line"), areas = svg.querySelectorAll(".area"), dots = svg.querySelectorAll(".dot");
      tween(0, 1, duration, (t) => {
        let d = 0;
        data.series.forEach((values, s) => {
          const pts = values.map((v, i) => {
            if (v == null) return null;
            const was = previous.series[s] ? previous.series[s][i] : null;
            return [g.X(i), g.Y(was == null ? v : was + (v - was) * t)];
          }).filter(Boolean);
          const path = smoothPath(pts);
          if (lines[s]) lines[s].setAttribute("d", path);
          if (areas[s] && pts.length > 1) areas[s].setAttribute("d", `${path} L${pts[pts.length - 1][0]},${g.pad.t + g.H} L${pts[0][0]},${g.pad.t + g.H} Z`);
          pts.forEach((p) => { if (dots[d]) dots[d].setAttribute("cy", p[1]); d++; });
        });
      });
    }
    hover(svg, g) {
      const tip = this.body.querySelector(".tip"), guide = svg.querySelector(".guide"), hit = svg.querySelector(".hit");
      const scale = () => svg.getBoundingClientRect().width / +svg.getAttribute("viewBox").split(" ")[2];
      let last = -1;
      const show = (event) => {
        const box = svg.getBoundingClientRect(), k = scale();
        const x = (event.clientX - box.left) / k;
        let i = 0, best = Infinity;
        g.keys.forEach((_, j) => { const d = Math.abs(g.X(j) - x); if (d < best) { best = d; i = j; } });
        guide.setAttribute("x1", g.X(i)); guide.setAttribute("x2", g.X(i)); guide.style.opacity = g.type === "bar" ? 0 : 0.6;
        const rows = g.ys.map((y, s) => `<div><span style="color:${g.colors[s]}">●</span> ${escape(y)} <b>${format(g.series[s][i])}${escape(g.unit)}</b></div>`).join("");
        tip.innerHTML = `<div class="muted" style="color:inherit;opacity:.7">${escape(g.keys[i])}</div>${rows}`;
        const top = Math.min(...g.series.map((v) => (v[i] == null ? Infinity : g.Y(v[i]))));
        tip.style.left = `${g.X(i) * k}px`; tip.style.top = `${(Number.isFinite(top) ? top : 20) * k - 8}px`;
        tip.style.transform = ""; tip.classList.add("on");
        if (i !== last) {
          svg.querySelectorAll(".dot").forEach((dot, j, all) => dot.setAttribute("r", Math.abs(+dot.getAttribute("cx") - g.X(i)) < 0.5 ? 4.6 : dotRadius(g.keys.length, +dot.getAttribute("cx") >= g.X(g.keys.length - 1) - 0.5)));
          svg.querySelectorAll(".bar").forEach((bar) => { bar.style.opacity = +bar.dataset.i === i ? 1 : 0.55; });
          last = i;
        }
      };
      const hide = () => {
        tip.classList.remove("on"); guide.style.opacity = 0; last = -1;
        svg.querySelectorAll(".dot").forEach((dot) => dot.setAttribute("r", dotRadius(g.keys.length, +dot.getAttribute("cx") >= g.X(g.keys.length - 1) - 0.5)));
        svg.querySelectorAll(".bar").forEach((bar) => { bar.style.opacity = 1; });
      };
      hit.addEventListener("mousemove", show);
      hit.addEventListener("mouseleave", hide);
    }
  }

  // MARK: <lb-calendar>

  class SpaceCalendar extends SpaceElement {
    static get observedAttributes() { return ["source", "field", "value", "weeks", "label", "title", "color"]; }
    static style = `
      .head { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 10px; }
      .label { font-size: 0.92em; font-weight: 600; }
      .summary { font-size: 0.85em; color: var(--space-muted); font-variant-numeric: tabular-nums; }
      .grid { display: grid; grid-auto-flow: column; grid-auto-columns: 12px; grid-template-rows: 14px repeat(7, 12px); gap: 3px; overflow-x: auto; padding-bottom: 2px; }
      .month { font-size: 0.73em; color: var(--space-muted); grid-row: 1; white-space: nowrap; width: 12px; overflow: visible; line-height: 12px; }
      .cell { width: 12px; height: 12px; border-radius: 3.5px; background: var(--space-line); transition: transform var(--space-pop-duration) var(--space-pop-easing); }
      .cell:hover { transform: scale(1.25); }
      .cell.today { box-shadow: 0 0 0 1.5px var(--space-text) inset; }
      .cell.future { visibility: hidden; }
      .scale { display: flex; gap: 3px; align-items: center; justify-content: flex-end; font-size: 0.77em; color: var(--space-muted); margin-top: 8px; }
      .scale .cell { width: 10px; height: 10px; }
    `;
    async load() {
      const rows = await this.rows();
      const field = this.attr("field", (firstOfType(rows.fields, "date") || {}).name);
      if (!field) throw new Error("没有日期字段，请设置 field 属性。");
      const valueField = this.attr("value", "");
      const totals = new Map();
      for (const r of rows) {
        const d = parseDate(r[field]);
        if (!d) continue;
        const add = valueField ? (typeof r[valueField] === "number" ? r[valueField] : 0) : 1;
        totals.set(dayKey(d), (totals.get(dayKey(d)) || 0) + add);
      }
      return { totals };
    }
    connectedCallback() {
      super.connectedCallback();
      if (!this.resize && window.ResizeObserver) {
        let width = 0;
        this.resize = new ResizeObserver(() => {
          if (this.getAttribute("weeks") || !this.totals || Math.abs(this.clientWidth - width) < 15) return;
          width = this.clientWidth; this.draw({ totals: this.totals });
        });
        this.resize.observe(this);
      }
    }
    draw({ totals }) {
      this.totals = totals;
      // Without a weeks attribute the calendar fills its card.
      const fit = Math.floor(((this.clientWidth || 300) + 3) / 15);
      const weeks = Math.max(1, Math.min(60, +this.attr("weeks", Math.max(8, fit))));
      const color = this.attr("color", "var(--space-accent)");
      const today = startOfDay(new Date());
      const end = new Date(today); end.setDate(today.getDate() + (6 - ((today.getDay() + 6) % 7)));
      const start = new Date(end); start.setDate(end.getDate() - weeks * 7 + 1);
      const max = Math.max(0, ...totals.values());
      const level = (v) => (!v ? 0 : max <= 1 ? 4 : Math.min(4, Math.ceil((v / max) * 4)));
      const fill = (l) => (l === 0 ? "" : `background: color-mix(in srgb, ${color} ${[0, 28, 48, 68, 86][l]}%, var(--space-line))`);
      let html = "", active = 0, lastMonth = -1;
      for (let w = 0; w < weeks; w++) {
        const monday = new Date(start); monday.setDate(start.getDate() + w * 7);
        const month = monday.getMonth();
        html += `<div class="month" style="grid-column:${w + 1}">${month !== lastMonth && monday.getDate() <= 7 ? `${month + 1}月` : ""}</div>`;
        if (monday.getDate() <= 7) lastMonth = month;
        for (let d = 0; d < 7; d++) {
          const day = new Date(monday); day.setDate(monday.getDate() + d);
          const key = dayKey(day), v = totals.get(key) || 0;
          if (v && day <= today) active++;
          const cls = ["cell", day.getTime() === today.getTime() ? "today" : "", day > today ? "future" : ""].join(" ");
          html += `<div class="${cls}" data-w="${w}" style="grid-column:${w + 1};grid-row:${d + 2};${fill(level(v))}" title="${key}${v ? ` · ${format(v)}` : ""}"></div>`;
        }
      }
      const label = this.attr("label", this.attr("title", ""));
      const first = !this.drawn;
      this.body.innerHTML = `<div class="head"><span class="label">${escape(label)}</span><span class="summary">最近 ${weeks} 周 · ${active} 天</span></div>
        <div class="grid">${html}</div>
        <div class="scale">少${[0, 1, 2, 3, 4].map((l) => `<div class="cell" style="${fill(l)}"></div>`).join("")}多</div>`;
      this.drawn = true;
      const grid = this.body.querySelector(".grid");
      grid.scrollLeft = grid.scrollWidth;
      if (first && !reduceMotion()) {
        const expand = preset("expand");
        grid.querySelectorAll(".cell").forEach((cell) => {
          const w = +cell.dataset.w;
          cell.animate([{ opacity: 0, transform: "scale(0.6)" }, { opacity: 1, transform: "scale(1)" }],
            { duration: expand.duration, delay: (w / weeks) * expand.visual, easing: expand.easing, fill: "backwards" });
        });
      }
    }
  }

  // MARK: <lb-records>

  class SpaceRecords extends SpaceElement {
    static get observedAttributes() { return ["source", "limit", "fields", "title", "label"]; }
    static style = `
      ul { list-style: none; margin: 0; padding: 0; }
      li, .names { display: grid; grid-template-columns: var(--cols); column-gap: 16px; padding: 8px 0; border-top: 1px solid var(--space-line); font-size: 0.96em; font-variant-numeric: tabular-nums; }
      .names { border-top: 0; padding: 0 0 6px; font-size: 0.81em; color: var(--space-muted); }
      li span, .names span { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
      li span:first-child { color: var(--space-muted); }
      li .num, .names .num { justify-self: end; text-align: right; }
      li.new { animation: arrive var(--space-slide-duration) var(--space-slide-easing) both; }
      @keyframes arrive {
        from { opacity: 0; transform: translateY(-6px); background: var(--space-accent-soft); }
        60% { opacity: 1; transform: none; background: var(--space-accent-soft); }
        to { background: transparent; }
      }
      @media (prefers-reduced-motion: reduce) { li.new { animation: none; } }
    `;
    async load() {
      const rows = await this.rows();
      const limit = Math.max(1, +this.attr("limit", 5));
      const fields = list(this.attr("fields", "")) ;
      const names = fields.length ? fields : (rows.fields || []).map((f) => f.name);
      const types = Object.fromEntries((rows.fields || []).map((f) => [f.name, f.type]));
      return { rows: rows.slice(-limit).reverse(), names, types };
    }
    draw({ rows, names, types }) {
      const header = this.header() || (this.attr("label", "") ? `<div class="title">${escape(this.attr("label", ""))}</div>` : "");
      if (!rows.length) { this.body.innerHTML = `${header}<div class="empty">还没有记录。</div>`; this.seen = new Set(); return; }
      const keys = rows.map((r) => JSON.stringify(names.map((n) => r[n])));
      const previous = this.seen;
      const cols = names.map((n) => (types[n] === "date" ? "6.5em" : types[n] === "number" ? "5em" : "minmax(4em, 1fr)")).join(" ");
      const cell = (n, v) => `<span class="${types[n] === "number" ? "num" : ""}" title="${escape(n)}">${escape(v == null ? "" : typeof v === "number" ? format(v) : v)}</span>`;
      this.body.style.setProperty("--cols", cols);
      this.body.innerHTML = `${header}<div class="names">${names.map((n) => `<span class="${types[n] === "number" ? "num" : ""}">${escape(n)}</span>`).join("")}</div>
        <ul>${rows.map((r, i) => `<li class="${previous && !previous.has(keys[i]) ? "new" : ""}">${names.map((n) => cell(n, r[n])).join("")}</li>`).join("")}</ul>`;
      this.seen = new Set(keys);
    }
  }

  // MARK: <lb-quick-add>

  class SpaceQuickAdd extends SpaceElement {
    static get observedAttributes() { return ["target", "fields", "defaults", "label", "title"]; }
    static style = `
      form { display: grid; grid-template-columns: repeat(auto-fill, minmax(118px, 1fr)); gap: 10px 12px; align-items: end; }
      label { display: flex; flex-direction: column; gap: 5px; font-size: 0.81em; color: var(--space-muted); min-width: 0; }
      .actions { grid-column: 1 / -1; display: flex; align-items: center; gap: 12px; }
      input { font: inherit; font-size: 1em; color: var(--space-text); background: var(--space-bg); border: 1px solid var(--space-line);
              border-radius: 8px; padding: 0 9px; height: 32px; line-height: 30px; outline: none; min-width: 0; width: 100%;
              transition: border-color var(--space-pop-duration) var(--space-ease), box-shadow var(--space-pop-duration) var(--space-ease); }
      input:focus { border-color: color-mix(in srgb, var(--space-accent) 60%, transparent); box-shadow: 0 0 0 3px var(--space-accent-soft); }
      input[type=number] { font-variant-numeric: tabular-nums; }
      input::-webkit-inner-spin-button, input::-webkit-outer-spin-button { -webkit-appearance: none; margin: 0; }
      input::-webkit-datetime-edit { padding: 0; }
      button { font: inherit; font-weight: 550; font-size: 0.96em; color: var(--space-bg); background: var(--space-text); border: 0; border-radius: 8px;
               padding: 7px 16px; cursor: pointer; display: inline-flex; gap: 6px; align-items: center; min-width: 84px; justify-content: center;
               transition: transform var(--space-pop-duration) var(--space-pop-easing), opacity 0.16s ease, background-color 0.25s ease; }
      button:hover { opacity: 0.9; }
      button:active { transform: scale(0.95); }
      button:disabled { opacity: 0.5; cursor: default; }
      button.done { background: var(--space-good); }
      .check { display: inline-block; width: 12px; height: 12px; }
      .check path { stroke-dasharray: 16; stroke-dashoffset: 16; animation: draw 0.34s 0.05s cubic-bezier(0.33, 1, 0.68, 1) forwards; }
      @keyframes draw { to { stroke-dashoffset: 0; } }
      .message { font-size: 0.88em; color: var(--space-bad); }
      .message:empty { display: none; }
      .shake { animation: shake 0.32s cubic-bezier(0.36, 0.07, 0.19, 0.97); }
      @keyframes shake { 20%, 60% { transform: translateX(-3px); } 40%, 80% { transform: translateX(3px); } }
      @media (prefers-reduced-motion: reduce) { .shake, .check path { animation: none; stroke-dashoffset: 0; } }
    `;
    async load() {
      const target = this.attr("target", "");
      if (!target) throw new Error("缺少 target 属性。");
      const rows = await api.query(target);
      let fields = (rows.fields || []).map((f) => ({ name: f.name, type: f.type }));
      const declared = list(this.attr("fields", ""));
      if (!fields.length) {
        if (!declared.length) throw new Error("记录表还不存在，请用 fields 属性给出新建时的表头。");
        const defaults = this.defaults();
        fields = declared.map((name) => ({
          name,
          type: /日期|date/i.test(name) ? "date" : typeof defaults[name] === "number" ? "number" : "text",
        }));
      }
      // A column with no values yet types as text; a numeric default says otherwise.
      const defaults = this.defaults();
      fields = fields.map((f) => (f.type === "text" && !rows.length && typeof defaults[f.name] === "number" ? { ...f, type: "number" } : f));
      return { fields, header: fields.map((f) => f.name), fresh: !(rows.fields || []).length };
    }
    defaults() {
      try { return JSON.parse(this.attr("defaults", "{}")) || {}; } catch (_) { return {}; }
    }
    draw(data) {
      const signature = data.fields.map((f) => f.name + ":" + f.type).join("|");
      this.data = data;
      if (signature === this.signature) return; // keep whatever the user is typing
      this.signature = signature;
      const defaults = this.defaults();
      const label = this.attr("label", "记录");
      const input = (f) => {
        const value = defaults[f.name] != null ? defaults[f.name] : f.type === "date" ? api.today() : "";
        const type = f.type === "date" ? "date" : f.type === "number" ? "number" : "text";
        return `<label class="${f.type}">${escape(f.name)}<input name="${escape(f.name)}" type="${type}" ${type === "number" ? 'step="any" inputmode="decimal"' : ""} value="${escape(value)}" data-default="${escape(value)}" data-type="${f.type}" autocomplete="off"></label>`;
      };
      this.body.innerHTML = `${this.header()}<form novalidate>${data.fields.map(input).join("")}<div class="actions"><button type="submit">${escape(label)}</button><div class="message" role="status"></div></div></form>`;
      const form = this.body.querySelector("form");
      form.addEventListener("submit", (event) => { event.preventDefault(); this.submit(form); });
    }
    async submit(form) {
      const button = form.querySelector("button"), message = form.querySelector(".message");
      const record = {};
      let problem = "";
      for (const el of form.querySelectorAll("input")) {
        const raw = el.value.trim();
        if (!raw) continue;
        if (el.dataset.type === "number") {
          const n = Number(raw);
          if (!Number.isFinite(n)) { problem = `「${el.name}」需要数字。`; break; }
          record[el.name] = n;
        } else record[el.name] = raw;
      }
      if (!problem && !Object.keys(record).length) problem = "请至少填写一项。";
      if (problem) return this.fail(form, problem);
      button.disabled = true; message.textContent = "";
      try {
        await api.append(this.attr("target", ""), record, { header: this.data.header });
        const label = this.attr("label", "记录");
        button.classList.add("done");
        button.innerHTML = `<svg class="check" viewBox="0 0 12 12" fill="none"><path d="M2.5 6.4 5 8.8 9.6 3.4" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>已记录`;
        for (const el of form.querySelectorAll("input")) if (el.dataset.type !== "date") el.value = el.dataset.default;
        const first = [...form.querySelectorAll("input")].find((el) => el.dataset.type !== "date" && !el.dataset.default);
        if (first) first.focus();
        clearTimeout(this.reset);
        this.reset = setTimeout(() => { button.classList.remove("done"); button.textContent = label; button.disabled = false; }, 1300);
      } catch (e) {
        button.disabled = false;
        this.fail(form, e && e.message ? e.message : String(e));
      }
    }
    fail(form, text) {
      form.querySelector(".message").textContent = text;
      form.classList.remove("shake"); void form.offsetWidth; form.classList.add("shake");
    }
  }

  const components = { "quick-add": SpaceQuickAdd, stat: SpaceStat, chart: SpaceChart, calendar: SpaceCalendar, records: SpaceRecords };
  for (const [name, Component] of Object.entries(components)) {
    customElements.define(`space-${name}`, Component);
    // The old names, kept for good: a class may be defined once, so each alias is a subclass.
    customElements.define(`lb-${name}`, class extends Component {});
  }
})();
