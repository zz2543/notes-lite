# 18: `.notes/` 搬迁与空间库

**What to build:** 首次打开含 `.留白/` 的笔记库时自动搬入 `.notes/`；侧栏可在“资料库 | 空间”之间切换，新建、排序空间并生成编写说明与提示词。

**Blocked by:** 01, 03

**Status:** ready-for-agent

**Progress:** in-progress

- [x] 首次打开自动搬迁空间主页、编写说明与操作记录；中途失败保留原目录并提示；用户 Markdown 不变
- [x] “资料库 | 空间”分段切换，侧栏内容横向平移
- [x] 新建、改名、删除、拖动排序空间；新建时生成提示词（含范围内记录表位置与表头）
- [x] 编写说明安装到 `.notes/空间/`，随版本覆盖
- [x] 核心库测试覆盖搬迁各情形与空间库

## Comments

### 2026-10-20 · implementer

Branch `ticket/18-notes-folder-and-spaces` (merged with `feat/notes-desktop` after the work).

- **Core** (`src/core`): `spaces.ts` (`spaceLibrary`: spaces/space/create/update/delete/reorder/installGuide/recordTables/prompt;
  scope helpers `scopeFromMeta`, `scopeMeta`, `scopeContains`, `scopeLabel`; `SpaceError` codes), `recordTables.ts`
  (table parsing outside code fences, `路径#标题` addressing; ticket 19 adds typed read/write here), `spaceGuide.ts`
  (old guide ported, `.留白/` → `.notes/`, brand-neutral wording, version 2), `migration.ts` (`migrateLegacyFolder`).
- **Migration:** `.留白/` is copied into a `.notes.migrating/` staging folder (over a copy of any existing `.notes/`, whose
  files win), the operation log's `".留白/…"` paths are rewritten, then staging is swapped in and `.留白/` removed. Any
  failure removes staging and leaves `.留白/` and `.notes/` untouched; the message reaches the page as `LibraryInfo.notice`
  (toast). A leftover staging folder from an interrupted run is cleared. Runs on every open (launch and 打开笔记库).
- **Guide:** installed on create/prompt, and on open whenever the library has spaces, overwritten when it differs.
- **UI:** `Spaces.tsx` — `SideSwitch` (tablist “侧栏”, pill slides with 滑移), `SidePages` (content slides 60px × amplitude
  with fade, left into 空间, right back; `travel.sideSwitch` in motion.ts), `SpacePanel` (list “空间”, Motion `Reorder` drag,
  context menu 编辑空间… / 复制给 agent 的提示词 / 删除空间… with confirm; follows `.notes/空间` changes from the watcher),
  `SpaceDialog` (emoji, name, 整个笔记库 or folder checkboxes). Creating copies the prompt to the clipboard (main process).
- Decisions: deleting a space trashes the file (system trash); names follow the same macOS/Windows rules as notes;
  meta names stay `lb-scope`/`lb-icon` (new prefix is ticket 20). Selecting a space only highlights it — opening its page
  and scoped tree is ticket 19. Reference sync on rename/move (`syncPaths`) is ticket 21.
- Evidence: `npx vitest run tests/core/spaces.test.ts tests/core/migration.test.ts` (10 + 5, incl. ported SpaceLibraryTests
  except syncPaths); `tests/e2e/spaces.spec.ts` (4: migration + list, failed migration notice, create/prompt/drag/edit/
  delete, external space file appears). Full: typecheck, `npm test` 87 passed, `npm run test:e2e` 35 passed. Two earlier
  full e2e runs each had one different timing test fail under machine load (load avg ~8); each passed in isolation and
  on the third full run.
