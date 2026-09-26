# Plume 开放接口计划：让 agent 成为一等用户

> 状态：三个阶段均已完成 · 2026-09-26
> 范围：三个阶段——命令层与 `plume` CLI → MCP 与人机闭环 → 事件流、自动化与自定义命令

## 0. 目标与原则

**目标**：用户能在 Plume 里做的事，agent 都能做；agent 做的事，用户都能看见、能审阅、能撤回。

**原则**

1. **文件仍是唯一真相。** 库依旧是一个 Markdown 文件夹，不引入数据库。`.plume/` 里的索引随时可删、可重建。
2. **只开放文件表达不了的东西。** 读写文件 agent 本来就会，不再包一层 `read_note` / `write_note`。要开放的是三类：
   - 活的界面状态：选区、光标、打开的笔记、待审阅改动
   - 派生索引：反链、标题、待办、标签、搜索
   - 人机交互通道：打开笔记、提交审阅、提问、通知
3. **命令面板就是 API。** 所有动作注册到同一张命令表。⌘K、斜杠菜单、CLI、MCP 都从这张表生成，不允许出现"只有人能做"的操作。
4. **副作用分级决定权限**，不靠逐个工具写死：

   | 等级 | 例子 | 策略 |
   |---|---|---|
   | `read` | `context`、`search`、`backlinks` | 直接放行 |
   | `ui` | `open`、`reveal`、`notify` | 直接放行 |
   | `propose` | `propose_edit`、`ask_user` | 进审阅队列或会话面板 |
   | `write` | `create`、`move`、`trash` | 走审阅模式；`trash` 一律确认 |

5. **工具要少。** MCP 暴露的工具不超过 10 个。更细的能力放进 CLI，agent 需要时用 `--help` 自己查。
6. **没开 app 也能用。** `read` 类命令在 app 没运行时，由 CLI 直接读文件执行。

## 1. 现状（本计划要改的地方）

| 现状 | 位置 | 问题 |
|---|---|---|
| 上下文只有一句"当前笔记是 xxx"，启动时写死 | `AppModel.runAgent`，`Sources/Plume/AppModel.swift` | agent 看不到选区，也拿不到之后的状态 |
| agent 只能靠写文件影响 app，事后做 diff | `finishRun` / `filesChanged` | 没有"为什么这样改"，也没有提问通道 |
| 写入归属靠猜 | `writing` 集合、`mostRecentTerminalSession()` | 多个会话并发时会认错 |
| 命令写死在各处 | `CommandPalette.entries`、`SlashItem.all` | UI 和 agent 不共用；用户无法扩展 |
| 选区只存在于 `NSTextView` 里 | `Editor.swift` | 模型层读不到选区 |
| 子进程环境只有 PATH 和 NO_COLOR | `CLIEnvironment.environment` | 无法注入会话身份 |

## 2. 目标架构

```
PlumeCore（纯逻辑，可测）
├─ JSONValue / RPC 编解码         ← 新增
├─ CommandSpec（命令元数据与参数 schema）← 新增
├─ VaultIndex（链接/标题/待办/标签/搜索）← 新增，app 与 CLI 共用
└─ Markdown / LineDiff / AgentEvents（已有）

Plume.app
├─ CommandRegistry：命令 id → handler(AppModel, args, caller)
├─ AgentServer：Unix socket，按行传 JSON-RPC 2.0
└─ 命令面板和斜杠菜单改为从 Registry 生成

plume（新可执行目标，打包进 Plume.app/Contents/Helpers/plume）
├─ plume <command> [args] [--json]  → 通过 socket 调 app；app 没开时 read 类命令本地执行
├─ plume mcp                         → stdio MCP 服务（阶段二）
└─ plume watch                       → 事件流 JSONL（阶段三）
```

**关键约定**

- **Socket 路径**：`~/Library/Application Support/Plume/run/plume.sock`，权限 0600。路径固定且短，因为 Unix socket 路径上限是 104 字节，库名可能是中文，不能拼进路径。
- **协议**：每行一条 JSON-RPC 2.0 消息。`method` 就是命令 id。请求里带 `caller: { session?: String, pid: Int }`。
- **会话身份**：Plume 启动 agent 时注入以下环境变量：
  - `PLUME_SESSION=<AgentSession.id>`
  - `PLUME_SOCK=<path>`
  - `PATH` 前面加上 `Plume.app/Contents/Helpers`

  CLI 自动带上这些身份信息，app 据此把请求准确归到对应会话。
