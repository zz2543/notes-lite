// 新建示例空间 (ticket 31): the notes and homepage of 组件示例, which the app writes itself. Four sample
// notes hold record tables running up to the day it is made; the homepage puts every component to
// work on them, and under each card shows the markup that draws it, for copying into a page of one's own.
// Above them, 自定义写法 (设计地基): a section drawn without components, from the style foundation, the
// built-in charts and space.open, as an agent's own page would be; then React 写法, the same notes drawn
// with React and Recharts (space.load("react")).

/** The sample space's name; a second one is “组件示例 2”, and so on. */
export const exampleSpaceName = "组件示例";
export const exampleSpaceIcon = "🧩";

const pad = (n: number) => String(n).padStart(2, "0");
/** `days` before `now`, as YYYY-MM-DD in local time. */
const daysBefore = (now: Date, days: number) => {
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - days);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
};
const table = (header: string[], rows: (string | number)[][]) =>
  [`| ${header.join(" | ")} |`, `|${header.map(() => "---").join("|")}|`, ...rows.map((row) => `| ${row.join(" | ")} |`)].join("\n");

/** The four sample notes, by file name, with records up to `now`; oldest first, as a table grows. */
export function exampleNotes(now: Date): Record<string, string> {
  // A workout every two or three days for four months, the weights slowly going up.
  const workouts: (string | number)[][] = [];
  for (let day = 120, i = 0; day >= 0; day -= i % 3 === 2 ? 3 : 2, i++) {
    const squat = i % 2 === 1;
    const weight = (squat ? 70 : 50) + Math.floor(i / 4) * 2.5;
    workouts.push([daysBefore(now, day), squat ? "深蹲" : "卧推", weight, 5 - (i % 3 === 0 ? 1 : 0)]);
  }
  const weights: (string | number)[][] = [];
  for (let week = 17; week >= 0; week--) weights.push([daysBefore(now, week * 7), (70.1 + week * 0.13 + (week % 3) * 0.07).toFixed(2)]);

  const todos = [
    ["买蛋白粉", "[x]", daysBefore(now, 6)],
    ["预约体检", "[x]", daysBefore(now, 3)],
    ["整理书单", "[ ]", daysBefore(now, -2)],
    ["换跑鞋", "[ ]", daysBefore(now, -5)],
    ["写周报", "[x]", daysBefore(now, 0)],
  ];

  const books = ["置身事内", "悉达多", "三体"];
  const reading: (string | number)[][] = [];
  for (let day = 60, i = 0; day >= 0; day--, i++) {
    if (i % 4 === 3) continue;
    reading.push([daysBefore(now, day), books[Math.min(books.length - 1, Math.floor(i / 22))]!, 12 + ((i * 7) % 26)]);
  }

  const starts = ["08:30", "14:00", "20:15"];
  const focus: (string | number)[][] = [];
  for (let day = 45, i = 0; day >= 0; day--, i++) {
    if (i % 5 === 4) continue;
    focus.push([daysBefore(now, day), starts[i % starts.length]!, 25 + ((i * 11) % 50)]);
  }

  return {
    "健身记录.md": `# 健身记录\n\n## 训练\n\n${table(["日期", "动作", "重量", "组数"], workouts)}\n\n## 体重\n\n${table(["日期", "体重"], weights)}\n`,
    "待办清单.md": `# 待办清单\n\n${table(["事项", "完成", "截止"], todos)}\n`,
    "读书进度.md": `# 读书进度\n\n${table(["日期", "书名", "页数"], reading)}\n`,
    "专注时长.md": `# 专注时长\n\n${table(["日期", "开始时间", "时长（分钟）"], focus)}\n`,
  };
}

const escapeHtml = (s: string) => s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");

/** A card of the sample homepage: what the component is, the component, and its markup to copy. */
const card = (name: string, about: string, markup: string) => `<section class="space-card">
  <h3>${name}</h3>
  <p class="space-muted">${about}</p>
  ${markup}
  <div class="space-snippet">
    <pre><code>${escapeHtml(markup)}</code></pre>
    <button type="button" class="space-button space-secondary">复制写法</button>
  </div>
</section>`;

/**
 * The sample homepage, after its meta, for the space whose folder is `folder`. Its own script only copies
 * a card's markup; everything else is the components.
 */
