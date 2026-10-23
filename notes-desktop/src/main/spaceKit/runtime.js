// What `space` offers beyond the notes (设计地基, 2026-10-22), spliced into the interface's script (see
// spaceShim): the design tokens as resolved colours (space.theme, space.on("theme")), ECharts bundled
// with the app and themed on those tokens (space.load, space.chart), opening a note in the app
// (space.open) and a toast (space.toast). Then the motion parts that need a script: data-space-count
// and .space-spotlight. Everything follows 外观, 强调色 and 动效强度 as they change, without a reload.
// eslint-disable-next-line no-unused-vars
function spaceRuntime(call) {
  const media = (query) => (window.matchMedia ? window.matchMedia(query) : null);
  const darkQuery = media("(prefers-color-scheme: dark)");
  const reducedQuery = media("(prefers-reduced-motion: reduce)");
  const reduced = () => !!(reducedQuery && reducedQuery.matches);
  const failure = (code, message) => Object.assign(new Error(message), { code });

  // MARK: theme

  const hueNames = ["red", "orange", "yellow", "green", "teal", "blue", "indigo", "purple", "pink", "graphite"];
  let canvas = null;
  let probe = null;
  /** A CSS colour (variables, color-mix and all) as the rgba() the canvas paints, which ECharts reads. */
  const resolve = (css) => {
    if (!probe) {
      probe = document.createElement("span");
      probe.style.cssText = "position:absolute;width:0;height:0;overflow:hidden;visibility:hidden;pointer-events:none";
      canvas = document.createElement("canvas").getContext("2d", { willReadFrequently: true });
      canvas.canvas.width = canvas.canvas.height = 1;
    }
    if (!probe.isConnected) (document.body || document.documentElement).appendChild(probe);
    probe.style.color = "";
    probe.style.color = css;
    const computed = getComputedStyle(probe).color;
    canvas.clearRect(0, 0, 1, 1);
    canvas.fillStyle = "#000";
    canvas.fillStyle = computed;
    canvas.fillRect(0, 0, 1, 1);
    const [r, g, b, a] = canvas.getImageData(0, 0, 1, 1).data;
    return a === 255 ? `rgb(${r}, ${g}, ${b})` : `rgba(${r}, ${g}, ${b}, ${Math.round((a / 255) * 1000) / 1000})`;
  };
  const withAlpha = (rgb, alpha) => rgb.replace(/^rgba?\(([^,]+),([^,]+),([^,)]+).*$/, `rgba($1,$2,$3, ${alpha})`);
  const variable = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();

  let cached = null;
  const theme = () => {
    if (cached) return cached;
    const color = (name) => resolve(`var(${name})`);
    const hues = {};
    for (const name of hueNames) {
      hues[name] = { color: color(`--space-${name}`), deep: color(`--space-${name}-deep`), tint: color(`--space-${name}-tint`), glow: color(`--space-${name}-glow`) };
    }
    cached = Object.freeze({
      dark: !!(darkQuery && darkQuery.matches),
      reducedMotion: reduced(),
      amplitude: parseFloat(variable("--space-motion-amplitude")) || 1,
      accent: color("--space-accent"),
      onAccent: color("--space-on-accent"),
      text: color("--space-text"),
      muted: color("--space-muted"),
      line: color("--space-line"),
      hover: color("--space-hover"),
      card: color("--space-card"),
      background: color("--space-bg"),
      good: color("--space-good"),
      warn: color("--space-warn"),
      bad: color("--space-bad"),
      chart: [1, 2, 3, 4, 5, 6].map((n) => color(`--space-chart-${n}`)),
      hues: Object.freeze(hues),
      font: variable("--space-font"),
      headingFont: variable("--space-heading-font"),
      mono: variable("--space-mono"),
      radius: parseFloat(variable("--space-radius")) || 18,
    });
    return cached;
  };

  const themeListeners = new Set();
  const charts = new Set();
  let pending = false;
  const themeChanged = () => {
    cached = null;
    if (pending) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      const now = theme();
      for (const entry of [...charts]) entry.retheme(now);
      for (const handler of themeListeners) {
        try { handler(now); } catch (e) { setTimeout(() => { throw e; }); }
      }
    });
  };
  for (const query of [darkQuery, reducedQuery]) if (query) query.addEventListener("change", themeChanged);
  // The app rewrites this style element when 排版, 强调色 or 动效 change (the page's preload).
  const watchSettings = () => {
    const style = document.getElementById("space-settings");
    if (style) new MutationObserver(themeChanged).observe(style, { childList: true, characterData: true, subtree: true });
  };
  if (document.getElementById("space-settings")) watchSettings();
  else document.addEventListener("DOMContentLoaded", watchSettings, { once: true });

  // MARK: libraries

  const libraries = { echarts: { url: "kit/echarts.js", global: "echarts" }, react: { url: "kit/react.js", global: "SpaceReact" } };
  const loading = new Map();
  const load = (name) => {
    const library = libraries[name];
    if (!library) return Promise.reject(failure("invalid", `没有内置库“${name}”。可以用的有：${Object.keys(libraries).join("、")}。`));
    if (window[library.global]) return Promise.resolve(window[library.global]);
    if (!loading.has(name)) {
      loading.set(name, new Promise((done, fail) => {
        const script = document.createElement("script");
        script.src = new URL(library.url, location.href).href;
        script.onload = () => (window[library.global] ? done(window[library.global]) : fail(failure("failed", `内置库“${name}”加载后不可用。`)));
        script.onerror = () => { loading.delete(name); fail(failure("failed", `内置库“${name}”加载失败。`)); };
        document.head.appendChild(script);
      }));
    }
    return loading.get(name);
  };

  /** The tokens as an ECharts theme: the app's palette, type and lines, a frosted tooltip. */
  const chartTheme = (t) => {
    const axis = (split) => ({
      axisLine: { show: false, lineStyle: { color: t.line } },
      axisTick: { show: false },
      axisLabel: { color: t.muted, fontSize: 11, hideOverlap: true },
      splitLine: { show: split, lineStyle: { color: t.line } },
      nameTextStyle: { color: t.muted, fontSize: 11 },
    });
    return {
      color: t.chart,
      backgroundColor: "transparent",
      textStyle: { fontFamily: t.font, color: t.text },
      title: { textStyle: { color: t.text, fontWeight: 650, fontSize: 14 }, subtextStyle: { color: t.muted } },
      legend: { textStyle: { color: t.muted, fontSize: 11 }, icon: "circle", itemWidth: 8, itemHeight: 8, itemGap: 12, pageTextStyle: { color: t.muted } },
      tooltip: {
        backgroundColor: withAlpha(t.dark ? resolve("var(--card-bg)") : resolve("var(--card-bg)"), 0.86),
        borderWidth: 0,
        padding: [8, 12],
        textStyle: { color: resolve("var(--card-fg)"), fontSize: 12 },
        extraCssText: "border-radius:12px;backdrop-filter:blur(24px) saturate(1.8);-webkit-backdrop-filter:blur(24px) saturate(1.8);box-shadow:0 0 0 .5px rgba(127,127,127,.25),0 8px 28px rgba(0,0,0,.18);",
        axisPointer: { lineStyle: { color: t.muted, type: "dashed" }, crossStyle: { color: t.muted }, shadowStyle: { color: t.hover } },
      },
      categoryAxis: axis(false),
      valueAxis: axis(true),
      timeAxis: axis(false),
      logAxis: axis(true),
      line: { symbol: "circle", symbolSize: 6, showSymbol: false, smooth: 0.3, lineStyle: { width: 2.4 } },
      bar: { itemStyle: { borderRadius: [6, 6, 0, 0] }, barMaxWidth: 28 },
      pie: { itemStyle: { borderColor: t.card, borderWidth: 2, borderRadius: 6 } },
      scatter: { symbolSize: 8 },
      gauge: { axisLine: { lineStyle: { color: [[1, t.hover]] } } },
      markLine: { lineStyle: { color: t.muted }, label: { color: t.muted } },
      dataZoom: { textStyle: { color: t.muted }, borderColor: t.line },
    };
  };

  const chart = async (target, option) => {
    const element = typeof target === "string" ? document.querySelector(target) : target;
    if (!element || element.nodeType !== 1) throw failure("invalid", "space.chart 需要一个元素或能找到元素的选择器。");
    const echarts = await load("echarts");
    if (element.clientHeight === 0 && !element.style.height) element.style.height = "220px";
    const existing = echarts.getInstanceByDom(element);
    if (existing) existing.dispose();
    let current = theme();
    const instance = echarts.init(element, chartTheme(current), { renderer: "canvas" });
    const build = typeof option === "function" ? option : null;
    const motion = (t) => (t.reducedMotion ? { animation: false } : {});
    instance.setOption({ ...motion(current), ...(build ? build(current) : option || {}) });
    const watch = typeof ResizeObserver === "function" ? new ResizeObserver(() => !instance.isDisposed() && instance.resize()) : null;
    if (watch) watch.observe(element);
    const entry = {
      retheme(t) {
        if (instance.isDisposed() || !element.isConnected) {
          if (watch) watch.disconnect();
          if (!instance.isDisposed()) instance.dispose();
          charts.delete(entry);
          return;
        }
        current = t;
        instance.setTheme(chartTheme(t));
        instance.setOption({ animation: !t.reducedMotion, ...(build ? build(t) : {}) });
      },
    };
    charts.add(entry);
    return instance;
  };

  // MARK: toast

  let shelf = null;
  const toast = (message, options = {}) => {
    if (!shelf || !shelf.isConnected) {
      shelf = document.createElement("div");
      shelf.className = "space-toasts";
      shelf.setAttribute("role", "status");
      document.body.appendChild(shelf);
    }
    const item = document.createElement("div");
    item.className = "space-toast";
    const text = document.createElement("span");
    text.textContent = String(message == null ? "" : message);
    item.appendChild(text);
    let timer = 0;
    const close = () => {
      clearTimeout(timer);
      if (!item.isConnected || item.classList.contains("space-leaving")) return;
      item.classList.add("space-leaving");
      setTimeout(() => item.remove(), reduced() ? 0 : 220);
    };
    if (options.action) {
      const button = document.createElement("button");
      button.type = "button";
      button.textContent = String(options.action);
      button.addEventListener("click", () => {
        close();
        if (typeof options.onAction === "function") options.onAction();
      });
      item.appendChild(button);
    }
    shelf.appendChild(item);
    const duration = typeof options.duration === "number" ? options.duration : options.action ? 6000 : 3000;
    if (duration > 0) timer = setTimeout(close, duration);
    return { close };
  };

  // MARK: motion parts

  const easeOut = (t) => 1 - Math.pow(1 - t, 3);
  const numberIn = /-?\d[\d,]*(?:\.\d+)?/;
  const shown = new WeakMap();
  /** data-space-count: the number (the attribute's, or the element's text) counts up to itself. */
  const count = (element) => {
    const source = element.getAttribute("data-space-count") || element.textContent || "";
    const match = numberIn.exec(source);
    if (!match) return;
    const target = parseFloat(match[0].replace(/,/g, ""));
    const decimals = (match[0].split(".")[1] || "").length;
    const grouped = match[0].includes(",");
    const before = source.slice(0, match.index);
    const after = source.slice(match.index + match[0].length);
    const from = shown.has(element) ? shown.get(element) : 0;
    shown.set(element, target);
    const text = (n) => before + n.toLocaleString("en-US", { minimumFractionDigits: decimals, maximumFractionDigits: decimals, useGrouping: grouped }) + after;
    if (reduced() || from === target) { element.textContent = text(target); return; }
    const duration = (parseFloat(element.getAttribute("data-space-duration")) || 1200) * Math.min(1.4, Math.max(0.6, theme().amplitude));
    const start = performance.now();
    const step = (now) => {
      if (shown.get(element) !== target) return;
      const k = Math.min(1, (now - start) / duration);
      element.textContent = text(from + (target - from) * easeOut(k));
      if (k < 1) requestAnimationFrame(step);
    };
    element.textContent = text(from);
    requestAnimationFrame(step);
  };
  const seen = typeof IntersectionObserver === "function"
    ? new IntersectionObserver((entries) => {
        for (const entry of entries) if (entry.isIntersecting) { seen.unobserve(entry.target); count(entry.target); }
      })
    : null;
  const watchCount = (element) => (seen ? seen.observe(element) : count(element));
  const scan = (root) => {
    if (root.nodeType !== 1) return;
    if (root.hasAttribute("data-space-count")) watchCount(root);
    for (const element of root.querySelectorAll("[data-space-count]")) watchCount(element);
  };
  const startParts = () => {
    scan(document.body);
    new MutationObserver((records) => {
      for (const record of records) {
        if (record.type === "attributes") { if (shown.has(record.target)) count(record.target); else watchCount(record.target); }
        else for (const node of record.addedNodes) scan(node);
      }
    }).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["data-space-count"] });
    // .space-spotlight: the light follows the pointer.
    document.addEventListener("pointermove", (event) => {
      const card = event.target && event.target.closest ? event.target.closest(".space-spotlight") : null;
      if (!card) return;
      const box = card.getBoundingClientRect();
      card.style.setProperty("--space-mx", `${event.clientX - box.left}px`);
      card.style.setProperty("--space-my", `${event.clientY - box.top}px`);
    }, { passive: true });
    document.addEventListener("pointerout", (event) => {
      const card = event.target && event.target.closest ? event.target.closest(".space-spotlight") : null;
      if (card && !card.contains(event.relatedTarget)) { card.style.removeProperty("--space-mx"); card.style.removeProperty("--space-my"); }
    });
  };
  if (document.body) startParts();
  else document.addEventListener("DOMContentLoaded", startParts, { once: true });

  return {
    methods: {
      theme,
      load,
      chart,
      toast,
      open: (path) => call("open", path),
    },
    onTheme(handler) {
      themeListeners.add(handler);
      return () => themeListeners.delete(handler);
    },
  };
}
