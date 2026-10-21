# 29: 审查卡片与“直接保留”模式

**What to build:** 每一轮结束后出现一张审查卡片，默认一键全部保留，也可逐篇撤回；设置中可改为直接保留。

**Blocked by:** 28

**Status:** ready-for-agent

**Progress:** completed（2026-10-21，证据见 Comments；等 CI 与合并）

- [x] 卡片列出本轮改动的笔记及行数变化，“全部保留”为默认操作
- [x] 展开查看差异并撤回单篇；“撤回本轮”整体还原
- [x] 设置中的“直接保留”模式不出现卡片，仍可在操作记录撤销
- [x] 笔记库以外的改动在卡片中标明不可撤销

## Comments

### 2026-10-21 实施记录（Notion AI）

分支 `notion/29-turn-review`（从 `feat/notes-desktop` 408dd0d 拉出）。

- 行数与差异（接缝 A）：`lineDiff` 从操作记录移到 `src/core/lineDiff.ts`，先去掉首尾相同的行再比，超过约 400 万格时按“全删再全加”统计；`snapshots.finish` 给每个文本改动记 `lines: {added, removed}`，新的 `snapshots.diff(turn, path)` 给出逐行差异（附件为 null）。`TurnChange` 移到 `shared/conversation`，页面直接用。
- 一轮的结束：`end` 事件带 `turn`（快照 id）、`entry`（有改动时的操作记录条目）、完整的改动清单与 `outside`。`outside` 来自 Agent 写文件类工具调用（Write/Edit 等）的路径，按工作目录解析后落在笔记库以外的那些。
- 审查（`src/core/assistantTurns.ts`）：有改动（含库外）的一轮结束时 `review: "pending"`，设置为“直接保留”时直接 `kept`。`review()` 处理卡片的三种操作：全部保留；撤回单篇（`snapshots.revert(turn, path)`）；撤回本轮（撤销其操作记录条目，与在操作记录里撤销完全等同；条目已在操作记录撤销过则只把剩下的撤回，不重复撤销）。逐篇撤回到最后一篇时，同样把操作记录条目标为已撤销。之后又被改过的笔记拒绝撤回并说明原因。`diff()` 给卡片展开用。IPC：`reviewTurn`、`turnDiff`。
- 设置：`assistantReview: "review" | "keep"`（默认 review），设置 › 助手新增“写入审查”组，`审查方式` 两档：每轮结束后审查 / 直接保留。
- 卡片（`src/renderer/src/TurnReview.tsx`）：标题“本轮改动了 N 个文件”；每行是 新建/改写/删除 + 路径 + `+a −b`，点开像时间线一样展开逐行差异；右侧“撤回”（已撤回 / 只记大小时间的附件显示“无法撤回”）；库外的写入列为“笔记库以外 … 不可撤销”，没有按钮；底部“撤回本轮”与主按钮“全部保留”。保留后收成一行“已保留本轮改动（N 个文件）。在操作记录中撤销”；撤回后为“已撤回本轮改动。”，有剩下撤不回的则说“已撤回本轮可撤回的改动；N 个文件无法撤回。”。
- 规格没写明、这里做的决定：继续对话即视为上一轮“全部保留”（默认操作，最多点一次）；“直接保留”在每轮结束时读取；只有库外改动的一轮也出卡片，只有“全部保留”。

证据：`npm run typecheck` 通过；`npx vitest run` 195 通过 / 3 跳过 / 4 失败——这 4 项（library “disk refuses the write”、migration “cannot be read halfway”、organize “can't be rewritten”、search “folder can't be read”）在基线 408dd0d 上同样失败，原因是沙箱里 chmod 不生效，与本任务无关。新增核心库用例：snapshots 行数与逐行差异；turns 的 `end` 带 turn/entry/库外写入；assistantTurns 审查 7 项（待审查与全部保留、展开差异与单篇撤回再整轮撤回并与操作记录一致、逐篇撤完即整轮撤销、又被改过时拒绝、操作记录已撤销后再撤回本轮不重复、直接保留、继续对话即保留且无改动不审查）。`npm run build && npx playwright test`（Linux Xvfb）：93 项中 87 通过；失败的 6 项（design-system/settings 的系统强调色两项、editing 拒绝保存两项、external-changes、space-refresh）在基线 408dd0d 上同样失败（沙箱无系统强调色、chmod 与文件监视），以 CI 的 macOS/Windows 为准。新增 `tests/e2e/turn-review.spec.ts` 5 项：卡片行数与全部保留、继续对话即保留、展开差异撤回单篇再撤回本轮且操作记录显示已撤销、直接保留不出卡片仍可在操作记录撤销、库外写入标“不可撤销”且撤回本轮不碰它。`assistant-turn.spec.ts` 中“从回复进入操作记录”一项先点“全部保留”再进入（卡片取代了原来那一行，用例意图不变）。

代码审查（固定基点 `feat/notes-desktop`，规范、规格两路子代理）后的修改：撤回本轮后如实说明撤不回的文件；已保留的文件数不算已撤回的；`..` 开头的库内文件夹不再被当成库外；类型改名 `ReviewState`、新增 `ReviewChoice` 与 `canRevert`，选项改名 `reviewMode()`；术语表加“写入审查”。

留给后续：
- 库外改动只认得写文件类工具调用的路径；用 Bash 等命令改动库外文件认不出来，其余 Agent（任务 30）的适配层也要提供 `writes`。
- 在操作记录里撤销一轮后，对话里的卡片状态不会自己更新（再点卡片上的按钮会得到正确结果，不会重复撤销）。
- 逐篇撤回不会反映在操作记录的文件列表里。
- 操作记录的差异仍用它自己的分行（末尾换行算一行），与卡片的分行不同。
- “全部保留”是视觉上的主按钮，没有抢输入框的焦点。

