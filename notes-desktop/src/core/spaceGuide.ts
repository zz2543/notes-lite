// The authoring guide installed at `.notes/空间/编写说明.md`, overwritten whenever it differs from
// this version's. Ported from the old app's SpaceGuide with the new folder and, since ticket 20, the
// brand-neutral names (`space`, `space-*`, `--space-*`), the old `lb` names as aliases, and the
// interface's TypeScript declarations.

/** Bumped whenever the text changes. */
export const spaceGuideVersion = 7;

/** The page interface and components as TypeScript declarations, as the guide carries them. */
export const spaceTypes = `/** 字段类型：整列都是数字为 number，整列都是 YYYY-MM-DD 为 date，其余为 text。 */
type SpaceFieldType = "number" | "date" | "text";
interface SpaceField { name: string; type: SpaceFieldType }
/** 单元格的值：数字字段是 number，日期和文字是字符串，空单元格是 null。 */
type SpaceValue = number | string | null;
/** 一条记录：{ 字段: 值 }，以及它在表中的行号 _row（从 0 开始，不可枚举）。 */
type SpaceRecord = { readonly _row: number } & { [field: string]: SpaceValue };
/** query 的结果：记录数组，fields 是表头与字段类型。 */
type SpaceRecords = SpaceRecord[] & { readonly fields: SpaceField[] };
/** 新写入的记录：值可以是数字或字符串（字符串里的占位符会被展开）。 */
type SpaceDraft = { [field: string]: number | string | null };
/** 定位记录：字段等于该值的记录，或 { _row: 行号 }。 */
type SpaceMatch = { [field: string]: number | string | null };
type SpaceScope = { library: true } | { library: false; folders: string[] };
/** modified：最后修改时间，ISO 8601 字符串。 */
interface SpaceNote { path: string; title: string; modified: string }
interface SpaceTable { source: string; header: string[] }
interface SpaceQueryOptions {
  filter?: SpaceMatch | ((record: SpaceRecord) => boolean);
  /** 字段名；前面加 - 表示倒序，例如 "-日期"。 */
  sort?: string;
  limit?: number;
}
type SpaceErrorCode = "outside-scope" | "not-found" | "exists" | "unknown-field" | "scope-change" | "invalid" | "conflict" | "failed";
/** 失败的调用拒绝 Promise，错误对象带 code。 */
interface SpaceError extends Error { code: SpaceErrorCode }

/** 解析好的颜色都是 rgb()/rgba() 字符串，可以直接交给画布、SVG 或 ECharts。 */
interface SpaceHue { color: string; deep: string; tint: string; glow: string }
type SpaceHueName = "red" | "orange" | "yellow" | "green" | "teal" | "blue" | "indigo" | "purple" | "pink" | "graphite";
interface SpaceTheme {
  dark: boolean;
  /** 用户开启了「减弱动态效果」。 */
  reducedMotion: boolean;
  /** 动效幅度：轻 0.6、标准 1、强 2。 */
  amplitude: number;
  accent: string; onAccent: string; text: string; muted: string; line: string; hover: string;
  card: string; background: string; good: string; warn: string; bad: string;
  chart: string[];
  hues: Record<SpaceHueName, SpaceHue>;
  font: string; headingFont: string; mono: string;
  radius: number;
}
interface SpaceToastOptions {
  /** 按钮文字，例如 "撤销"。 */
  action?: string;
  onAction?: () => void;
  /** 显示多久（毫秒）；0 表示一直显示。默认有按钮 6000，没有 3000。 */
  duration?: number;
}
/** ECharts 实例（见 https://echarts.apache.org）。 */
type SpaceEChartsInstance = any;

interface SpaceApi {
  scope(): Promise<SpaceScope>;
  notes(folder?: string): Promise<SpaceNote[]>;
  read(path: string): Promise<string>;
  tables(path?: string): Promise<SpaceTable[]>;
  query(source: string, options?: SpaceQueryOptions): Promise<SpaceRecords>;
  append(target: string, records: SpaceDraft | SpaceDraft[], options?: { header?: string[] }): Promise<{ count: number }>;
  update(target: string, match: SpaceMatch, changes: SpaceDraft): Promise<{ count: number }>;
  remove(target: string, match: SpaceMatch): Promise<{ count: number }>;
  create(path: string, content: string): Promise<{ path: string }>;
  write(path: string, content: string): Promise<{ path: string }>;
  rename(path: string, title: string): Promise<{ path: string }>;
  move(path: string, folder: string): Promise<{ path: string }>;
  trash(path: string): Promise<{ path: string }>;
  page(): Promise<string>;
  writePage(html: string): Promise<{ path: string }>;
  /** 在笔记应用里打开范围内的一篇笔记。 */
  open(path: string): Promise<{ path: string }>;
  /** 当前外观下解析好的设计变量（同步）。 */
  theme(): SpaceTheme;
  /** 加载笔记应用内置的库（离线可用）；目前有 "echarts"。 */
  load(name: "echarts"): Promise<any>;
  /** 在元素里画一张 ECharts 图表，配色字体跟随笔记应用；option 可以是函数，外观变化时用新的 theme 重新调用。 */
  chart(target: Element | string, option: object | ((theme: SpaceTheme) => object)): Promise<SpaceEChartsInstance>;
  /** 页面底部的提示，可以带一个按钮。 */
  toast(message: string, options?: SpaceToastOptions): { close(): void };
  /** 范围内的文件变化时调用 handler；返回取消订阅的函数。 */
  on(event: "change", handler: (paths: string[]) => void): () => void;
  /** 外观、强调色、排版或动效强度变化时调用 handler。 */
  on(event: "theme", handler: (theme: SpaceTheme) => void): () => void;
  /** 今天的日期 YYYY-MM-DD（本地时间）。 */
  today(): string;
}

/** 笔记应用注入的接口。 */
declare const space: SpaceApi;
/** 旧名称，与 space 是同一个对象。 */
declare const lb: SpaceApi;

interface HTMLElementTagNameMap {
  "space-stat": HTMLElement;
  "space-chart": HTMLElement;
  "space-calendar": HTMLElement;
  "space-quick-add": HTMLElement;
  "space-records": HTMLElement;
}
`;