- **命名冲突**：APFS 默认不区分大小写，`.build` 目录里不能同时出现 `Plume` 和 `plume` 两个文件。所以 SPM 产品命名为 `plume-cli`，`bundle.sh` 复制时改名为 `Helpers/plume`。
- **库根目录识别**（给 CLI 的离线模式用）：从当前目录往上找，先找 `.plume/`，其次找同时有 `AGENTS.md` 和 `CLAUDE.md` 的目录。

---

## 阶段一：命令层、socket 与 `plume` CLI

**要达成**：app 里的 agent 和终端里的 agent，都能用 `plume context` 拿到实时编辑状态，用 `plume search/backlinks` 查询库，用 `plume open` 让用户看到某篇笔记。

### 1.1 PlumeCore 基础类型

- `JSONValue`：可编解码的 JSON 枚举，协议两端共用。
- `RPC`：`Request`、`Response`、`RPCError` 的编解码，加一个按行切分的读取器（复用 `JSONLines.drain` 的思路）。
- `CommandSpec`：
  - 字段：`id`、`title`、`summary`、`params: [ParamSpec]`、`effect`、`palette: PaletteInfo?`
  - `ParamSpec`：`name`、`type`（string/int/bool/string[]）、`required`、`help`
  - 一份 spec 能生成三样东西：CLI 的 `--help`、MCP 的 `inputSchema`、面板的显示文字。

### 1.2 VaultIndex（PlumeCore）

- 输入是库根目录，扫描全部 `.md`，逐行调用 `Markdown.parseLine` 取出以下内容：
  - `[[wikilink]]`，建出出链和反链
  - `#`、`##`、`###` 标题，带行号
  - `- [ ]` 和 `- [x]` 待办，带行号和所在标题
  - `#标签`，需要新增一个小解析函数，排除行首的 `#` 标题
- `search(query, limit)`：标题命中排在正文前面，返回 `path`、`line`、`snippet`。
- 增量更新：`update(rel, content)` 和 `remove(rel)`。app 在 `Vault.handleEvents` 和保存时调用。
- 暂不做持久化缓存：个人库一次全量扫描在 100ms 量级，先测再说（见风险 R3）。

### 1.3 CommandRegistry（app）

新建 `Sources/Plume/Commands.swift`，阶段一注册以下命令：

| id | effect | 说明 |
|---|---|---|
| `context` | read | 当前库、当前笔记、选区文本和范围、光标所在标题链、该笔记的反链、待审阅文件列表、调用者所属会话 |
| `notes` | read | 列出笔记，可按文件夹过滤 |
| `search` | read | 全文搜索 |
| `backlinks` | read | 指定笔记的反链 |
| `outline` | read | 指定笔记的标题树和待办 |
| `tasks` | read | 全库未完成待办，可按文件夹或标签过滤 |
| `open` | ui | 打开笔记，可选定位到行或标题 |
| `reveal` | ui | 在侧栏中定位 |
| `notify` | ui | toast；带 `session` 时同时写进该会话的时间线 |
| `new` / `zen` / `review.next` / … | ui | 把现有面板命令迁进来 |

- `CommandPalette.entries` 里的命令部分改为从 Registry 过滤出 `palette != nil` 的项生成。笔记列表部分不动。
- 面板里写死的 "Claude 总结 / Codex 整理待办" 两条先保留，阶段三改成命令文件。

### 1.4 编辑器状态上提

- `AppModel` 新增 `editorSelection: NSRange`，由 `Editor.swift` 在 `textViewDidChangeSelection` 里节流约 100ms 后写回。
- `context` 从 `editorText` 和 `editorSelection` 算出选区文本和光标所在的标题链。

### 1.5 AgentServer（app）

- 新建 `Sources/Plume/AgentServer.swift`：BSD socket + `DispatchSource` 负责 accept 和读取，每个连接一个串行队列，handler 统一派发到主线程执行（`AppModel` 是主线程对象）。
- 启动时如果残留旧的 sock 文件，先 `unlink` 再重新 bind。退出时在 `applicationWillTerminate` 里清理。
- 同时只允许一个 Plume 实例持有 socket。第二个实例启动时，检测到 socket 能连通就不再抢占。
- 错误码：
  - `-32601`：命令不存在
  - `-32602`：参数错误
  - `1001`：没有打开的库
  - `1002`：需要用户确认，但被拒绝

