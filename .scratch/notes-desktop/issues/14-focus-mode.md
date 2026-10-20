# 14: 专注模式

**What to build:** 一键进入只呈现标题与正文的专注模式，卡片以克制的弹簧展开铺满，Esc 返回且保留编辑位置。

**Blocked by:** 02, 03

**Status:** ready-for-agent

**Progress:** completed

- [x] ⌘⇧F / Ctrl+Shift+F 或卡片按钮进入，Esc 或退出按钮返回
- [x] 正文卡片以“专注”弹簧展开（强档回弹 ≤ 0.12），侧栏与列表淡出仅左移 4–6px，背景压暗
- [x] 往返保留内容、光标、选区与阅读位置，转场中可继续操作或反向
- [x] 专注中正常编辑与保存

## Comments

### 2026-10-20 — implemented on `ticket/14-focus-mode`

- `FocusMode.tsx`: `useFocusMode` (⌘⇧F / Ctrl+Shift+F toggles; Esc in the card or with nothing focused leaves, taken before CodeMirror so the selection stays) and `FocusToggle` (进入专注模式 / 退出专注, low-key at the card's head, keeps editor focus). 专注模式 is a layout class on `.app`; the editor is never rebuilt.
- Motion: columns collapse with a negative margin on `--spring-focus` (强 0.46s / 0.12) and translate `--focus-shift` 5px left while fading over the spring's visual duration; `.app::before` dims with `--focus-dim`. Path, tools and foot fade out; title + body stay centred on `--measure`. Reduced motion: only fades.
- 助手栏 stays docked right in 专注模式 (⌘J still works; Esc keeps it open).
- Evidence: `tests/e2e/focus.spec.ts` (6 tests: shortcut/Esc, button round trip keeping selection + scroll, typing through a reversed transition and saving, spring/fade/5px/dimming timings, reduced motion, docked 助手栏); preset limits in `tests/core/motion.test.ts`.
- Commands: `npm run typecheck`, `npm test` (117 passed, 1 skipped), `npm run test:e2e` (67 passed); after merging `feat/notes-desktop` (docs only) typecheck + `focus.spec.ts` green again.


### 2026-10-20 完成

合并进 `feat/notes-desktop` 后 Windows 上一个用固定次数 ↓ 定位第 60 段的用例差一行（字体折行不同），改为按到达为止（提交见 git log）；CI 两平台通过：https://github.com/zz2543/notes-lite/actions/runs/39383413147
