# 共笔 Twain：中文配音宣传片

Remotion 工程。1920 × 1080，16:9，30 fps，96.30 秒。
普通话女声、按旁白同步的中文字幕、原创轻量配乐，以及软件真实界面的动画展示。

## 播放和编辑

```sh
npm run dev
```

选择 `TwainPromo` 查看整片，`Scenes` 下可以独立查看八个场景。
当前预览地址：http://localhost:3410/TwainPromo。

## 内容

| 场景       | 介绍                                 |
| ---------- | ------------------------------------ |
| 共笔       | 你掌舵，AI 执笔                      |
| 本地写作   | 本地 Markdown、实时排版、斜杠菜单    |
| AI 协作    | Claude Code 和 Codex、当前笔记上下文 |
| 修改审阅   | 逐段对比、接受修改、还原内容         |
| 资料研究   | 问题、结论、证据、来源和草稿         |
| 可视化空间 | 日记、习惯、数据和图表               |
| 开放工作流 | 自定义命令、自动化、CLI 和 MCP       |
| 片尾       | 记录、思考、行动                     |

## 素材与依据

主界面、研究工作台及空间来自项目 `Twain/docs/screenshots`；写作菜单和审阅来自 `promo/img` 的演示数据截图。审阅旧截图中的 Plume 是共笔前身名称，细节展示保留了原图。片中使用界面截图，不是实时操作录屏。工作流画面是依据现有代码制作的配置与接口示例。

功能已核对 `Vault.swift`、`NoteDetail.swift`、`ReviewView.swift`、`ResearchDesk.swift`、`Spaces.swift`、`Commands.swift`、`Pipelines.swift`、`Sources/TwainCLI/main.swift` 和 `Sources/TwainCore/MCP.swift`。没有把 2026-10-11 产品定义中尚未实现的自适应模式作为已实现功能宣传。

旁白由 Edge TTS 的 `zh-CN-XiaoxiaoNeural` 合成，经过响度归一化。背景配乐由 `scripts/score.mjs` 原创合成，无外部音乐素材。项目素材均已复制到 `public`，预览与导出不需要再次访问语音服务。

## 工程文件

- `src/scenes/`：八个独立场景。
- `src/shared.tsx`：软件配色、字幕、截图局部放大和预览兼容处理。
- `src/timing.json`：每段旁白的实际时长、时间安排及 Caption JSON。
- `narration.txt`、`captions.srt`：旁白脚本和字幕。
- `public/voice/`、`public/score.wav`：中文语音和原创配乐。
- `out/`：用于画面检查的关键帧。
- `verification.json`：音频、时长和关键帧检查结果。

## 检查与导出

```sh
npm run lint
npm run verify
npm run render-video
```

也可在 Studio 中点击 Render 导出 H.264 MP4。当前交付以可播放、可编辑的预览为主。

如需重新生成音频和配乐：`npm run prepare-media`。此步骤需要 `uv`、FFmpeg、网络连接以及 Edge TTS 服务可用；已有语音文件会复用。