### 1.6 `plume` CLI（新目标 `PlumeCLI`）

- `Package.swift` 新增 `.executableTarget(name: "PlumeCLI", dependencies: ["PlumeCore"])`，产品名 `plume-cli`。不引入第三方依赖，参数解析手写。
- 用法：`plume <command> [--param value …] [--json]`。
  - 默认输出人读的文本；加 `--json` 输出原始结果。
  - `plume help [command]` 由 CommandSpec 生成。
- 离线模式：socket 连不上时，`read` 类命令用 VaultIndex 在本地执行。`context`、`ui` 类命令返回明确报错："Plume 未运行"。
- `plume --version` 输出版本和协议版本号，为以后兼容留余地。

### 1.7 agent 启动改造（`CLI.swift` / `AppModel.runAgent`）

- `AgentProcess.start` 新增 `extraEnv: [String: String]` 参数，注入 `PLUME_SESSION`、`PLUME_SOCK` 和修改后的 PATH。
- 上下文字符串改为：

  > 你在 Plume 笔记库中工作……可以运行 `plume context` 获取用户当前的笔记、选区和待审阅状态；`plume help` 查看全部命令。直接修改文件即可，Plume 会把改动交给用户审阅。

  当前笔记路径仍直接写在上下文里，省得 agent 为这一条信息多跑一次命令。
- `AGENTS.md` 模板加一小节"Plume 命令"，让终端里的 agent 也知道有 `plume` 可用。

### 1.8 安装命令行工具

- 设置 → Agent 页新增一个按钮："安装 plume 命令"。
  - 做法：把 `~/.local/bin/plume` 软链到 `Helpers/plume`，不需要 sudo。`CLIEnvironment` 已经把这个目录列为兜底路径。
- 状态显示：已安装 / 未安装 / 指向了别的版本。
- `bundle.sh`：复制 `plume-cli` 到 `Contents/Helpers/plume`，并一起 codesign。

### 1.9 终端会话认领（可选，阶段一最后一项）

- `plume attach`：终端 agent 调用后，app 把调用者的 pid 所属进程树认领为一个终端会话，替代 `mostRecentTerminalSession()` 的猜测。
- 推荐流程：在 AGENTS.md 里约定，终端 agent 修改文件前先运行一次 `plume attach`。

### 阶段一验收

- [ ] 在 app 里让 Claude "看看我选中的这段有没有被别的笔记引用"，它能调用 `plume context` 和 `plume backlinks`，回答正确。
- [ ] 终端里 `cd` 到库目录，app 开着时 `plume open 收件箱 --line 3` 能打开笔记并定位；app 关着时 `plume search xxx` 仍能返回结果。
- [ ] ⌘K 里的命令都来自 Registry，行为与改造前一致。
- [ ] 单元测试：RPC 编解码、CommandSpec 生成 help、VaultIndex（链接、标题、待办、标签、搜索排序、增量更新）。
- [ ] `scripts/e2e.sh`：用临时库、带 `PLUME_BACKGROUND` 启动 app，逐条跑 `plume` 命令，对比 JSON 输出。

---

## 阶段二：MCP 与人机闭环

**要达成**：agent 能提交带理由的修改提案、能向用户提问；用户拒绝修改时，原因能回到 agent 手里。

### 2.1 `plume mcp`

- stdio MCP 服务，手写实现 `initialize`、`tools/list`、`tools/call`，协议逻辑放进 PlumeCore 方便测试。每次工具调用都转发到 app 的 socket。
- 暴露的工具（不超过 8 个）：`context`、`search`、`backlinks`、`open`、`notify`、`propose_edit`、`ask_user`、`run_command`（最后一个在阶段三加入）。
- 工具说明由 CommandSpec 生成，每条都写清楚"什么时候该用"。
- 启动参数注入（**需先实测确认**）：
  - Claude：`--mcp-config '{"mcpServers":{"plume":{"command":"<Helpers>/plume","args":["mcp"]}}}'`，并加 `--allowedTools "mcp__plume__*"`，否则 `-p` 模式会卡在权限上。
  - Codex：`-c 'mcp_servers.plume.command="<Helpers>/plume"' -c 'mcp_servers.plume.args=["mcp"]'`
- 设置页加一个开关："给 agent 挂载 Plume 工具（MCP）"，默认开启。关闭后退回阶段一的纯 CLI 方式。

