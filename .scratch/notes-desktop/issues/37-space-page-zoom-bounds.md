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
