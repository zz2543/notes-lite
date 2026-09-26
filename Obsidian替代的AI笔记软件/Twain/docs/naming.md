# 产品命名：共笔 · Twain

> 状态：已定名，代码已改名 · 2026-09-26。旧名 Plume 的迁移见第 4 节。
> 商标与重名（App Store、商标库、域名、GitHub）尚未核查。

## 1. 名字

| | 名字 | 含义 |
|---|---|---|
| 中文 | **共笔** | 两人执一支笔、合写一份文本。原指同学分工合写、共享的课堂笔记，本身就带"笔记"和"合写"两层意思 |
| 英文 | **Twain** | 古英语的"二"（*never the twain shall meet*），又让人想到作家马克·吐温——两个人，一位作者 |

两个名字讲的是同一件事：**人和 agent 是同一份 Markdown 的两位作者，人掌舵，agent 执笔，每一处改动人都能看见、审阅、撤回。** 这就是"AI 原生"在本产品里的具体含义（见 [agent-api-plan.md](agent-api-plan.md) 的目标一节）。名字里不出现"AI"，AI 的卖点交给副标题。

## 2. 写法

- 并列全称：`共笔 · Twain`（中点前后各一个空格）。用于 app 关于页、官网标题、宣传片片头片尾。
- 中文语境正文只写「共笔」，英文语境只写「Twain」。同一段里不混用。
- 命令、路径、标识符一律小写 `twain`。
- 不写：`共笔AI`、`Twain AI`、`TWAIN`（全大写是扫描仪驱动标准，会混淆）、`Twain Notes`。

## 3. 副标题

- 中文：**你掌舵，AI 执笔。**
- 英文：**Two minds, one manuscript.**
- 需要说明产品类别时：「agent 原生的 Markdown 笔记」/ *An agent-native Markdown notebook.*

## 4. 从 Plume 改名（已完成）

代码里的 Plume 已全部改为 Twain（标识符、命令、路径）或「共笔」（中文界面文案、给 agent 的中文提示词）。

| 位置 | 旧 | 新 |
|---|---|---|
| Swift 包与目录 | `Plume` / `PlumeCore` / `PlumeCLI` / `PlumeCoreTests` | `Twain` / `TwainCore` / `TwainCLI` / `TwainCoreTests` |
| App | `Plume.app`，`app.plume.notes` | `Twain.app`，`app.twain.notes`；中文系统显示「共笔」（`scripts/bundle.sh` 写入 `zh-Hans.lproj`） |
| 命令 | `plume`（产物 `plume-cli`） | `twain`（产物 `twain-cli`） |
| 库目录 | `.plume/` | `.twain/` |
| Application Support | `Plume/`（`run/plume.sock`、`bin/`） | `Twain/`（`run/twain.sock`、`bin/`） |
| 环境变量 | `PLUME_*` | `TWAIN_*` |
| MCP | 服务名 `plume`，Claude 工具前缀 `mcp__plume` | `twain`，`mcp__twain` |

**老用户升级时自动迁移**（`Sources/Twain/LegacyPlume.swift`，不再有人从 Plume 升级时整个删掉）：

- 偏好设置：首次启动时从 `app.plume.notes` 复制到新 bundle id，不覆盖已有的值。
- 命令：用户装过的 `~/.local/bin/plume` 换成 `~/.local/bin/twain`；旧的 `Application Support/Plume/` 只含命令链接和 socket，直接删除。
- 库：打开库时把 `.plume/` 整个移动为 `.twain/`，并把 `AGENTS.md`、`.twain/commands/`、`.twain/automations/` 里失效的 `plume` 命令改为 `twain`、正文里的 Plume 改为「共笔」。

**仍用旧名、未改的**：宣传材料 `promo/`（含已出片的宣传片）、`Plume.dc.html`、`deliverables/plume-original-film/`。宣传片需要重新出片头片尾。

**还没核查**：商标与重名。