### 2.2 `propose_edit`

- 参数：
  - `path`
  - `content`（整篇替换）或 `edits: [{old, new}]`（片段替换，`old` 必须唯一命中）
  - `reason`：整体理由
  - `notes?: [{line, text}]`：逐段理由，按行号对齐到 hunk
- 语义是**先审后写**：磁盘不变，生成一个提案进入审阅，接受时才写盘。这与现有"agent 先写、再审"的路径并存：
  - `PendingReview` 新增 `origin: .written | .proposed`、`reasons: [Int: String]`、`sessionID`。
  - `finishReview` 对 `.proposed` 应用选中的 hunk 后写盘；全部拒绝时什么都不写。
- 提案持久化到 `.plume/proposals/<id>.json`，app 重启后仍在（见决策 D2）。
- 返回 `{ id, status: "pending" }`；传 `wait: true` 时阻塞到用户处理完，返回每个 hunk 的处理结果。
- ReviewView：每个 hunk 旁显示理由；顶部显示整体理由和来源会话。

### 2.3 `ask_user`

- 参数：`question`、`options?: [String]`、`allowText: Bool`、`timeout`（默认 600 秒）。
- 会话面板里出现一张提问卡片，带选项按钮和输入框。窗口不在前台时发系统通知。
- 调用会阻塞，直到用户作答或超时。超时返回 `{ answered: false }`，让 agent 自己决定怎么继续。
- **需先实测**：Claude Code 对 MCP 工具调用的超时上限（`MCP_TOOL_TIMEOUT`），必要时启动时调大。

### 2.4 拒绝原因回传

- 拒绝某个 hunk 时，可以选填一句原因。
- 审阅结束时，如果有拒绝且填了原因，审阅条出现按钮："把意见发回给 <agent>"。
  - 点击后用该会话的 `cliSessionID` 执行 `--resume`，消息内容是结构化的"接受了哪些、拒绝了哪些、原因是什么"。
- 默认手动点按钮，不自动发送，避免意外产生费用（见决策 D3）。

### 阶段二验收

- [ ] Claude 通过 `propose_edit` 提交三处修改，审阅界面逐段显示理由。拒绝一处并填写原因，点"发回"后，Claude 在同一会话里给出修订版提案。
- [ ] agent 调用 `ask_user` 问"合并到哪篇笔记？"，用户点选项后，agent 按答案继续执行。
- [ ] 同一个 app 里并发跑两个会话，每个改动都归到正确的会话。
- [ ] 单元测试：MCP 消息编解码、`edits` 应用（唯一命中和冲突两种情况）、带理由的 hunk 对齐。

---

## 阶段三：事件流、自动化与自定义命令

**要达成**：AI 从"叫它才动"变成常驻在工作流里；工作流本身以文件形式随库保存。

### 3.1 事件流

- RPC 新增 `subscribe(events: [String])`，连接保持打开，app 向这个连接推送事件。
- `plume watch [--events a,b]` 输出 JSONL。
- 事件类型：
  - `note.opened`、`note.saved`、`note.created`、`note.deleted`、`note.moved`
  - `proposal.created`、`review.resolved`（含每个 hunk 的处理结果）
  - `session.started`、`session.finished`
  - `selection.changed`：需要显式订阅，节流 500ms
- 每个事件都带 `source`：`user`、`agent:<session>` 或 `external`。

### 3.2 自定义命令 `.plume/commands/*.md`

```markdown
---
title: 润色选中段落
agent: claude
model: sonnet
effort: medium
scope: selection        # selection | note | vault
icon: wand.and.stars
key: polish             # 斜杠菜单里输入 /polish 触发
---
把下面这段改得更简洁，保留原意和语气，用 propose_edit 提交：

{{selection}}

（所在笔记：{{path}}）
```

- 启动时和文件变化时加载，注册进 Registry。它们会出现在 ⌘K、斜杠菜单，以及 `plume run <key>` 和 MCP 的 `run_command` 里。
- 模板变量：`{{selection}}`、`{{note}}`、`{{path}}`、`{{title}}`、`{{date}}`。
- 首次打开库时，写入几份默认命令文件，替代 `SlashItem.all` 和面板里写死的 agent 命令。
- frontmatter 解析放进 PlumeCore，只支持简单的 `key: value`，不引入 YAML 库。

### 3.3 自动化 `.plume/automations/*.md`

