# 给 Notion AI 的接手提示词

把下面分隔线之间的内容整段粘给 Notion AI（或 Notion 里接了 GitHub 写权限的自定义 Agent）。

---

你接手继续开发一个跨平台 Markdown 笔记桌面应用，代号 notes-desktop（Electron + React + CodeMirror + TypeScript）。你看不到维护者的电脑，一切都通过 GitHub 仓库 `zz2543/notes-lite` 完成。

## 0. 先确认你的能力

开始前先说清楚你能做到哪些：读仓库文件、建分支、提交、开 PR、读 GitHub Actions 结果、在你自己的环境里运行命令（npm）。如果你**不能往 GitHub 写入**（建分支或开 PR），立即停下来告诉我，不要把代码贴在聊天里假装完成。

## 1. 开工前必读（都在 `feat/notes-desktop` 分支上）

1. `AGENTS.md`，以及它指向的 `docs/agents/issue-tracker.md`、`docs/agents/triage-labels.md`、`docs/agents/domain.md`。
2. 工作流程：`docs/agents/skills/README.md`，然后是 `docs/agents/skills/mp-4-implement/SKILL.md`、`tdd/SKILL.md`（含 `tests.md`、`mocking.md`）、`code-review/SKILL.md`。你没有 Skill 工具：“call the Skill tool with X”就是“读 `docs/agents/skills/X/SKILL.md` 并照做”。
3. 任务：`.scratch/notes-desktop/README.md`（任务索引、阻塞关系、进度、优先顺序），以及你要做的那张 `.scratch/notes-desktop/issues/<NN>-*.md`，包括它的 Comments 和阻塞项任务里的实施记录。
4. 领域文档：`notes-desktop/docs/GLOSSARY.md`、`notes-desktop/docs/adr/`、`notes-desktop/docs/specs/`（入口 `spec.md`，助手栏看 `assistant-spec.md`，界面与动效看 `ui-motion-spec.md`），`notes-desktop/docs/design-system.md`，`notes-desktop/README.md`。
5. CI：`.github/workflows/notes-desktop.yml`。

## 2. 做哪张任务

按 `.scratch/notes-desktop/README.md` 的顺序，从阻塞项全部有完成记录（`**Progress:** completed`）的任务里挑：

- 先做助手栏：29（审查卡片与“直接保留”模式），再 30（其余 Agent 与对话历史）。
- 再做 12、13，然后 22，然后 23（动效审查，覆盖助手栏），最后 25。
- **10、11、24 不要做**，维护者要在最后亲自决定。
- 启动速度不要优化，回退只记录在任务评论里。
- 一次只做一张任务。上一张的 PR 没被合并前，不开始依赖它的任务；不依赖它的下一张可以开始，但同时最多两个未合并的 PR。

开始一张任务时，先告诉我它的编号和标题。

## 3. 代码必须和现有代码分开，方便回退

- **绝不直接推送到 `feat/notes-desktop` 或 `main`，绝不合并、不 force push、不删除别人的分支、不改仓库设置。**
- 每张任务从 `feat/notes-desktop` 的最新提交新建一个分支：`notion/<NN>-<英文短名>`，例如 `notion/29-turn-review`。所有改动只提交到这个分支。
- 任务做完后开一个 **draft PR**，目标分支是 `feat/notes-desktop`，标题 `[notion] <NN>: <任务标题>`。由维护者审查后决定合并或关闭。PR 被关闭就等于这次实现作废，分支可以直接丢弃。
- 一个 PR 只做一张任务，不夹带无关重构、格式化或依赖升级。新增 npm 依赖必须在 PR 描述里单独说明理由。
- 如果 `feat/notes-desktop` 在你工作期间前进了，把它合并进你的分支再标记 PR 就绪，不要 rebase 已推送的提交。

## 4. 实现流程（mp-4-implement）

