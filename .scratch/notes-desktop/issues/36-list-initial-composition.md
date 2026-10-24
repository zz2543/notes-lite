# 36: 列表首次组合输入位置稳定

**What to build:** 修复用户 2026-10-24 录屏中的问题：在空列表项首次输入中文时，组合文本固定起点、向右增长，而不是向左挤出。上屏、列表源码和在标记内编辑的能力保持原样。

**Blocked by:** 无

**Status:** ready-for-agent

**Progress:** in-progress

- [x] 在真实应用中复现首次拼音输入的左移，并先得到失败测试
- [x] 无序、有序、任务和嵌套列表的组合文本固定起点、向右增长
- [x] 上屏后源码正确，不增加、丢失或重复列表标记
- [ ] 完成类型检查、全量单元及 e2e 验证和双轴审查

## Comments

### 2026-10-24 实施记录（Notion AI）

- 基线：`notion/all`，固定点 `8419ad080418efc763a0054d204778e6dc71c250`；分支：`notion/fix-list-ime`。
- 最小复现：笔记只有 `- 项目`，End → Enter → CDP `Input.imeSetComposition` 输入 q、qi、qing。
- 红灯：`DISPLAY=:99 ELECTRON_DISABLE_SANDBOX=1 npx playwright test tests/e2e/list-composition.spec.ts --reporter=list`；首字起点应为 570px，实际为 559.53125px，断言失败。继续组字起点为 555.140625、534.1875px；滚动位置始终为 0。
- 定向观测：组合文本留在 `.cm-md-hang` 源码标记节点中；其固定宽度和 `justify-content: flex-end` 使组字不断向左增长。CodeMirror 保护正在组字的节点，不能靠随后重画标记纠正。
- 最小修复：列表标记范围改为不包含其末端的半开区间。光标在正文起点（包括空项）时保持不可编辑的标记 widget，组合输入从正文节点开始；光标真正进入标记内时仍显示源码。不改 CSS、动画、Markdown 文件或依赖。
- 接缝：已确认的接缝 B，Playwright 驱动真实 Electron；用 DOM Range 量组合文本的左右边缘，逐次核对起点不动、右端增长，并读取最终保存的 Markdown。
- 复现环境：Linux 虚拟显示、Electron 44.5.1；不能替代 macOS/Windows 真实系统输入法候选窗的人工验收。
- 类型检查通过；精确复现用例从红变绿。`npm test`：294 通过、4 失败、3 跳过（已有跳过未修改）；未修改基线得到相同结果。四项失败是 library 保存拒写、migration 不可读文件、organize 引用拒写、search 不可读目录：本环境 `chmod(0)` 后仍能读取，不具备这些权限断言所需的文件系统行为。
- 首轮相关 e2e：20 通过、2 失败（caret 即时采样、lists 空行坐标），未修改基线单独重跑两项均通过；修复分支正在重跑。全量 e2e 正在运行，结果和双平台 CI 待补，不将 Linux 测试当作双平台验收。
- 规范轴审查：未发现明文违规或需处理的代码异味；只有范围端点判断变化，沿用既有命名与注释，测试经过公共编辑界面并测量实际组字位置。
- 规格轴审查：未发现缺漏或范围扩张；标记末端归入正文，标记内部仍可编辑；分别核对组合文本起点、右端与最终源码，未改动画开关和其他排版规则。
- 已按要求尝试并行启动两路独立子代理，服务返回 `The tool capability failed unexpectedly`；随后单独重试仍失败。以上两轴由同一代理分开审查（遵循仓库 skill README 的降级规则），不是独立子代理结论。
- 不优化启动、不修改 CI 或构建配置；不新增 npm 依赖。