```markdown
---
title: 收件箱归类
on: note.saved
match: 收件箱.md
agent: claude
model: haiku
debounce: 120           # 秒；保存停止 2 分钟后才运行
---
把收件箱里新增的条目归到合适的笔记，用 propose_edit 提交，每条都写明理由。
```

- 以后台会话运行（`SessionSource.automation`），显示在会话列表里，可以随时停止。
- 所有写入都必须走审阅，无论当前审阅模式是什么。
- 护栏：
  - 自动化自己产生的事件不会再次触发自己
  - 每条自动化同一时间只跑一个实例
  - 每日运行次数上限，默认 20
  - 设置里有全局总开关
  - 首次加载一条新的自动化时，需要用户确认启用，因为它可能随 git 拉取进来

### 3.4 AGENTS.md 学习回路

- 内置命令"从最近的审阅总结写作规则"：读取 `.plume/proposals/` 的历史和拒绝原因，通过 `propose_edit` 提议修改 AGENTS.md。
- 规则变更本身也要经过审阅。

### 3.5 `.plume/` 与 git

- 应提交：`commands/`、`automations/`
- 应忽略：`proposals/`、`index/`
- 首次创建 `.plume/` 时，写入 `.plume/.gitignore`。

### 阶段三验收

- [ ] 新建 `.plume/commands/polish.md` 后，不用重启 app，在斜杠菜单输入 `/polish` 就能触发。
- [ ] 往收件箱追加三条内容，两分钟后出现一份带理由的归类提案。连续保存不会重复触发。
- [ ] `plume watch --events note.saved` 在用户保存时实时输出，并能区分来源是用户还是 agent。
- [ ] 单元测试：frontmatter 解析、模板渲染、自动化匹配与去抖、防自触发。

---

## 4. 实施顺序与规模估计

| 步骤 | 内容 | 主要文件 | 规模 |
|---|---|---|---|
| 1 | JSONValue、RPC、CommandSpec 及测试 | PlumeCore 新文件 | 小 |
| 2 | VaultIndex 及测试 | PlumeCore/VaultIndex.swift | 中 |
| 3 | 选区上提 | Editor.swift、AppModel.swift | 小 |
| 4 | CommandRegistry，面板改造 | Commands.swift、CommandPalette.swift | 中 |
| 5 | AgentServer | AgentServer.swift、PlumeApp.swift | 中 |
| 6 | PlumeCLI 目标、打包 | Package.swift、PlumeCLI/、bundle.sh | 中 |
| 7 | 环境变量注入、上下文改写、AGENTS 模板 | CLI.swift、AppModel.swift | 小 |
| 8 | 安装按钮、e2e 脚本 | SettingsView.swift、scripts/e2e.sh | 小 |
| — | **阶段一完成** | | |
| 9 | MCP 协议与 `plume mcp`，实测两个 CLI 的挂载参数 | PlumeCore/MCP.swift、PlumeCLI | 中 |
| 10 | propose_edit、提案持久化、ReviewView 显示理由 | AppModel.swift、ReviewView.swift | 大 |
| 11 | ask_user 卡片 | AgentInspector.swift | 中 |
| 12 | 拒绝原因回传 | ReviewView.swift、AppModel.swift | 小 |
| — | **阶段二完成** | | |
| 13 | subscribe、`plume watch` | AgentServer.swift、PlumeCLI | 中 |
| 14 | 命令文件、frontmatter、模板 | PlumeCore、Commands.swift | 中 |
| 15 | 自动化引擎与护栏 | Automations.swift | 大 |
| 16 | AGENTS.md 学习回路 | 命令文件 | 小 |
| — | **阶段三完成** | | |

每一步单独提交，每步结束后跑 `swift test` 和 e2e 脚本。

## 5. 决策（2026-09-26 已全部确认，均按建议执行）

- **D1 命令名和安装位置**：`plume`，软链到 `~/.local/bin`。*建议：就这样。*
- **D2 提案存放位置**：
  - 选项 a：持久化到 `.plume/proposals/`，重启后还在
  - 选项 b：只在内存里，重启就丢

  *建议 a。* 提案可能要过一阵才审，丢了体验很差；这些文件也是学习回路的数据来源。
