// 新建示例空间 (ticket 31): the notes and homepage of 组件示例, which the app writes itself. Four sample
// notes hold record tables running up to the day it is made; the homepage puts every component to
// work on them, and under each card shows the markup that draws it, for copying into a page of one's own.

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
