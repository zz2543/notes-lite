// The authoring guide installed at `.notes/空间/编写说明.md`, overwritten whenever it differs from
// this version's. Ported from the old app's SpaceGuide with the new folder; ticket 20 renames the
// interface and adds its type declarations.

/** Bumped whenever the text changes. */
export const spaceGuideVersion = 2;

export const spaceGuide = `<!-- 空间主页编写说明 · 版本 2 · 由笔记应用自动生成，升级时会被覆盖，请不要手动修改 -->
# 空间主页编写说明

你要编写的是笔记应用里某个**空间**的**空间主页**：一个 HTML 页面，围绕一个主题（例如健身、雅思）展示每天的进展，并提供快捷录入。用户把新建空间时复制的提示词交给你，提示词里有空间文件路径、范围和现有记录表。

## 必须遵守的规则

1. **数据只存记录表。** 空间主页自身不保存任何记录。所有数据都写进范围内笔记里的 Markdown 表格（记录表）。
2. **联网拿到的数据必须写入记录表**（用 \`lb.append\` 等），不能只显示在页面上或缓存在页面里。
3. **localStorage 只存界面偏好**（例如上次选的标签、图表按周还是按月），不能存记录。
4. **只能访问范围内的路径。** 范围外的笔记、\`..\`、隐藏目录和 \`.notes/\` 一律被拒绝。页面不能运行命令，也不能访问笔记库外的文件。
5. **不要修改空间文件开头的 \`lb-scope\`。** 范围由用户在笔记应用里设置；页面试图改变范围的写入会被拒绝。
6. 所有写入都会进入用户可以逐条撤销的操作记录，删除的笔记会进废纸篓。写入要克制：只写用户需要的数据。

## 空间文件

每个空间是笔记库里的 \`.notes/空间/<名称>.html\`。开头是笔记应用写的 meta，之后是空间主页正文：

\`\`\`html
<meta name="lb-scope" content="健身, 日记">   <!-- 范围：逗号分隔的文件夹；整个笔记库写 * -->
<meta name="lb-icon" content="🏋️">           <!-- 图标 -->

<div class="lb-card">
  <h2>本周训练</h2>
  <lb-stat source="健身/训练记录.md" op="count" period="week" label="本周训练" unit="次"></lb-stat>
</div>
\`\`\`

- 只写 \`<body>\` 里的内容即可（可以包含 \`<style>\`、\`<script>\`），笔记应用会注入样式包、组件和 \`lb\` 接口。
- meta 之后为空表示「还没有主页」。保存文件后，笔记应用会自动刷新显示。
- 页面可以联网，可以用 \`<script src="https://cdn.jsdelivr.net/...">\` 引用网上的库，也可以 \`fetch\` 外部数据。
- 网上的 \`<script src>\` 加载完之前，它后面的脚本不会运行。先用组件和 \`lb\` 把数据显示出来，再在需要外部库的地方检查它是否已加载（例如 \`if (window.Chart)\`），网络慢时页面也不会空着。
- 页面里的 JS 报错会显示在页面顶部的错误条上，用户可以把错误复制给你修复。错误里的行号就是空间文件里的行号。
- 页面不能跳转到别的网址（点击链接会在用户的浏览器里打开）。嵌入的 \`<iframe>\` 里没有 \`lb\`。

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

笔记应用注入的 CSS 变量和 class，跟随深色模式。用它们，页面就会和笔记应用原生界面一致。

| 变量 | 含义 |
|---|---|
| \`--lb-bg\` | 页面背景 |
| \`--lb-card\` | 卡片背景 |
| \`--lb-text\` | 正文颜色 |
| \`--lb-muted\` | 次要文字颜色 |
| \`--lb-line\` | 分隔线、边框 |
| \`--lb-accent\` | 强调色 |
| \`--lb-accent-soft\` | 浅强调色（填充） |
| \`--lb-good\` / \`--lb-warn\` / \`--lb-bad\` | 状态色 |
| \`--lb-radius\` | 卡片圆角 |
| \`--lb-font\` / \`--lb-mono\` | 正文字体 / 等宽字体 |
| \`--lb-chart-1\` … \`--lb-chart-6\` | 图表系列色 |

| class | 用途 |
|---|---|
| \`.lb-card\` | 卡片 |
| \`.lb-grid\` | 自动换行的卡片网格 |
| \`.lb-row\` | 横向排列 |
| \`.lb-muted\` | 次要文字 |
| \`.lb-button\` | 按钮 |
| \`.lb-input\` | 输入框 |

## 小组件

组件是通用的：它们不知道「健身」「雅思」这些主题，只认识记录表和字段。通用属性：

- \`source\`（读）/ \`target\`（写）：记录表位置，见上文。
- \`label\`、\`title\`：显示名称；\`unit\`：单位；\`color\`：颜色（任何 CSS 颜色，如 \`var(--lb-chart-2)\`）。

数据变化时组件会自动重绘。

### \`<lb-stat>\` 大数字

\`\`\`html
<lb-stat source="健身/训练记录.md#卧推" op="max" field="重量" period="all" label="卧推纪录" unit="kg"></lb-stat>
\`\`\`

- \`op\`：\`count\`（条数，默认）、\`sum\`、\`avg\`、\`max\`、\`min\`、\`latest\`（最新一条的值）。除 \`count\` 外都需要 \`field\`。
- \`period\`：\`all\`（默认）、\`today\`、\`week\`（本周，周一开始）、\`month\`、\`year\`；需要日期字段，用 \`date-field\` 指定，默认是第一个日期类型的字段。
- \`digits\`：小数位数（默认自动）。

### \`<lb-chart>\` 折线图 / 柱状图

\`\`\`html
<lb-chart source="健身/训练记录.md#卧推" x="日期" y="重量" type="line" title="卧推重量" unit="kg"></lb-chart>
\`\`\`

- \`type\`：\`line\`（默认）或 \`bar\`。
- \`x\`：横轴字段；\`y\`：一个或多个纵轴字段（逗号分隔）。
- \`agg\`：同一个 x 值有多条记录时的合并方式，\`sum\`（默认）、\`avg\`、\`max\`、\`min\`、\`count\`、\`last\`。
- \`limit\`：只显示最近 N 个 x 值。
- \`height\`：高度（像素，默认 180）。

### \`<lb-calendar>\` 打卡热力日历

\`\`\`html
<lb-calendar source="健身/训练记录.md" field="日期" label="打卡"></lb-calendar>
\`\`\`

- \`field\`：日期字段（默认第一个日期类型的字段）。
- \`value\`：可选，用这个数字字段的合计决定颜色深浅；不写时按条数。
- \`weeks\`：显示最近几周（默认按卡片宽度铺满）。

### \`<lb-quick-add>\` 快捷录入

\`\`\`html
<lb-quick-add target="健身/训练记录.md#卧推" fields="日期, 动作, 重量, 组数" label="记一组"></lb-quick-add>
\`\`\`

- 按目标记录表的表头和字段类型生成输入框：数字字段用数字输入，日期字段默认填今天，其余是文本。
- \`fields\`：表不存在时用来新建的表头（逗号分隔）；表已存在时以表头为准。
- \`defaults\`：默认值，JSON，例如 \`defaults='{"动作":"卧推"}'\`。
- 提交后记录写入表格末尾，进入操作记录。

### \`<lb-records>\` 最近记录

\`\`\`html
<lb-records source="健身/训练记录.md#卧推" limit="5" fields="日期, 重量" title="最近训练"></lb-records>
\`\`\`

- \`limit\`：显示几条（默认 5），按表格从下往上取最新的。
- \`fields\`：显示哪些字段（默认全部）。

## \`lb\` 接口

页面访问笔记的唯一通道，组件内部也只用它。所有方法都返回 Promise；失败时 Promise 被拒绝，错误对象有 \`code\` 和 \`message\`。路径都相对于笔记库根目录，并且必须在范围内。

### 读取

- \`lb.scope()\` → \`{ library: true }\` 或 \`{ library: false, folders: ["健身", "日记"] }\`
- \`lb.notes(folder?)\` → \`[{ path, title, modified }]\`，范围内（或范围内某个文件夹下）的全部笔记
- \`lb.read(path)\` → 笔记全文（字符串）
- \`lb.tables(path?)\` → \`[{ source, header }]\`，范围内（或某篇笔记里）可定位的记录表
- \`lb.query(source, options?)\` → 记录数组。每条记录是 \`{ 字段: 值 }\`，数字字段是 number，日期和文字是字符串，空单元格是 \`null\`。
  - 数组的 \`fields\` 属性是 \`[{ name, type }]\`；每条记录有不可枚举的 \`_row\`（在表中的行号，从 0 开始）。
  - \`options.filter\`：对象（字段等于该值）或函数 \`(record) => boolean\`。
  - \`options.sort\`：字段名；前面加 \`-\` 表示倒序，例如 \`"-日期"\`。
  - \`options.limit\`：最多返回几条。
  - 记录表不存在时返回空数组。

### 写记录

- \`lb.append(target, record 或 records, options?)\` → \`{ count }\`。\`options.header\` 指定新建时的表头，默认按记录里字段出现的顺序。记录里有表头之外的字段会报错。
- \`lb.update(target, match, changes)\` → \`{ count }\`。\`match\` 是对象：字段等于该值的记录都会被修改；也可以用 \`{ _row: 3 }\` 指定行。
- \`lb.remove(target, match)\` → \`{ count }\`，\`match\` 同上。
- 字符串值里的占位符会被展开，例如 \`{ 日期: "{今天}" }\`。

### 写笔记

- \`lb.create(path, content)\`：新建笔记，已存在时报错。
- \`lb.write(path, content)\`：覆盖笔记全文（笔记不存在时新建）。
- \`lb.rename(path, newTitle)\`：改名（不含 \`.md\`），范围内指向它的链接会被更新。
- \`lb.move(path, folder)\`：移动到范围内的另一个文件夹，范围内的链接会被更新。
- 如果范围外的笔记链接到这篇笔记，改名和移动会被拒绝（\`outside-scope\`），因为范围外的笔记不能被修改。
- \`lb.trash(path)\`：移到废纸篓。

### 空间文件自身

- \`lb.page()\` → 当前空间文件的全文。
- \`lb.writePage(html)\`：重写当前空间文件。不能改变 \`lb-scope\`，不能访问其他空间文件。

### 其他

- \`lb.today()\` → 今天的日期 \`YYYY-MM-DD\`（本地时间，同步返回）。

### 事件

- \`lb.on("change", (paths) => { … })\`：范围内的文件变化时触发（用户在编辑器里保存、外部工具修改、\`lb\` 写入都算），\`paths\` 是变化的路径。组件已经自动刷新，你自己写的部分需要订阅它。

### 错误码

\`outside-scope\`（范围外或被禁止的路径）、\`not-found\`、\`exists\`、\`unknown-field\`、\`scope-change\`（试图修改范围）、\`invalid\`（参数不对）、\`conflict\`、\`failed\`。

## 示例

\`\`\`html
<meta name="lb-scope" content="健身">
<meta name="lb-icon" content="🏋️">

<div class="lb-grid">
  <div class="lb-card"><lb-stat source="健身/训练记录.md#卧推" period="week" label="本周训练" unit="次"></lb-stat></div>
  <div class="lb-card"><lb-stat source="健身/训练记录.md#卧推" op="max" field="重量" label="卧推纪录" unit="kg"></lb-stat></div>
</div>
<div class="lb-card"><lb-chart source="健身/训练记录.md#卧推" x="日期" y="重量" title="卧推重量" unit="kg"></lb-chart></div>
<div class="lb-card"><lb-calendar source="健身/训练记录.md#卧推" label="打卡"></lb-calendar></div>
<div class="lb-card"><lb-quick-add target="健身/训练记录.md#卧推" fields="日期, 动作, 重量, 组数" defaults='{"动作":"卧推"}' label="记一组"></lb-quick-add></div>
<div class="lb-card" id="streak"></div>
<script>
  async function draw() {
    const rows = await lb.query("健身/训练记录.md#卧推", { sort: "-日期" });
    const days = new Set(rows.map(r => r.日期));
    const key = (x) => \`\${x.getFullYear()}-\${String(x.getMonth() + 1).padStart(2, "0")}-\${String(x.getDate()).padStart(2, "0")}\`;
    let streak = 0, d = new Date();
    while (days.has(key(d))) { streak++; d.setDate(d.getDate() - 1); }
    document.getElementById("streak").textContent = \`已连续训练 \${streak} 天\`;
  }
  draw();
  lb.on("change", draw);
</script>
\`\`\`
`;