- **D3 拒绝原因是否自动发回**：*建议手动点按钮*，避免意外产生费用。以后可以加一个"自动发回"的设置项。
- **D4 老的"先写后审"路径是否保留**：*建议保留*，兼容不认识 Plume 的 agent。等提案路径成熟后，AGENTS.md 里改为推荐用 `propose_edit`。
- **D5 自动化的默认每日上限**：*建议 20 次。*

## 6. 风险

- **R1 CLI 参数随版本变动。** `--mcp-config`、`--allowedTools`、Codex 的 `mcp_servers` 配置都要在步骤 9 实测。参数拼装集中在 `AgentProcess.arguments`，已有单元测试覆盖，变了只需改一处。
- **R2 MCP 工具调用阻塞超时。** `ask_user` 和 `propose_edit wait` 可能超出 CLI 默认的工具超时。对策：调大超时，并且让超时返回明确的状态，而不是报错。
- **R3 大库的索引性能。** 先实测上千篇笔记时的扫描耗时；超过 300ms 再做 `.plume/index` 缓存（按 mtime 失效）。
- **R4 socket 安全。** 只有本用户可读写（0600）。任何本地进程都能调用 `read` 和 `ui`；`write` 类命令一律进审阅，风险可控。以后如有需要，可以加每次启动随机生成的 token。
- **R5 自动化失控。** 靠 3.3 的护栏兜底，并且所有自动化会话都要在界面上可见、可停止。

## 7. 实施记录

### 阶段一（2026-09-26 完成，1.9 暂缓）

**新增文件**
- PlumeCore：
  - `JSONValue.swift`、`RPC.swift`、`UnixSocket.swift`：协议和 socket 基础设施
  - `CommandSpec.swift`：内置命令表，以及参数解析和校验
  - `VaultIndex.swift`、`VaultQueries.swift`：索引，app 与离线 CLI 共用
  - `EditorContext.swift`：由光标和选区算出行号、标题链
  - `Render.swift`：文本输出，阶段二的 MCP 也会复用
  - `AgentArguments.swift`：拼装 agent 启动参数，从 app 里挪过来以便测试
- App：
  - `Commands.swift`：命令注册表，⌘K 由它生成
  - `AgentServer.swift`：socket 服务
  - `PlumeTool.swift`：`plume` 命令的软链与安装
- CLI：`Sources/PlumeCLI/main.swift`
- 脚本：`scripts/e2e.sh`

**验证**
- `swift test`：50 个测试全部通过，其中本阶段新增 22 个。
- `scripts/e2e.sh`：16 项全部通过。
- 真实的 Claude（haiku）会主动调用 `plume context`，并正确回答光标所在标题和反链。
- 真实的 Codex 在下文所述参数下，能在沙箱内调用 `plume context`；访问外网仍被拦截。

**和计划不一样的地方**
- **Claude 需要显式放行 `plume`。** `-p` 模式配合 `--permission-mode acceptEdits` 会拒绝所有 shell 命令，所以启动参数加了 `--allowedTools "Bash(plume:*)"`。
- **Codex 的 workspace-write 沙箱会拦截 Unix socket**，`connect` 返回 EPERM。
  - 解决办法：打开 Codex 自带的网络代理，并且只把 Plume 的 socket 放进白名单（`features.network_proxy.unix_sockets`）。
  - 外网请求要经过代理的域名白名单，而白名单默认为空，所以外网依然不通。实测访问 example.com 返回 403。
  - 这是 Codex 0.157 的实验性配置，后续版本可能变动；风险 R1 已经在这里实测过一次。
  - `plume` 能识别被沙箱拦截的情况：只读命令自动改为读文件，其余命令会报出准确原因。
- **CLI 能识别自己在哪个库里。** 请求里带上调用者所在的库路径；如果和 app 打开的库不同，只读命令改为在本地执行，而不会返回错误库的数据。
- **调试开关。** DEBUG 构建支持用环境变量 `PLUME_SOCK` 指定 socket 路径，e2e 脚本靠它避免和正在使用的 Plume 冲突。

- **Codex 的放行参数限定版本。** 只在确认 Codex 不低于 0.157.0 时才加这组参数，版本未知也不加。原因是：旧版本可能忽略代理设置，却照样执行 `network_access=true`，结果等于把整个网络打开。旧版本的 Codex 里，`plume` 的只读命令照常可用，`context` 等命令会报"被沙箱拦截"。

