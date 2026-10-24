# 37: 空间主页与卡片在页面缩放后对齐

**What to build:** 修复用户 2026-10-24 截图中的空间面板向外溢出、与页面边界不齐。保持用户页面缩放可用，不通过隐藏或裁掉内容掩盖错位。

**Blocked by:** 无（与 36 独立，均从同一 notion/all 基线开始）

**Status:** ready-for-agent

**Progress:** in-progress

- [x] 真实 Electron 中稳定复现空间原生页面与宿主卡片错位
- [x] 页面缩放 100%、150%、80%、恢复 100% 时四边均对齐
- [x] 只修原生布局边界，不改空间 HTML、组件、数据与权限
- [ ] 全量验证和双平台 CI 完成

## Comments

### 2026-10-24 实施记录（Notion AI）

- 基线：`notion/all` @ `8419ad080418efc763a0054d204778e6dc71c250`；分支：`notion/fix-space-panel-bounds`，不依赖 36。
- 最小场景：一个名为“阅读”的空间，主页只有标题与一张卡片。100% 缩放时正常；150% 时 DOM 卡片左边缘 502 CSS px = 753 窗口 DIP，但 WebContentsView 原生左边缘仍为 502 DIP。相同原因影响 y、宽和高，使页面从卡片溢出。
- 红灯命令：`DISPLAY=:101 ELECTRON_DISABLE_SANDBOX=1 npx playwright test tests/e2e/space-bounds.spec.ts --reporter=list`；修复前断言 `Expected >= 753, Received 502`。
- 已证实原因：`showSpacePage` 的现有契约传入 CSS px，而 `WebContentsView.setBounds` 使用窗口 DIP，旧实现直接取整，没有考虑宿主页缩放。不是显示器物理像素比例，也不是主页自己写的布局问题。
- 修复：只在主进程原生边界乘 `win.webContents.getZoomFactor()`，再对 x、y、width、height 取整。保持 IPC 的 CSS px 契约；不乘 `devicePixelRatio`，避免 Retina/高 DPI 下重复换算。主页自身缩放策略不变。
- 绿灯：同一场景原生边界变为 x=753、y=84、width=432、height=635，与 150% 下的卡片槽一致。回归测试进一步核对 100%→150%→80%→100% 时四条边误差至多 1 DIP（原生整数边界取整），无需任意 sleep。
- 接缝 B：真实 Electron 窗口、真实 DOM 槽与公开的 Electron 原生视图边界，不模拟坐标换算函数。
- `npm run typecheck`、`npm run build` 通过；相关 e2e（space-bounds、space-page、space-shell、space-styles）13/13 通过，含主页读写、沙盒隔离、存储、导航、示例空间和外观。
- `npm test`：294 通过、4 失败、3 已有跳过，与未修改基线一致；4 项是本环境 chmod 不拒绝访问导致的 library/migration/organize/search 权限用例失败。未更改、跳过或放宽旧测试。
- 规范轴：单独审查无明文违规或需处理的代码异味；沿用既有边界和变量命名，没有引入换算抽象、依赖或跨层业务逻辑。
- 规格轴：单独审查无缺漏或范围扩张；四个坐标值均转换，缩小及恢复也验证；未禁止缩放、不裁切内容，不修改主页数据与权限。
- 子代理服务在本轮两路并行启动及单独重试均失败（`The tool capability failed unexpectedly`）；依仓库 skills README，由同一代理分别审查两轴，不冒称独立子代理结论。
- 全量 e2e 与双平台 CI 仍待补充；实现不等于已完成跨平台验收。未改 CI/构建配置、启动速度或旧产品目录，未新增依赖。

### 2026-10-24 全量验证补充（Notion AI）

- 全量 `DISPLAY=:101 ELECTRON_DISABLE_SANDBOX=1 npm run test:e2e`：131 通过、8 失败（139 项），新增空间边界回归通过。失败为 design-system 系统强调色/变量 2 项、editing 权限拒写 2 项、external-changes 删除、interruption 时序、settings 系统强调色、space-refresh 刷新。
- 对同一固定点的干净基线执行全量相同命令：129 通过、9 失败（138 项）；上述 8 项全部在未修改基线中失败，基线另有 caret 即时采样失败。没有新增失败项。所有原有测试保持不变。
- 启动预算沿用既有测试，未做优化。Linux 10000 篇笔记冷启动测量中位数 1036 ms（904/1098/1036）；并行验证环境下的测量仅留作记录，不当作 macOS/Windows 的回归结论。
- 双平台 CI：https://github.com/zz2543/notes-lite/actions/runs/40097467108 。当前 macOS、Windows 的安装、类型检查和核心测试均已通过，e2e/打包仍在运行，不能先称验收完成。

### 2026-10-24 CI 阻塞记录（Notion AI）

- Windows 首轮 CI 已失败：https://github.com/zz2543/notes-lite/actions/runs/40097467108/job/120882611025 。安装、typecheck、核心测试通过，失败发生在 e2e，未进入打包。
- 注释列出既有 assistant-turn 超时/worker teardown、caret 即时采样、design-system --glass（期望 .72，实际 .88）、interruption、lists 两项坐标和 space-page 导航超时。没有修改这些旧断言，不将其失败掩盖为“全量通过”。Mac 同轮仍在运行。
- Linux 的新增边界测试和相关 13 项全部通过；Linux 全量的所有 8 项失败均在干净基线复现。Windows CI 的其他旧路径失败尚不能由本次缩放修复擅自承接，需要另立任务或维护者确认扩大范围。
- 维持 Draft 与 Progress: in-progress；不自行合并、不改 CI 配置、不为 CI 放宽或跳过旧测试。
