# 12: 表格与公式

**What to build:** 笔记中的 Markdown 表格与行内、独立公式正确显示。

**Blocked by:** 08

**Status:** ready-for-agent

**Progress:** completed

- [x] 表格原地排版
- [x] 行内与独立公式用随应用分发的 KaTeX 渲染，附许可文件
- [x] 编辑时可看到源码，离开后恢复显示
- [x] 移植旧版表格与公式测试

## Comments

### 2026-10-21 实施记录（Notion AI）

分支 `notion/all`，提交 `[notion] 12: …`。

**做了什么**

- 解析（`src/shared/markdown.ts`）：`displayMath`（单行 `$$…$$`，最多缩进 3 格，与旧版一致）、`parseTable`（对齐行、单元格去空白；行内代码、`[[页|别名]]`、`\|` 里的竖线不拆格；短行补空格，超出表头列数的格子不显示，与旧版一致）、`renderedBlocks`（表格需表头行 + 对齐行；闭合的 `$$` 块；单行公式；跳过代码块、front matter 和未闭合的 `$$` 之后的内容）。
- 显示（`src/renderer/src/blockView.ts`）：光标不在块内时，表格画成表格（表头、对齐、单元格里的粗体/斜体/代码/公式），独立公式由 KaTeX 画出并居中；光标进入（点击或 ↑↓）即显示 Markdown，独立公式编辑时下方实时预览；行内公式在所在行编辑时显示 TeX。点击单元格时光标落在该格文字末尾。只加装饰，不改文件内容。编辑器没有焦点时全部画出，与其他语法标记的规则一致。
- KaTeX（`src/renderer/src/tex.ts`）：`katex` 0.18.9（与旧版同版本）打进应用，首次遇到公式时才加载（独立 chunk，不影响启动）；带 mhchem（`\ce`），参数与旧版一致（`throwOnError:false`、`trust:false`、`strict:"ignore"`）；加载失败时公式保留 TeX 并可重试。
- 许可：`resources/licenses/katex/` 下有 KaTeX 的 MIT 许可（逐字复制）、mhchem 的 Apache-2.0 全文和 README（列出版权）；随 `extraResources` 打包。
- 样式：变量在 `tokens.css`（`--table-*`、`--math-size`），取值写进 `docs/design-system.md`“正文排版”表。

**测试**

- 单元：`tests/core/renderSyntax.test.ts` 移植旧版 `testDisplayMathLine`、`testTable`、`testTableWithoutTrailingPipe`，另加缩进、列数不齐、未闭合 `$$` 之后的表格、按行读取；`tests/core/katex-license.test.ts`。
- e2e：`tests/e2e/tables-math.spec.ts`（表格：对齐、单元格粗体、emoji、点击单元格编辑、↑↓ 进入；公式：行内/块/单行、KaTeX 不认识的命令显示为错误色、点击进入、预览随输入更新、↑ 进入；源码视图原样显示，切回时光标在表格里则表格保持展开）。文件内容逐字比对。
- 本地：typecheck 通过；vitest 全部通过（除沙箱里 4 个已知的 chmod 相关失败，基线也一样）；`npm run build` 通过；e2e 全部通过（除沙箱里 6 个已知的环境失败，基线也一样）。没有 PR，CI 未自动运行。

**代码审查**（两个子代理：规范、需求）已处理：单元格含 emoji 时报错；视图切换时焦点状态丢失导致表格先画后展开（焦点状态移出 compartment）；每次按键复制全文、光标移动重建所有块；块 widget 估高；点横向滚动条误入编辑；KaTeX 加载失败兜底；行内样式表两处重复；尺寸放进 tokens；单元格内公式加载后重新测量；mhchem 许可；单行 `$$` 缩进规则；补测试。

**未做 / 待定**

- KaTeX 的 `KaTeX_Size3` 字体小于 Vite 默认 4KB 内联阈值，被内联成 `data:` 字体，CSP（`default-src 'self'`）会拦下并在控制台报一条错误；浏览器随即改用同名 `.woff`，实测字体正常加载、显示无误。另外 KaTeX 的 `.woff`/`.ttf` 备用字体也被打进了包（约 876 KB）。要去掉这条报错和多余字体，需要改 CSP（加 `font-src 'self' data:`）或 Vite 配置（扩大 `woff2Only` 范围、调内联阈值），属于构建配置改动，按约定先问用户。
- 表格单元格里的删除线、高亮、链接、`[[页|别名]]`、标签暂不排版（正文目前也不排版链接），由任务 13 一并处理。
- 缩进的表格（行首有空格）不识别为表格，与现有 `blockType` 的规则一致；旧版允许最多 3 个空格。
- 深色模式的颜色变量已加，未单独做深色截图验证；KaTeX 的错误色固定为 `#cc0000`。
