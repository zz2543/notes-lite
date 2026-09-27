# 共笔插件与开放接口：创作者文档

> 适用版本：共笔（Twain）0.2 · 2026-09
> 一句话：**共笔的一切都是库里的文件**。插件是一个文件夹，数据是 JSON Lines，命令和流水线是 Markdown。任何能写文件、能发 HTTP 请求、能调用命令行的东西，都能扩展共笔。

## 目录

1. [能扩展哪些地方](#1-能扩展哪些地方)
2. [插件（空间）](#2-插件空间)
3. [仪表盘模块](#3-仪表盘模块)
4. [HTML 模块与 `window.twain`](#4-html-模块与-windowtwain)
5. [命令与流水线](#5-命令与流水线)
6. [数据集合](#6-数据集合)
7. [本地 HTTP 接口](#7-本地-http-接口)
8. [命令行 `twain` 与 MCP](#8-命令行-twain-与-mcp)
9. [事件与自动化](#9-事件与自动化)
10. [`twain://` 链接](#10-twain-链接)
11. [完整示例：阅读空间](#11-完整示例阅读空间)

---

## 1. 能扩展哪些地方

| 你想做的 | 写什么 | 放在哪 |
|---|---|---|
| 一种新的“模式”（日记、自律、读书……） | 插件：`manifest.json` + 模板 + 规则 | `.twain/plugins/<id>/` |
| 仪表盘上的一块内容 | 声明式模块（JSON）或 HTML 模块 | 插件的 `manifest.json` / `widgets/*.html` |
| 一个 agent 命令（⌘K、斜杠菜单、`twain run`） | Markdown 提示词 | `.twain/commands/*.md` 或插件的 `commands/` |
| 多步协作流程（带审阅关口） | Markdown 流水线 | `.twain/pipelines/*.md` 或插件的 `pipelines/` |
| 事件触发的 agent 任务 | Markdown 自动化 | `.twain/automations/*.md` |
| 从别的 app 导入笔记或数据 | HTTP 请求、CLI、往文件夹里放文件 | 见第 6～8 节 |

建议提交到 git：`.twain/` 下的 `plugins/`、`commands/`、`pipelines/`、`automations/`、`data/`、`summaries.json`、`annotations/`。已被忽略：`proposals/`、`index/`。

---

## 2. 插件（空间）

插件就是一个文件夹：

```
.twain/plugins/reading/
├── manifest.json        必需
├── rules.md             agent 在这个空间的笔记上工作时要遵守的约定
├── templates/book.md    新条目的模板
├── commands/*.md        插件自带的命令
├── pipelines/*.md       插件自带的流水线
└── widgets/*.html       HTML 模块
```

### manifest.json

```json
{
  "id": "reading",
  "name": "读书",
  "icon": "book",
  "description": "一本书一篇笔记，读完让 AI 帮你写书评。",
  "collections": {
    "pages": {"label": "阅读量", "fields": {"pages": {"label": "页数", "unit": "页"}}}
  },
  "space": {
    "folder": "读书",
    "entry": {"title": "{{date}} 读书", "template": "templates/book.md"},
    "rules": "rules.md",
    "modules": [ … 见第 3 节 … ]
  }
}
```

| 字段 | 说明 |
|---|---|
| `id` | 唯一标识，默认取文件夹名 |
| `name`、`icon`、`description` | 名字、SF Symbols 图标名、一句话说明（显示在仪表盘顶部） |
| `collections` | 数据集合的显示名和单位（可选），供图表和数字模块使用 |
| `space.folder` | 这个空间的笔记所在文件夹（相对于库）；`""` 表示整个库 |
| `space.entry.title` | “新条目”的标题模板。可用变量：`{{date}}` `{{time}}` `{{weekday}}` `{{week}}` `{{month}}` `{{year}}` `{{yesterday}}` `{{tomorrow}}` |
| `space.entry.template` | 新条目的正文模板（插件内的相对路径），可以使用同样的变量和 `{{title}}` |
| `space.rules` | 规则文件。agent 在处理 `space.folder` 下的笔记时，这些规则会自动加进它的上下文 |
| `space.modules` | 仪表盘上的模块列表，按顺序排列 |

- **停用**：在插件文件夹里放一个空文件 `.disabled`，或者在“设置 → 开放 → 插件与空间”里关掉开关。
- **修改**：直接编辑文件，共笔会自动重新载入；也可以在仪表盘右上角点“编辑”，增删模块、调整顺序，改动会写回 `manifest.json`，而你手写的其他字段会原样保留。

---

## 3. 仪表盘模块

每个模块都是一个 JSON 对象，`type` 决定类型，`title` 是卡片标题，`"span": 2` 表示占满一整行。

| type | 作用 | 参数 |
|---|---|---|
| `today` | 今天的条目：已经写了就显示摘录，没写就提供“开始写”按钮 | — |
| `calendar` | 类似 GitHub 贡献图，每格是一天，颜色越深那天写得越多；点击打开或新建那天的条目 | `days`（默认 84） |
| `query` | 笔记列表 | `folder`、`tag`、`sort`（`modified` 或 `name`）、`limit` |
| `tasks` | 未完成的待办，可以直接勾选 | `folder`、`tag`、`limit` |
| `ask` | 问库输入框：提交后打开研究台 | `placeholder`、`scope`（`folder:路径` 或 `tag:名字`） |
| `stat` | 一个大数字，可设目标 | `collection`、`field`、`reduce`（`avg`、`sum`、`last`、`max`、`count`）、`days`、`goal` |
| `chart` | 折线图或柱状图（按天汇总） | `collection`、`field`、`reduce`、`days`、`kind`（`line` 或 `bar`）、`goal` |
| `habits` | 习惯打卡 ＋ 最近几天的圆点 | `collection`（默认 `habits`）、`items`（习惯名数组）、`days` |
| `log` | “记一笔”：手动录入数据 | `fields: [{collection, field, label}]` |
| `pipelines` | 流水线按钮 | `items`（流水线 key 数组；省略则列出全部） |
| `note` | 嵌入一篇笔记的开头 | `path` |
| `stats` | 库的概况：笔记数、待办数、待审阅改动数、数据集合数 | — |
| `text` | 一段说明文字（支持行内 Markdown） | `text` |
| `html` | 你自己写的页面 | `file`、`height`，以及任意自定义参数 |

---

## 4. HTML 模块与 `window.twain`

`html` 模块运行在 WKWebView 沙盒里：

- **拦截外网**：http、https、ws、ftp 请求一律被阻止。
- **只能读自己的插件文件夹**，读不到库里的其他文件。
- **与共笔通信**：只能通过注入的 `window.twain` 对象。

```js
// 调用任何对 agent 开放的命令，参数与 CLI 和 MCP 一致，返回 Promise
const r = await twain.call("data.query", { collection: "habits", since: "30d" });
await twain.call("data.add", { collection: "pages", record: { pages: 30 } });
await twain.call("skim", { folder: "读书" });
await twain.open("读书/三体.md", 12);   // 在共笔里打开笔记，可选行号

twain.module     // 这个模块在 manifest 里的 JSON，自定义参数都在这里
twain.plugin     // { id, name }
twain.onDataChange(() => redraw());   // 数据集合变化时回调
```

CSS 变量随浅色、深色模式自动切换：`--tw-text`、`--tw-secondary`、`--tw-accent`、`--tw-fill`、`--tw-bg`。页面背景保持透明即可与卡片融为一体。

**权限与 agent 相同**：
- 读命令和 `data.add` 直接执行。
- 改动笔记要用 `propose` 提交，照样进入用户的审阅。
- 完整示例见自律空间的 `widgets/streaks.html`。

---

## 5. 命令与流水线

### 命令 `commands/<key>.md`

```markdown
---
title: 润色选中段落
agent: claude          # claude | codex
model: sonnet          # 可省略
scope: selection       # selection | note | vault
icon: wand.and.stars
key: polish            # 斜杠菜单里输入 /polish
---
把这段改得更简洁，用 propose_edit 提交：{{selection}}（来自 {{path}} 第 {{line}} 行）
```

模板变量：`{{selection}}`、`{{note}}`、`{{path}}`、`{{title}}`、`{{line}}`、`{{date}}`、`{{input}}`。

### 流水线 `pipelines/<key>.md`

用 `## 标题` 分步。每步开头可以写几行选项：

- `gate:`
  - `review`：等这一步提交的改动全部审阅完，再进入下一步
  - `ask`：停下来，让用户选择继续、按意见重做或停止
  - `none`：自动进入下一步
- `model:`、`effort:`：这一步使用的模型和思考强度

frontmatter 里的 `tools: annotate, cards` 可以给整条流水线开启可选的 MCP 工具。

```markdown
---
title: 读完一本书
agent: claude
scope: note
tools: annotate
---
## 摘出要点
gate: ask
读 {{path}}，列出这本书的 5 个核心观点，每个附上我摘录的原句。

## 写书评
gate: review
根据上一步（{{prev}}）和我的意见，用 propose_edit 在 {{path}} 末尾追加一节“我的书评”。
```

- 步骤之间用 `{{prev}}`（上一步的输出）或 `{{steps.1}}`（第 1 步的输出）传递结果。
- 所有步骤在同一个 agent 会话里运行，后面的步骤记得前面的对话。
- 需要 `{{input}}` 的流水线，启动时会先让用户输入。

---

## 6. 数据集合

数据按集合存放，每个集合一个文件：`.twain/data/<集合>.jsonl`，每行一个 JSON 对象。

- **不需要事先定义结构。**
- **时间**：记录有 `time`（ISO 8601）或 `date`（`yyyy-MM-dd`）字段时按它算；两者都没有时，写入时自动加上当前时间。
- **集合名**：只能包含文字、数字、`-` 和 `_`。

写入方式任选：

```bash
twain data add sleep --record '{"hours": 7.5}'
twain data add workout --record '[{"minutes": 30, "date": "2026-09-26"}, {"minutes": 45}]'
twain data import sleep --file ~/Downloads/sleep.csv       # CSV（第一行是表头）、JSON、JSON Lines
curl -H "Authorization: Bearer $TOKEN" -d '{"hours":7.5}' http://127.0.0.1:27182/v1/data/sleep
cp export.csv 库/.twain/inbox/sleep/                        # 放进来自动导入，处理完移到 已导入/
```

读取：

```bash
twain data                                             # 列出所有集合
twain data query sleep --since 7d                      # 原始记录（7d、4w、3m、1y 或日期）
twain data query sleep --since 30d --field hours --reduce avg   # 按天汇总
```

---

## 7. 本地 HTTP 接口

- **地址**：`http://127.0.0.1:27182/v1`。只监听本机，可以在“设置 → 开放”里关闭或改端口。
- **鉴权**：除 `/v1/ping` 外，每个请求都要带 `Authorization: Bearer <令牌>`。令牌保存在 `~/Library/Application Support/Twain/http-token`（权限 0600），可以在设置里重置。

| 方法与路径 | 请求体或参数 | 作用 |
|---|---|---|
| `GET /v1/ping` | — | 检查共笔是否在运行，返回当前库的名字 |
| `POST /v1/call/<命令>` | 参数对象 | 调用任何对 agent 开放的命令，规则与 CLI、MCP 相同（例如 `propose` 会进入审阅） |
| `GET /v1/data` | — | 列出数据集合 |
| `POST /v1/data/<集合>` | 一条记录，或记录数组 | 写入数据 |
| `GET /v1/data/<集合>` | `?since=7d&limit=&field=&reduce=` | 读取数据 |
| `POST /v1/notes` | `{title, content, folder?, source?, source_id?, open?}` | 导入笔记，见下文 |
| `GET /v1/notes` | `?q=&folder=&tag=` | 笔记名片（skim） |
| `GET /v1/notes/<路径>` | `?level=1\|2\|3&section=` | 分级读取一篇笔记 |

**导入规则**（`POST /v1/notes`）：
- 默认放进 `导入/<source>/`，也可以用 `folder` 指定。
- 带 `source_id` 时按 `source + source_id` 去重：
  - 第一次导入：直接新建笔记。
  - 再次导入且内容相同：跳过。
  - 再次导入且内容变了：共笔提交一份**修改提案**，用户审阅后才写入，绝不覆盖用户的编辑。
- 懂听 GotIt 的接入脚本 `integrations/gotit/twain-gotit-sync.py` 就是这样做的：共笔里没有一行针对它的代码。

---

## 8. 命令行 `twain` 与 MCP

- **CLI**：`twain help` 列出全部命令，`twain help <命令>` 查看参数；加 `--json` 输出 JSON。
- **离线可用**：共笔没开时，只读命令和 `data.*` 命令直接读写库里的文件。
- **agent 默认可用的 MCP 工具（10 个）**：`context`、`search`、`skim`、`read_note`、`backlinks`、`tasks`、`open`、`propose_edit`、`ask_user`、`run_command`。
- **按需开启的工具**：`annotate`（AI 审阅会话）、`cards`（问库会话）。流水线用 `tools:` 开启。
- **分级阅览**：先 `skim` 看名片（标题、标签、一句话摘要），再 `read --level 2` 看提纲，最后才读正文或某一节。名片里的摘要默认从笔记开头提取，不花 token；也可以在“笔记信息”里手写，或让小模型批量生成。

---

## 9. 事件与自动化

用 `twain watch [--events a,b]` 可以持续接收事件（JSON Lines）。自动化文件 `.twain/automations/*.md` 通过 `on:` 订阅事件。

| 事件 | 含义 |
|---|---|
| `note.opened` · `note.saved` · `note.changed` · `note.created` · `note.deleted` · `note.renamed` | 笔记的生命周期 |
| `note.imported` | 外部程序通过接口导入了笔记 |
| `proposal.created` · `review.resolved` | 修改提案的提交和审阅结果 |
| `annotation.created` · `annotation.resolved` | 批注的新建和处理 |
| `data.added` | 数据集合新增了记录（`collection`、`count`） |
| `session.started` · `session.finished` | agent 会话开始和结束 |
| `selection.changed` | 选区变化（需要显式订阅） |

例：每当睡眠数据更新，就在自律空间里补一句观察：

```markdown
---
title: 睡眠变差时提醒我
on: data.added
agent: claude
model: haiku
debounce: 600
---
运行 twain data query sleep --since 7d --field hours。如果最近 3 天平均低于 6.5 小时，用 twain notify 提醒我，并说明哪几天偏少。否则什么都不做。
```

---

## 10. `twain://` 链接

在笔记、网页、快捷指令里都可以使用：

- `twain://open?note=收件箱&line=12`
- `twain://new?title=会议记录&folder=工作&content=…`
- `twain://ask?q=这个月我读了哪些书&scope=folder:读书`
- `twain://run?name=weekly`（命令或流水线的 key）

---

## 11. 完整示例：阅读空间

```
.twain/plugins/reading/manifest.json
```

```json
{
  "id": "reading",
  "name": "读书",
  "icon": "book",
  "description": "一本书一篇笔记，每天记读了多少页。",
  "collections": {"pages": {"label": "阅读", "fields": {"pages": {"label": "页数", "unit": "页"}}}},
  "space": {
    "folder": "读书",
    "entry": {"title": "{{date}} 读书"},
    "rules": "rules.md",
    "modules": [
      {"type": "log", "title": "今天读了多少", "fields": [{"collection": "pages", "field": "pages", "label": "页数"}]},
      {"type": "stat", "title": "近 30 天", "collection": "pages", "field": "pages", "reduce": "sum", "days": 30, "goal": 600},
      {"type": "chart", "title": "每天的阅读量", "collection": "pages", "field": "pages", "days": 30, "kind": "bar", "span": 2},
      {"type": "query", "title": "在读的书", "folder": "读书", "tag": "在读", "limit": 6},
      {"type": "ask", "title": "问问读过的书", "scope": "folder:读书"}
    ]
  }
}
```

```
.twain/plugins/reading/rules.md
```

```markdown
读书/ 下每本书一篇笔记，标签 #在读 或 #读完。摘录用 > 引用并注明页码；我的想法写在摘录下面。整理时不要改动摘录原文。
```

保存后，它会出现在侧栏的“空间”里。