export const spaceGuide = `<!-- 空间主页编写说明 · 版本 ${spaceGuideVersion} · 由笔记应用自动生成，升级时会被覆盖，请不要手动修改 -->
# 空间主页编写说明

你要编写的是笔记应用里某个**空间**的**空间主页**：一个 HTML 页面，围绕一个主题（例如健身、雅思）展示每天的进展，并提供快捷录入。用户把新建空间时复制的提示词交给你，提示词里有空间文件路径、范围和现有记录表。

## 必须遵守的规则

1. **数据只存记录表。** 空间主页自身不保存任何记录。所有数据都写进范围内笔记里的 Markdown 表格（记录表）。
2. **联网拿到的数据必须写入记录表**（用 \`space.append\` 等），不能只显示在页面上或缓存在页面里。
3. **localStorage 只存界面偏好**（例如上次选的标签、图表按周还是按月），不能存记录。
4. **只能访问范围内的路径。** 范围外的笔记、\`..\`、隐藏目录和 \`.notes/\` 一律被拒绝。页面不能运行命令，也不能访问笔记库外的文件。
5. **不要修改空间文件开头的 \`space-scope\`。** 范围由用户在笔记应用里设置；页面试图改变范围的写入会被拒绝。
6. 所有写入都会进入用户可以逐条撤销的操作记录，删除的笔记会进废纸篓。写入要克制：只写用户需要的数据。

## 工作方式

- **只读需要的东西：** 这份说明、空间文件、提示词里列出的进展记录表。想了解主题，最多浏览几篇笔记；不要逐篇读完范围内的笔记。范围内的对比表、速查表等内容表格不是进展记录，不要做成主页内容。
- **这份说明就是全部接口文档。** 不要打开或解包笔记应用的程序文件去找组件的行为。常被问到的：记录表还不存在时，组件显示空状态，\`space.query\` 返回空数组，第一次写入时自动新建；\`data-space-count\` 在元素出现或属性变化时滚动到新值；\`space.chart\` 跟随主题和窗口大小自动更新。
- **不要自建测试页面，也不要用浏览器检查。** 写好空间文件后笔记应用会立即显示主页，出错会显示在主页顶部的提示条里，用户会告诉你。
- **新建主页先给方案。** 第一次回复不写文件：说说你对这个空间的理解，列出打算放的卡片、图表、快捷录入和要用的记录表，问用户两三个偏好问题，等用户确认后再写。用户说“直接做”或要求已经很明确时可以跳过。修改已有主页时按用户说的改，不必先给方案。
- **写好空间文件就结束**，简短说明主页包含什么。

## 空间文件

每个空间是笔记库里的 \`.notes/空间/<名称>.html\`。开头是笔记应用写的 meta，之后是空间主页正文：

\`\`\`html
<meta name="space-scope" content="健身, 日记">   <!-- 范围：逗号分隔的文件夹；整个笔记库写 * -->
<meta name="space-icon" content="🏋️">           <!-- 图标 -->

<div class="space-card">
  <h2>本周训练</h2>
  <space-stat source="健身/训练记录.md" op="count" period="week" label="本周训练" unit="次"></space-stat>
</div>
\`\`\`

- 只写 \`<body>\` 里的内容即可（可以包含 \`<style>\`、\`<script>\`），笔记应用会注入样式包、组件和 \`space\` 接口。
- meta 之后为空表示「还没有主页」。保存文件后，笔记应用会自动刷新显示。
- **页面默认不能联网。** 图表用内置的 ECharts（\`space.chart\`），字体用系统字体，不要从 CDN 加载脚本、样式、字体或图片。
- **确实需要联网时**（例如获取天气、汇率）：先在对话里告诉用户要访问哪些网站、做什么用，问他是否同意；不同意就换成不联网的做法。同意后在空间文件开头写明网站和用途：\`<meta name="space-network" content="api.open-meteo.com">\`、\`<meta name="space-network-reason" content="获取每天的天气">\`（多个网站用逗号分隔，\`*.example.com\` 表示它的所有子域名）。主页显示时，笔记应用会在顶部请用户允许；允许前和不允许时，到这些网站的请求都会失败，页面要照常显示笔记里的数据，并说明「未允许联网」。没有写明的网站始终不能访问。
- 页面里的 JS 报错会显示在页面顶部的错误条上，用户可以把错误复制给你修复。错误里的行号就是空间文件里的行号。
- 页面不能跳转到别的网址（点击链接会在用户的浏览器里打开）。嵌入的 \`<iframe>\` 里没有 \`space\`。
- 页面里的顶层卡片（\`<body>\` 的直接子元素和 \`.space-grid\` 里的卡片）打开时会依次浮现，动效强度跟随用户的设置；不需要自己写入场动画。

## 记录表

记录表是笔记里的 Markdown 表格：表头就是字段，一行就是一条记录。

\`\`\`markdown
## 卧推
| 日期 | 动作 | 重量 | 组数 |
|---|---|---|---|
| 2026-10-18 | 卧推 | 60 | 5 |
\`\`\`

- **定位**：\`笔记路径#标题\`，例如 \`健身/训练记录.md#卧推\` 指 \`## 卧推\` 下面的第一张表。不写 \`#标题\` 时用该笔记里的第一张表。路径相对于笔记库根目录。
- **占位符**（按当天日期展开，可用于路径和写入的值）：
  - \`{今天}\` → \`2026-10-18\`
  - \`{年}\` → \`2026\`
  - \`{月}\` → \`2026-10\`
  - \`{周}\` → \`2026-W42\`（ISO 周）
  例如 \`健身/{月}.md\` 会按月自动分篇。
- **自动新建**：写入时目标笔记或表不存在，笔记应用按表头自动新建（笔记不存在就新建笔记；有 \`#标题\` 时同时新建该标题）。
- **字段类型**自动推断：整列都是数字的是数字（\`number\`），整列都是 \`YYYY-MM-DD\` 的是日期（\`date\`），其余是文字（\`text\`）。空单元格不参与推断。
- 单元格里的 \`|\` 会被转义，换行会被替换成空格。

## 样式包

笔记应用注入的 CSS 变量和 class，取值就是笔记应用自己的设计规范：跟随用户选的外观（浅色、深色）、强调色和排版（正文字体、字号、行距）。用它们，页面就会和笔记应用原生界面一致，用户改设置时页面立即跟着变。页面自己的 CSS 变量请用自己的前缀，不要和下面的名字重复。

| 变量 | 含义 |
|---|---|
| \`--space-bg\` | 页面背景 |
| \`--space-card\` | 卡片背景 |
| \`--space-text\` | 正文颜色 |
| \`--space-muted\` | 次要文字颜色 |
| \`--space-line\` | 分隔线、边框 |
| \`--space-hover\` | 悬停底色 |
| \`--space-accent\` | 强调色（用户在设置里选的） |
| \`--space-on-accent\` | 强调色上的文字 |
| \`--space-accent-soft\` | 浅强调色（填充） |
| \`--space-good\` / \`--space-warn\` / \`--space-bad\` | 状态色 |
| \`--space-radius\` | 卡片圆角 |
| \`--space-shadow\` | 卡片阴影 |
| \`--space-font\` / \`--space-heading-font\` / \`--space-mono\` | 正文字体 / 标题字体 / 等宽字体（跟随排版设置） |
| \`--space-ui-font\` | 界面字体（无衬线，和笔记应用的界面一致） |
| \`--space-font-size\` / \`--space-leading\` | 正文字号 / 行距（跟随排版设置） |
| \`--space-chart-1\` … \`--space-chart-6\` | 图表系列色 |
| \`--space-pop-duration\` / \`--space-pop-easing\` | 「轻弹」动效（悬停、按压），用于 \`transition\` |
| \`--space-slide-duration\` / \`--space-slide-easing\` | 「滑移」动效（列表变化、切换） |
| \`--space-expand-duration\` / \`--space-expand-easing\` | 「展开」动效（图表、展开） |
| \`--space-emerge-duration\` / \`--space-emerge-easing\` | 「浮现」动效（卡片进入） |
| \`--space-ease\` | 不带回弹的缓动 |

**字体由你按页面风格决定。** 页面默认用 \`--space-font\`（用户的正文字体，可能是衬线体）。仪表盘、数据卡片这类界面感强的主页可以在 \`body\` 上改用 \`--space-ui-font\`；读书、写作这类阅读感强的主页可以保留正文字体；大数字、标题也可以单独换字体。只用系统里有的字体，不要从网上加载。

动效变量按用户选的动效强度给出；用户开启「减弱动态效果」时，请只做淡入淡出（\`@media (prefers-reduced-motion: reduce)\`）。示例：\`transition: transform var(--space-pop-duration) var(--space-pop-easing);\`

| class | 用途 |
|---|---|
| \`.space-card\` | 卡片 |
| \`.space-grid\` | 自动换行的卡片网格 |
| \`.space-row\` | 横向排列 |
| \`.space-muted\` | 次要文字 |
| \`.space-button\` | 按钮（\`.space-button.space-secondary\` 为次要按钮） |
| \`.space-input\` | 输入框 |

## 设计与自定义

**页面完全由你决定。** 你可以自由编写 HTML、CSS、JS、SVG、\`<canvas>\`，内置组件和下面的样式只是起点，不是限制：可以只用组件，只用自己的写法，或者混用。目标是一个**好看、实用、像原生应用**的主页。

推荐的做法：

1. **先定结构。** 最重要的一两个数字放最上面最大；按主题分组（\`.space-section\`），每组 2–6 张卡片，用 \`.space-bento\` 网格排成大小不一的卡片。
2. **再定颜色。** 每类数据固定一个色相（\`data-hue\`），同一种数据在整页里颜色一致。整页的强调卡片用光晕（\`.space-glow\`），其余可以用素雅卡片（\`.space-card\`）或柔彩（\`.space-tint\`），不要每张都是光晕。
3. **然后是图表和动效。** 图表用 \`space.chart\`；数字用 \`data-space-count\` 滚动出现；进行中的状态用 \`.space-live\`。动效要克制：一页里持续动的东西不超过两三处。
4. **自己写的部分也用设计变量**（\`var(--space-*)\`、\`space.theme()\`），这样浅色、深色、强调色和排版变化时页面跟着变。

### 检查清单

- 浅色和深色模式都好看，文字和背景的对比度足够（次要文字不要太淡）。
- 没有数据时卡片也有内容：说明 + 一个「记第一笔」之类的入口。
- 窗口变窄时不挤、不溢出（\`.space-bento\` 会自动变成 2 列、1 列；自己写的布局请用 \`minmax(0, 1fr)\`、\`min-width: 0\`）。
- 数字照实显示，单位清楚；日期用中文习惯（10月22日）。
- 动效跟随 \`--space-motion-amplitude\`，并在 \`@media (prefers-reduced-motion: reduce)\` 下停止。
- 图表和日历的时间跨度跟着数据走：只有几天的记录时不要画 12 周或一整年的空格子，可以从第一条记录开始，或显示最近 7–30 天。
- 录入表单在窄卡片里也整齐：输入框可以缩小（\`min-width: 0\`、\`flex: 1 1 8em\`），按钮和输入框留在同一行或整体换行，占位文字不要被截断。
- 页面不报错（错误会显示在页面顶部）。

### 色相

10 个色相，每个有四个值：\`--space-<色相>\`（纯色）、\`--space-<色相>-deep\`（深色卡片底）、\`--space-<色相>-tint\`（深色底上的浅色文字）、\`--space-<色相>-glow\`（光晕）。色相：\`red\` \`orange\` \`yellow\` \`green\` \`teal\` \`blue\` \`indigo\` \`purple\` \`pink\` \`graphite\`。

在任何元素上写 \`data-hue="green"\`，它和它里面的元素就有 \`--space-hue\`、\`--space-hue-deep\`、\`--space-hue-tint\`、\`--space-hue-glow\`；不写时是强调色。下面的卡片风格和小部件都用它们。

### 其他变量

| 变量 | 含义 |
|---|---|
| \`--space-text-xs\` … \`--space-text-display\` | 字号：xs 11.5、s 12.5、m 14、l 17、xl 22、xxl 30、display 48（px） |
| \`--space-radius-s\` / \`-m\` / \`-l\` | 圆角 10 / 14 / 24 px |
| \`--space-gap\` | 卡片间距 |
| \`--space-shadow-raised\` | 抬起时的阴影 |
| \`--space-mesh\` | 彩色背景渐变（\`body.space-mesh\` 或 \`.space-mesh\` 使用） |
| \`--space-motion-amplitude\` | 动效幅度（轻 0.6、标准 1、强 2），自己的动画距离乘上它 |

### 布局

\`\`\`html
<header class="space-header">
  <div><h1>健身记录</h1><div class="space-header-sub">本月 12 次 · 今天 21:40 更新</div></div>
  <div class="space-segmented"><button>本周</button><button aria-pressed="true">本月</button><button>全部</button></div>
</header>
<section class="space-section">
  <h2 class="space-section-title">概览 <span class="space-section-hint">与上月相比</span></h2>
  <div class="space-bento">
    <div class="space-glow space-m" data-hue="red">…</div>
    <div class="space-card">…</div>
    <div class="space-card">…</div>
  </div>
</section>
\`\`\`

- \`.space-bento\`：4 列网格；子元素默认占 1 列，\`.space-m\` 2 列，\`.space-l\` 3 列，\`.space-full\` 整行，\`.space-tall\` 占两行高。窗口窄时自动变成 2 列、1 列。
- \`.space-header\`（\`.space-header-title\` / \`h1\`、\`.space-header-sub\`）、\`.space-section\`、\`.space-section-title\`、\`.space-section-hint\`。
- \`.space-grid\`（自动换行、等宽）仍然可用。

### 卡片风格

| class | 样子 |
|---|---|
| \`.space-card\` | 素雅卡片（白底 / 深色底，无边框） |
| \`.space-glow\` | 光晕：色相的深色底，里面有缓慢飘动的光，白色粗标题、同色调浅色副标题。里面的组件和 \`--space-text\`、\`--space-muted\` 等颜色自动换成适合深色底的值 |
| \`.space-glass\` | 毛玻璃：半透明、模糊背后的内容；配合 \`body.space-mesh\` 最好看 |
| \`.space-tint\` | 柔彩：带一点色相的浅色卡片 |

光晕的位置可以用 \`--space-glow-x\`、\`--space-glow-y\` 调整（默认 55%、78%）。

### 文字与小部件

| class | 用途 |
|---|---|
| \`.space-title\` / \`.space-subtitle\` | 卡片标题 / 副标题（光晕卡片里副标题是同色调的浅色） |
| \`.space-label\` | 小标签（次要文字） |
| \`.space-big\` | 大数字，单位写在里面的 \`<small>\` |
| \`.space-num\` | 等宽数字 |
| \`.space-up\` / \`.space-down\` | 上升 / 下降 |
| \`.space-segmented\` | 分段切换，里面放 \`<button>\`，选中的加 \`aria-pressed="true"\` |
| \`.space-chip\` | 标签（跟随 \`data-hue\`） |
| \`.space-glass-button\` | 玻璃按钮（光晕卡片上用）；\`.space-glass-button.space-solid\` 是白色实心按钮 |
| \`.space-progress\` | 进度条：\`<div class="space-progress" style="--space-value: 62"></div>\`（0–100，出现时从 0 长到该值） |
| \`.space-ring\` | 进度环：\`<div class="space-ring-wrap"><div class="space-ring" style="--space-value: 75"></div><span>75%</span></div>\`；大小用 \`--space-ring-size\`、粗细用 \`--space-ring-width\` |

### 动效

| 写法 | 效果 |
|---|---|
| \`data-space-count\` | 数字从 0 滚动到它自己（例如 \`<span data-space-count>540</span>\`）；之后改这个属性的值，会从旧值滚到新值。\`data-space-duration\` 设时长（毫秒） |
| \`.space-lift\` | 悬停时微微抬起 |
| \`.space-spotlight\` | 光跟着指针走（光晕卡片上很好看） |
| \`.space-float\` | 轻轻浮动 |
| \`.space-shimmer\` | 一道光扫过（进度条、按钮） |
| \`.space-live\` | 前面有呼吸的小圆点，表示进行中 |
| \`.space-breathe\` | 文字发光一明一暗（计时器） |

这些都跟随用户的动效强度，开启「减弱动态效果」时自动停止。光晕卡片里的光一直缓慢飘动，不需要另外写。自己写动画时，请用动效变量（见「样式包」）并乘上 \`--space-motion-amplitude\`。

### 图表：\`space.chart\`

笔记应用内置了 [ECharts](https://echarts.apache.org) 6，离线可用，用到时才加载。\`space.chart(元素或选择器, option)\` 画图并返回 ECharts 实例：

- 配色（\`--space-chart-1…6\`）、字体、坐标轴、网格线和毛玻璃提示框都跟随笔记应用，浅色深色切换时自动换色，不需要你写颜色。
- 元素尺寸变化时自动重绘；元素没有高度时设为 220px。
- 用户开启「减弱动态效果」时不播放动画。
- \`option\` 可以是函数 \`(theme) => option\`：外观变化时会用新的 \`theme\` 再调用一次，适合用到色相的图（例如光晕卡片里的白色折线）。
- 之后要更新数据，直接调用返回实例的 \`setOption\`。
- 想用 ECharts 的全部能力（\`echarts.graphic\` 渐变等）：\`const echarts = await space.load("echarts")\`。

\`\`\`html
<div class="space-card space-m">
  <div class="space-label">体重与训练时长</div>
  <div id="trend" style="height: 220px"></div>
</div>
<script>
  async function drawTrend() {
    const rows = await space.query("健身/训练记录.md", { sort: "日期" });
    const chart = await space.chart("#trend", {
      tooltip: { trigger: "axis" },
      legend: { right: 0 },
      xAxis: { type: "time" },
      yAxis: [{ type: "value", scale: true }, { type: "value" }],
      series: [
        { name: "体重", type: "line", data: rows.map(r => [r.日期, r.体重]), areaStyle: { opacity: 0.15 } },
        { name: "时长", type: "bar", yAxisIndex: 1, data: rows.map(r => [r.日期, r.时长]) },
      ],
    });
  }
  drawTrend();
  space.on("change", drawTrend);
</script>
\`\`\`

量级差别大的两组数用两个 y 轴（\`yAxisIndex\`）；日期请用 \`type: "time"\`，不要当作类别。

### 其他接口

- \`space.theme()\`：当前外观下解析好的颜色和字体（\`rgb()\` 字符串，可以直接用在画布、SVG 和 ECharts 里），以及 \`dark\`、\`reducedMotion\`、\`amplitude\`。\`space.on("theme", (theme) => …)\` 在外观、强调色、排版、动效强度变化时触发。
- \`space.open(path)\`：在笔记应用里打开范围内的一篇笔记（例如点击笔记卡片）。
- \`space.toast(message, { action, onAction, duration })\`：页面底部的提示，例如删除后 \`space.toast("已删除 1 条", { action: "撤销", onAction: undo })\`。

### 例子：光晕数字卡

\`\`\`html
<div class="space-bento">
  <div class="space-glow space-m space-spotlight" data-hue="red">
    <div class="space-title">本月训练</div>
    <div class="space-subtitle" id="month-delta">　</div>
    <div style="display: flex; gap: 32px; margin-top: 40px">
      <div><div class="space-label">次数</div><div class="space-big"><span data-space-count id="month-count">0</span><small>次</small></div></div>
      <div><div class="space-label">时长</div><div class="space-big"><span data-space-count id="month-minutes">0</span><small>分钟</small></div></div>
    </div>
  </div>
  <div class="space-glow space-m" data-hue="green">
    <div class="space-title">本月目标</div>
    <div class="space-subtitle"><span id="goal-text">　</span></div>
    <div class="space-progress space-shimmer" id="goal" style="--space-value: 0; height: 14px; margin-top: 48px"></div>
  </div>
</div>
<script>
  async function drawMonth() {
    const month = space.today().slice(0, 7);
    const rows = await space.query("健身/训练记录.md", { filter: r => String(r.日期).startsWith(month) });
    const minutes = rows.reduce((sum, r) => sum + (r.时长 || 0), 0);
    document.getElementById("month-count").setAttribute("data-space-count", rows.length);
    document.getElementById("month-minutes").setAttribute("data-space-count", minutes);
    document.getElementById("month-delta").textContent = rows.length ? \`最近一次 \${rows.at(-1).日期.slice(5).replace("-", "月")}日\` : "这个月还没有记录";
    document.getElementById("goal").style.setProperty("--space-value", Math.min(100, rows.length / 16 * 100));
    document.getElementById("goal-text").textContent = \`\${rows.length} / 16 次\`;
  }
  drawMonth();
  space.on("change", drawMonth);
</script>
\`\`\`

### 例子：自己写的组件

需要内置组件没有的东西（清单、计时器、笔记卡片……）时，直接写。数据仍然只经过 \`space\` 读写：

\`\`\`html
<div class="space-tint" data-hue="teal" id="notes"></div>
<script>
  async function drawNotes() {
    const notes = (await space.notes()).sort((a, b) => b.modified.localeCompare(a.modified)).slice(0, 4);
    const box = document.getElementById("notes");
    box.replaceChildren(...notes.map(note => {
      const item = document.createElement("button");
      item.className = "space-lift";
      item.style.cssText = "display:block;width:100%;text-align:left;font:inherit;color:inherit;background:none;border:0;padding:8px;border-radius:10px;cursor:pointer";
      item.innerHTML = \`<b></b><div class="space-label"></div>\`;
      item.querySelector("b").textContent = note.title;
      item.querySelector(".space-label").textContent = new Date(note.modified).toLocaleDateString("zh-CN", { month: "long", day: "numeric" });
      item.onclick = () => space.open(note.path);
      return item;
    }));
  }
  drawNotes();
  space.on("change", drawNotes);
</script>
\`\`\`

## 小组件

组件是通用的：它们不知道「健身」「雅思」这些主题，只认识记录表和字段。通用属性：

- \`source\`（读）/ \`target\`（写）：记录表位置，见上文。
- \`label\`、\`title\`：显示名称；\`unit\`：单位；\`color\`：颜色（任何 CSS 颜色，如 \`var(--space-chart-2)\`）。

数据变化时组件会自动重绘。字体和字号跟随页面（也就是用户的排版设置），入场动效跟随用户的动效强度。

### \`<space-stat>\` 大数字

\`\`\`html
<space-stat source="健身/训练记录.md#卧推" op="max" field="重量" period="all" label="卧推纪录" unit="kg"></space-stat>
\`\`\`

- \`op\`：\`count\`（条数，默认）、\`sum\`、\`avg\`、\`max\`、\`min\`、\`latest\`（最新一条的值）。除 \`count\` 外都需要 \`field\`。
- \`period\`：\`all\`（默认）、\`today\`、\`week\`（本周，周一开始）、\`month\`、\`year\`；需要日期字段，用 \`date-field\` 指定，默认是第一个日期类型的字段。
- \`digits\`：小数位数（默认自动）。

### \`<space-chart>\` 折线图 / 柱状图

\`\`\`html
<space-chart source="健身/训练记录.md#卧推" x="日期" y="重量" type="line" title="卧推重量" unit="kg"></space-chart>
\`\`\`

- \`type\`：\`line\`（默认）或 \`bar\`。
- \`x\`：横轴字段；\`y\`：一个或多个纵轴字段（逗号分隔）。
- \`agg\`：同一个 x 值有多条记录时的合并方式，\`sum\`（默认）、\`avg\`、\`max\`、\`min\`、\`count\`、\`last\`。
- \`limit\`：只显示最近 N 个 x 值。
- \`height\`：高度（像素，默认 180）。

### \`<space-calendar>\` 打卡热力日历

\`\`\`html
<space-calendar source="健身/训练记录.md" field="日期" label="打卡"></space-calendar>
\`\`\`

- \`field\`：日期字段（默认第一个日期类型的字段）。
- \`value\`：可选，用这个数字字段的合计决定颜色深浅；不写时按条数。
- \`weeks\`：显示最近几周（默认按卡片宽度铺满）。

### \`<space-quick-add>\` 快捷录入

\`\`\`html
<space-quick-add target="健身/训练记录.md#卧推" fields="日期, 动作, 重量, 组数" label="记一组"></space-quick-add>
\`\`\`

- 按目标记录表的表头和字段类型生成输入框：数字字段用数字输入，日期字段默认填今天，其余是文本。
- \`fields\`：表不存在时用来新建的表头（逗号分隔）；表已存在时以表头为准。
- \`defaults\`：默认值，JSON，例如 \`defaults='{"动作":"卧推"}'\`。
- 提交后记录写入表格末尾，进入操作记录。

### \`<space-records>\` 最近记录

\`\`\`html
<space-records source="健身/训练记录.md#卧推" limit="5" fields="日期, 重量" title="最近训练"></space-records>
\`\`\`

- \`limit\`：显示几条（默认 5），按表格从下往上取最新的。
- \`fields\`：显示哪些字段（默认全部）。

## \`space\` 接口

页面访问笔记的唯一通道，组件内部也只用它。所有方法都返回 Promise；失败时 Promise 被拒绝，错误对象有 \`code\` 和 \`message\`。路径都相对于笔记库根目录，并且必须在范围内。完整的类型见文末「类型声明」。

### 读取

- \`space.scope()\` → \`{ library: true }\` 或 \`{ library: false, folders: ["健身", "日记"] }\`
- \`space.notes(folder?)\` → \`[{ path, title, modified }]\`，范围内（或范围内某个文件夹下）的全部笔记
- \`space.read(path)\` → 笔记全文（字符串）
- \`space.tables(path?)\` → \`[{ source, header }]\`，范围内（或某篇笔记里）可定位的记录表
- \`space.query(source, options?)\` → 记录数组。每条记录是 \`{ 字段: 值 }\`，数字字段是 number，日期和文字是字符串，空单元格是 \`null\`。
  - 数组的 \`fields\` 属性是 \`[{ name, type }]\`；每条记录有不可枚举的 \`_row\`（在表中的行号，从 0 开始）。
  - \`options.filter\`：对象（字段等于该值）或函数 \`(record) => boolean\`。
  - \`options.sort\`：字段名；前面加 \`-\` 表示倒序，例如 \`"-日期"\`。
  - \`options.limit\`：最多返回几条。
  - 记录表不存在时返回空数组。

### 写记录

- \`space.append(target, record 或 records, options?)\` → \`{ count }\`。\`options.header\` 指定新建时的表头，默认按记录里字段出现的顺序。记录里有表头之外的字段会报错。
- \`space.update(target, match, changes)\` → \`{ count }\`。\`match\` 是对象：字段等于该值的记录都会被修改；也可以用 \`{ _row: 3 }\` 指定行。
- \`space.remove(target, match)\` → \`{ count }\`，\`match\` 同上。
- 字符串值里的占位符会被展开，例如 \`{ 日期: "{今天}" }\`。

### 写笔记

- \`space.create(path, content)\`：新建笔记，已存在时报错。
- \`space.write(path, content)\`：覆盖笔记全文（笔记不存在时新建）。
- \`space.rename(path, newTitle)\`：改名（不含 \`.md\`），范围内指向它的链接会被更新。
- \`space.move(path, folder)\`：移动到范围内的另一个文件夹，范围内的链接会被更新。
- 如果范围外的笔记链接到这篇笔记，改名和移动会被拒绝（\`outside-scope\`），因为范围外的笔记不能被修改。
- \`space.trash(path)\`：移到废纸篓。

### 空间文件自身

- \`space.page()\` → 当前空间文件的全文。
- \`space.writePage(html)\`：重写当前空间文件。不能改变 \`space-scope\`，不能访问其他空间文件。

### 其他

- \`space.today()\` → 今天的日期 \`YYYY-MM-DD\`（本地时间，同步返回）。
- \`space.open(path)\`、\`space.theme()\`、\`space.load(name)\`、\`space.chart(target, option)\`、\`space.toast(message, options?)\`：见「设计与自定义」。

### 事件

- \`space.on("theme", (theme) => { … })\`：外观、强调色、排版或动效强度变化时触发。
- \`space.on("change", (paths) => { … })\`：范围内的文件变化时触发（用户在编辑器里保存、外部工具修改、\`space\` 写入都算），\`paths\` 是变化的路径。返回取消订阅的函数。组件已经自动刷新，你自己写的部分需要订阅它。

### 错误码

\`outside-scope\`（范围外或被禁止的路径）、\`not-found\`、\`exists\`、\`unknown-field\`、\`scope-change\`（试图修改范围）、\`invalid\`（参数不对）、\`conflict\`、\`failed\`。

## 示例

\`\`\`html
<meta name="space-scope" content="健身">
<meta name="space-icon" content="🏋️">

<div class="space-grid">
  <div class="space-card"><space-stat source="健身/训练记录.md#卧推" period="week" label="本周训练" unit="次"></space-stat></div>
  <div class="space-card"><space-stat source="健身/训练记录.md#卧推" op="max" field="重量" label="卧推纪录" unit="kg"></space-stat></div>
</div>
<div class="space-card"><space-chart source="健身/训练记录.md#卧推" x="日期" y="重量" title="卧推重量" unit="kg"></space-chart></div>
<div class="space-card"><space-calendar source="健身/训练记录.md#卧推" label="打卡"></space-calendar></div>
<div class="space-card"><space-quick-add target="健身/训练记录.md#卧推" fields="日期, 动作, 重量, 组数" defaults='{"动作":"卧推"}' label="记一组"></space-quick-add></div>
<div class="space-card" id="streak"></div>
<script>
  async function draw() {
    const rows = await space.query("健身/训练记录.md#卧推", { sort: "-日期" });
    const days = new Set(rows.map(r => r.日期));
    const key = (x) => \`\${x.getFullYear()}-\${String(x.getMonth() + 1).padStart(2, "0")}-\${String(x.getDate()).padStart(2, "0")}\`;
    let streak = 0, d = new Date();
    while (days.has(key(d))) { streak++; d.setDate(d.getDate() - 1); }
    document.getElementById("streak").textContent = \`已连续训练 \${streak} 天\`;
  }
  draw();
  space.on("change", draw);
</script>
\`\`\`

## 旧名称

早期的空间主页用 \`lb\` 系列名称。它们是永久保留的别名，旧页面不用修改就能运行；新页面请只用上面的新名称。

| 旧名称 | 新名称 |
|---|---|
| \`lb\` 对象（\`lb.query\` 等） | \`space\`（同一个对象） |
| \`lb-*\` 组件（\`<lb-stat>\` 等） | \`space-*\` 组件 |
| \`--lb-*\` 变量（\`--lb-accent\` 等）、\`.lb-*\` class | \`--space-*\` 变量、\`.space-*\` class |
| \`lb-scope\`、\`lb-icon\` meta | \`space-scope\`、\`space-icon\` |

一个文件里同时写了 \`space-scope\` 和 \`lb-scope\` 时，以 \`space-scope\` 为准。

## 类型声明

用 TypeScript 或想检查用法时，可以把下面这段保存为 \`space.d.ts\` 放在你的工作目录（不要放进笔记库）。

\`\`\`ts
${spaceTypes}\`\`\`
`;