export function examplePage(folder: string): string {
  const at = (note: string) => `${folder}/${note}`;
  const stats = [
    card("大数字 · 计数", "本周训练了几次。", `<space-stat source="${at("健身记录.md#训练")}" op="count" period="week" label="本周训练" unit="次"></space-stat>`),
    card("大数字 · 最大值", "卧推和深蹲里最重的一组。", `<space-stat source="${at("健身记录.md#训练")}" op="max" field="重量" label="最大重量" unit="kg"></space-stat>`),
    card("大数字 · 求和", "这个月专注了多少分钟。", `<space-stat source="${at("专注时长.md")}" op="sum" field="时长（分钟）" period="month" label="本月专注" unit="分钟"></space-stat>`),
  ];
  const cards = [
    card("图表 · 折线", "体重的变化。", `<space-chart source="${at("健身记录.md#体重")}" x="日期" y="体重" type="line" unit="kg" title="体重"></space-chart>`),
    card("图表 · 柱状", "每天读了多少页。", `<space-chart source="${at("读书进度.md")}" x="日期" y="页数" type="bar" limit="21" title="每日页数"></space-chart>`),
    card("打卡日历", "哪些天练过。", `<space-calendar source="${at("健身记录.md#训练")}" title="训练日历"></space-calendar>`),
    card("最近记录", "最近几次训练。", `<space-records source="${at("健身记录.md#训练")}" limit="5" title="最近训练"></space-records>`),
    card("最近记录 · 待办", "清单里的事项。", `<space-records source="${at("待办清单.md")}" limit="5" title="待办"></space-records>`),
    card("快捷录入", "记一次专注，写进「专注时长」。", `<space-quick-add target="${at("专注时长.md")}" label="记一次专注" title="专注"></space-quick-add>`),
  ];
  return `<p class="space-muted">这是应用写好的示例主页：每张卡片用一个组件读取「${escapeHtml(folder)}」里的示例笔记，下方是画出它的写法，可以复制到自己的主页里。示例空间和其他空间一样，可以修改，也可以删除。</p>

<style>
  /* 复制写法: the markup under a card, small and quiet, from the style kit's own values. */
  .space-snippet { display: flex; flex-direction: column; align-items: flex-end; gap: var(--gap-2); margin-top: var(--gap-3); }
  .space-snippet pre { align-self: stretch; margin: 0; padding: var(--gap-2) var(--gap-3);
    border-radius: var(--space-control-radius); background: var(--space-bg); color: var(--space-muted); font-size: var(--code-size); }
  .space-snippet code { white-space: pre-wrap; overflow-wrap: anywhere; }
</style>

<section class="space-section">
  <h2 class="space-section-title">自定义写法 <span class="space-section-hint">不用组件，用设计地基自己写：光晕卡片、滚动数字、进度条、内置图表、点开笔记</span></h2>
  <div class="space-bento">
    <div class="space-glow space-m space-spotlight" data-hue="red">
      <div class="space-title">本月训练</div>
      <div class="space-subtitle" id="example-month-note">　</div>
      <div style="display: flex; gap: var(--gap-8); margin-top: var(--gap-8)">
        <div><div class="space-label">次数</div><div class="space-big"><span id="example-month-count" data-space-count>0</span><small>次</small></div></div>
        <div><div class="space-label">最大重量</div><div class="space-big"><span id="example-month-max" data-space-count>0</span><small>kg</small></div></div>
      </div>
    </div>
    <div class="space-glow space-m" data-hue="green">
      <div class="space-title">本月专注</div>
      <div class="space-subtitle"><span class="space-live" id="example-focus-note">　</span></div>
      <div class="space-progress space-shimmer" id="example-focus" style="--space-value: 0; height: 14px; margin-top: var(--gap-8)"></div>
    </div>
    <div class="space-card space-m">
      <div class="space-label">体重 · space.chart</div>
      <div id="example-weight" style="height: 200px"></div>
    </div>
    <div class="space-glow space-m" data-hue="indigo">
      <div class="space-title">每日页数</div>
      <div class="space-subtitle">最近 14 天</div>
      <div id="example-pages" style="height: 170px"></div>
    </div>
    <div class="space-tint space-full" data-hue="teal">
      <div class="space-label">示例笔记 · 点一下用 space.open 打开</div>
      <div id="example-notes" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(160px, 1fr)); gap: var(--gap-2); margin-top: var(--gap-2)"></div>
    </div>
  </div>
</section>

<script>
  // 自定义写法: everything in the section above, drawn from the notes through space.
  (() => {
    const folder = ${JSON.stringify(folder)};
    const month = space.today().slice(0, 7);
    const day = (date) => Number(date.slice(5, 7)) + "月" + Number(date.slice(8, 10)) + "日";
    async function draw() {
      const workouts = await space.query(folder + "/健身记录.md#训练", { filter: (r) => String(r.日期).startsWith(month) });
      document.getElementById("example-month-count").setAttribute("data-space-count", workouts.length);
      document.getElementById("example-month-max").setAttribute("data-space-count", Math.max(0, ...workouts.map((r) => r.重量 || 0)));
      document.getElementById("example-month-note").textContent = workouts.length ? "最近一次 " + day(workouts[workouts.length - 1].日期) : "这个月还没有训练";

      const focus = await space.query(folder + "/专注时长.md", { filter: (r) => String(r.日期).startsWith(month) });
      const minutes = focus.reduce((sum, r) => sum + (r["时长（分钟）"] || 0), 0);
      document.getElementById("example-focus").style.setProperty("--space-value", Math.min(100, (minutes / 1200) * 100));
      document.getElementById("example-focus-note").textContent = minutes + " / 1200 分钟";

      const weights = await space.query(folder + "/健身记录.md#体重", { sort: "日期" });
      await space.chart("#example-weight", {
        tooltip: { trigger: "axis" },
        grid: { left: 40, right: 12, top: 16, bottom: 24 },
        xAxis: { type: "time" },
        yAxis: { type: "value", scale: true },
        series: [{ name: "体重 kg", type: "line", data: weights.map((r) => [r.日期, r.体重]), areaStyle: { opacity: 0.12 } }],
      });

      const pages = (await space.query(folder + "/读书进度.md", { sort: "日期" })).slice(-14);
      await space.chart("#example-pages", (theme) => ({
        grid: { left: 4, right: 4, top: 20, bottom: 20 },
        xAxis: { type: "category", data: pages.map((r) => r.日期.slice(5).replace("-", "/")), axisLabel: { color: "rgba(255,255,255,.65)" } },
        yAxis: { show: false },
        series: [{ type: "bar", data: pages.map((r) => r.页数), barWidth: "56%",
          itemStyle: { color: "rgba(255,255,255,.32)", borderRadius: [8, 8, 3, 3] },
          emphasis: { itemStyle: { color: "#fff", shadowBlur: 16, shadowColor: theme.hues.indigo.glow } },
          label: { show: true, position: "top", color: "rgba(255,255,255,.8)", fontSize: 10 } }],
      }));

      const notes = (await space.notes(folder)).sort((a, b) => b.modified.localeCompare(a.modified));
      document.getElementById("example-notes").replaceChildren(...notes.map((note) => {
        const item = document.createElement("button");
        item.type = "button";
        item.className = "space-card space-lift";
        item.style.cssText = "margin:0;text-align:left;font:inherit;color:inherit;cursor:pointer;padding:var(--gap-3) var(--gap-4)";
        const title = document.createElement("b");
        title.textContent = note.title;
        const when = document.createElement("div");
        when.className = "space-label";
        when.textContent = "修改于 " + day(note.modified.slice(0, 10));
        item.append(title, when);
        item.addEventListener("click", () => space.open(note.path));
        return item;
      }));
    }
    draw();
    space.on("change", draw);
  })();
</script>

<section class="space-section">
  <h2 class="space-section-title">React 写法 <span class="space-section-hint">space.load("react")：React、htm 和 Recharts，配色跟随应用，笔记一改就重画</span></h2>
  <div class="space-bento" id="example-react"></div>
</section>

<script>
  // React 写法: two cards drawn with Recharts from the notes, through space.load("react").
  (async () => {
    const folder = ${JSON.stringify(folder)};
    const { html, mount, useTheme, useQuery, chartProps, Recharts } = await space.load("react");
    const { ResponsiveContainer, AreaChart, Area, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ReferenceLine, Legend } = Recharts;
    const day = (date) => Number(String(date).slice(5, 7)) + "/" + Number(String(date).slice(8, 10));
    const monday = (date) => {
      const d = new Date(date + "T00:00:00");
      d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
      return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    };

    function Weight() {
      const t = useTheme(), p = chartProps(t);
      const rows = useQuery(folder + "/健身记录.md#体重", { sort: "日期" });
      if (!rows || !rows.length) return null;
      const last = rows[rows.length - 1], before = rows[Math.max(0, rows.length - 5)];
      const change = last.体重 - before.体重;
      return html\`<div class="space-card space-m">
        <div class="space-label">体重 · Recharts</div>
        <div style="display: flex; align-items: baseline; gap: var(--gap-3)">
          <div class="space-big">\${last.体重.toFixed(1)}<small>kg</small></div>
          <span class="space-label" style=\${{ color: change <= 0 ? t.good : t.bad }}>\${change <= 0 ? "↓" : "↑"} \${Math.abs(change).toFixed(1)} 比 4 周前</span>
        </div>
        <div style="height: 170px">
          <\${ResponsiveContainer}>
            <\${AreaChart} data=\${rows} margin=\${{ top: 8, right: 8, left: 0, bottom: 0 }}>
              <defs>
                <linearGradient id="example-weight-fill" x1="0" x2="0" y1="0" y2="1">
                  <stop offset="0" stopColor=\${t.accent} stopOpacity="0.28" />
                  <stop offset="1" stopColor=\${t.accent} stopOpacity="0" />
                </linearGradient>
              </defs>
              <\${CartesianGrid} ...\${p.grid} />
              <\${XAxis} dataKey="日期" tickFormatter=\${day} ...\${p.xAxis} />
              <\${YAxis} domain=\${[(min) => Math.floor(min) - 0.5, (max) => Math.ceil(max)]} tickCount=\${5} tickFormatter=\${(v) => v.toFixed(1)} ...\${p.yAxis} />
              <\${Tooltip} ...\${p.tooltip} separator="  " labelFormatter=\${day} formatter=\${(v) => [v.toFixed(1) + " kg", "体重"]} />
              <\${ReferenceLine} y=\${70} stroke=\${t.good} strokeDasharray="4 4" label=\${{ value: "目标 70", position: "insideTopRight", fill: t.good, fontSize: 11 }} />
              <\${Area} type="monotone" dataKey="体重" stroke=\${t.accent} strokeWidth=\${2.4} fill="url(#example-weight-fill)" dot=\${false}
                activeDot=\${{ r: 4.5, strokeWidth: 2, stroke: t.card }} isAnimationActive=\${p.animate} />
            </\${AreaChart}>
          </\${ResponsiveContainer}>
        </div>
      </div>\`;
    }

    function Weekly() {
      const t = useTheme(), p = chartProps(t);
      const rows = useQuery(folder + "/健身记录.md#训练", { sort: "日期" });
      if (!rows) return null;
      const weeks = new Map();
      for (const r of rows) {
        const week = monday(r.日期);
        const entry = weeks.get(week) || { 周: week, 卧推: 0, 深蹲: 0 };
        entry[r.动作] = (entry[r.动作] || 0) + 1;
        weeks.set(week, entry);
      }
      const data = [...weeks.values()].slice(-8);
      const total = data.reduce((sum, w) => sum + w.卧推 + w.深蹲, 0);
      return html\`<div class="space-card space-m">
        <div class="space-label">每周训练 · Recharts</div>
        <div style="display: flex; align-items: baseline; gap: var(--gap-3)">
          <div class="space-big">\${(total / Math.max(1, data.length)).toFixed(1)}<small>次 / 周</small></div>
          <span class="space-label">最近 \${data.length} 周共 \${total} 次</span>
        </div>
        <div style="height: 170px">
          <\${ResponsiveContainer}>
            <\${BarChart} data=\${data} margin=\${{ top: 8, right: 8, left: 0, bottom: 0 }} barCategoryGap="30%">
              <\${CartesianGrid} ...\${p.grid} />
              <\${XAxis} dataKey="周" tickFormatter=\${day} ...\${p.xAxis} />
              <\${YAxis} allowDecimals=\${false} ...\${p.yAxis} />
              <\${Tooltip} ...\${p.tooltip} separator="  " cursor=\${{ fill: t.hover }} labelFormatter=\${(week) => day(week) + " 这周"} />
              <\${Legend} ...\${p.legend} />
              <\${Bar} dataKey="卧推" stackId="动作" fill=\${p.colors[0]} isAnimationActive=\${p.animate} />
              <\${Bar} dataKey="深蹲" stackId="动作" fill=\${p.colors[1]} radius=\${[6, 6, 0, 0]} isAnimationActive=\${p.animate} />
            </\${BarChart}>
          </\${ResponsiveContainer}>
        </div>
      </div>\`;
    }

    mount("#example-react", () => html\`<\${Weight} /><\${Weekly} />\`);
  })();
</script>

<h2 class="space-section-title">内置组件</h2>

<div class="space-grid">
${stats.join("\n")}
</div>

${cards.join("\n\n")}

<script>
  // 复制写法: the markup above the button, to the clipboard.
  document.addEventListener("click", (event) => {
    const button = event.target.closest(".space-snippet button");
    if (!button) return;
    const code = button.parentElement.querySelector("code");
    const range = document.createRange();
    range.selectNodeContents(code);
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    document.execCommand("copy");
    selection.removeAllRanges();
    button.textContent = "已复制";
    setTimeout(() => (button.textContent = "复制写法"), 1600);
  });
</script>
`;
}