**发布前还要处理**
- 用 Developer ID 签名并公证 app，同时签名 `Helpers/plume`。现在 `bundle.sh` 用的是临时签名（ad-hoc），别人从网上下载后会被 Gatekeeper 拦下。
- "安装 plume 命令"会装到 `~/.local/bin`，但这个目录不一定在用户的 PATH 里。安装后要检测一下，不在时提示用户怎么加。
- 在终端里自己启动的 Codex 不带这组参数。可以在设置里提供"写入 ~/.codex/config.toml"的选项，由用户主动开启。

**尚未完成**
- 1.9 `plume attach`（认领终端会话）暂缓。现有的终端会话识别仍在使用，等阶段二做提案归属时一并处理。
- 设置页的"plume 命令"一节还没有截图核对外观。

### 阶段二、三（2026-09-26 完成）

**新增文件**
- PlumeCore：
  - `Proposal.swift`：修改提案的模型和存储，按 edits 定位替换，把理由对齐到每处改动，生成发回给 agent 的意见
  - `MCP.swift`：MCP 协议处理
  - `VaultConfig.swift`：frontmatter、模板、glob 匹配、自定义命令和自动化文件的解析
- App：
  - `Workflow.swift`：提案、审阅收尾、提问、发回意见
  - `Automations.swift`：事件流、自定义命令、自动化引擎
- CLI：`plume mcp`、`plume watch`，以及 `--content -` 从标准输入读取内容

**验证**
- `swift test`：66 个测试全部通过。
- `scripts/e2e.sh`：36 项全部通过。它用 DEBUG 构建才有的 `debug.*` 命令，代替用户点"接受 / 拒绝 / 回答"。
- 真实 Claude（haiku）端到端验证了：
  - `propose_edit` 带 `wait=true`：拒绝后，Claude 拿到了拒绝原因；
  - 不等待的提案：拒绝后点"发回"，同一会话里 Claude 按原因重新提交，接受后写入；
  - `ask_user`：提问、得到回答、再根据回答提交提案；
  - 自动化：未启用时不运行；启用后在静默期结束时运行；直接写文件被拒绝，只能提交提案；不会被自己的提案再次触发；
  - "从审阅总结写作规则"：通过 `plume reviews` 读到审阅记录，把规则作为提案提交到 AGENTS.md。

**和计划不一样的地方**
- **每篇笔记同时只能有一份待审阅改动。** 已有待审阅改动时，新提案会被拒绝（错误码 1006），并提示 agent 等用户处理完。这比把多份提案合并起来简单，也更不容易出错。
- **提案作废。** 提案提交之后，如果文件被别处改过，接受时会判定作废，不会覆盖别人的改动。等待中的 agent 会收到 `stale` 状态。
- **自动化只读运行，而不只是"要求走审阅"。** Claude 用默认权限模式，只放行 plume 工具；Codex 用只读沙箱。它唯一能改笔记的途径就是提交提案。
- **自动化的启用和文件内容绑定。** 文件内容一变（包括随 git 拉取进来的改动），就需要重新启用。
- **直接写文件的审阅也会存档。** agent 直接改文件后经过的审阅，同样记进 `.plume/proposals/`，所以 `plume reviews` 能看到全部历史。
- **CLI 能用 app 自己注册的命令。** 遇到不认识的命令，CLI 会向 app 要命令定义；DEBUG 命令和以后新增的命令因此都能直接用。
- **Codex 挂载 MCP 需要放行工具。** `codex exec` 从不向用户申请批准，需要批准的工具会被直接拒绝。所以加了 `default_tools_approval_mode="approve"`。这些工具本身不绕过用户：提案仍要审阅，提问仍要回答。
- **Claude 的工具调用超时。** 提问可能要等很久，所以启动时设置 `MCP_TOOL_TIMEOUT=900000`（15 分钟），并把 `ask` 的默认等待时间定为 600 秒。
- **终端 agent 的归属。** 不做单独的 `plume attach` 了：请求里带的 pid 属于哪个终端会话的进程树，就归到哪个会话。

**尚未验证**
- Codex 通过 MCP 调用 `propose_edit`：放行参数已按官方文档加上，但测试时 Codex 账号额度用完了（到 9 月 27 日 15:36），没能实测。补上放行参数之前，Codex 调用只读工具 `context` 是成功的。
- Agent 面板里的提问卡片和"发回意见"卡片：截图工具画不出这个面板（原有的 banner 场景截出来也是空白），需要在真机上看。
- `selection.changed` 事件没有测试过（单元测试和真机都没有）。