1. 读完任务和规格后，在 PR 描述的草稿里列出：要做的行为、要测的接缝（接缝 A 核心库 = Vitest，`notes-desktop/tests/`；接缝 B 运行中的应用 = Playwright，`notes-desktop/tests/e2e/`，助手相关用 `tests/support/` 里的假 Agent）。接缝已经与维护者确认，不必再问。
2. 按 tdd 的红 → 绿循环一片一片做：一个失败的测试 → 刚好让它通过的实现 → 下一片。测试通过公开接口验证行为，不测内部实现，不写恒真断言。
3. 验证：
   - 如果你的环境能运行命令：在 `notes-desktop/` 下 `npm ci`，开发中常跑 `npm run typecheck` 和单个测试文件（`npx vitest run <文件>`、`npx playwright test <文件>`，e2e 前先 `npm run build`），任务结束时跑一次全量 `npm test` 和 `npm run test:e2e`。
   - 如果不能运行命令：只能靠 CI。开 PR 会自动在 macOS 和 Windows 上跑 typecheck、单元测试、e2e 和打包。为了省 CI，**等整张任务写完再开 PR**，之后修复尽量一次推送。CI 不通过就继续修，直到两个平台都通过；同一个失败修三次仍不过，就停下来在 PR 里写明情况再问我。
   - 绝不为了让 CI 变绿而删除、跳过或放宽已有测试。偶发失败要在 PR 里写明是哪条、重跑结果如何。
4. 收尾审查（code-review）：以 `feat/notes-desktop` 为固定点，对你的分支做两遍审查，一遍“规范”（仓库文档里的约定 + skill 里的代码坏味道清单），一遍“规格”（任务验收标准与相关规格逐条核对），两份结论分开写进 PR 描述。审查发现的问题在同一个 PR 里修掉。
5. 更新任务记录（随 PR 一起提交，PR 不合并就等于没完成）：
   - 任务文件里勾选已满足的验收标准，`**Progress:**` 写 `completed`；
   - 在任务的 `## Comments` 末尾追加 `### <日期> 实施记录（Notion AI）`：分支名、做了什么、关键设计决定、验证证据（命令与结果，或 CI 运行链接）、留给后续的事。只追加，不改动已有内容；
   - 更新 `.scratch/notes-desktop/README.md` 的进度那一行。

## 5. 代码与提交约定

- 沿用周围代码的命名、注释密度和写法；用术语表里的词，不用它排除的近义词。与 ADR 冲突时在 PR 里明确指出，不要悄悄绕过。
- 提交信息沿用仓库风格：英文、`feat(notes-desktop): ...` / `fix(notes-desktop): ...` / `test(notes-desktop): ...` / `docs(scratch): ...`，每个提交能单独通过 typecheck。
- 任务文件、规格、评论用中文；界面文案以规格为准。
- 不提交构建产物（`dist/`、`out/`、`node_modules/`、安装包）。
- 不修改 `NotesLite/`（旧版，只修严重 bug）和 `Obsidian替代的AI笔记软件/`（原产品）。

## 6. 什么时候停下来问我

- 规格或任务描述有歧义、互相矛盾，或与 ADR 冲突；
- 需要真实的模型服务、账号、密钥或付费资源（自动化测试里一律用假 Agent，不调用真实模型）；
- 需要改 CI、构建配置或仓库设置；
- CI 反复失败无法解决。

其余时候不必问，直接按上面的流程做。每完成一张任务，回复我：任务编号与标题、PR 链接、CI 结果、需要我重点看的地方。

---

## 给维护者：回退与合并

- 基线标签 `notion-baseline` 指向交接时 `feat/notes-desktop` 的提交。
- 不想要的 PR 直接关闭，不需要回退任何东西。
- 已合并的 PR 想撤掉：在 GitHub 上对该 PR 点 Revert，或本地 `git revert -m 1 <合并提交>`。
- 想整体回到交接前：从新到旧依次 revert 各个 `[notion]` 合并提交；或从 `notion-baseline` 新开分支，只挑想要的 PR 重新合并。
- 建议在 GitHub 的仓库设置里给 `feat/notes-desktop` 和 `main` 加分支保护（要求 PR、禁止 force push），让“不直接推送”不只靠提示词约束。
