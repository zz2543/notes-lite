# 共笔 · Twain 功能介绍片

68 秒，1920×1080，30 fps，H.264 + AAC，原创合成配乐，无旁白。画面中的应用界面都是真实截图，由共笔的调试场景（`TWAIN_SCENARIO`）在真实窗口里截取；笔记内容是演示数据。终端里显示的是 `twain` 命令对运行中的 app 的真实输出，只把库路径缩写成了 `~/我的笔记`。

| 时间 | 场景 | 画面 |
| --- | --- | --- |
| 0–5 秒 | 片头：共笔 · Twain / 你掌舵，AI 执笔。 | 标题卡 |
| 5–11 秒 | 01 本地优先：笔记就是 Markdown 文件夹 | 侧栏文件树 |
| 11–17 秒 | 02 写作：实时渲染、斜杠菜单、打字机模式 | 斜杠菜单 |
| 17–24 秒 | 03 Agent：Claude Code 与 Codex 在侧栏 | agent 面板、Markdown 回复 |
| 24–32 秒 | 04 审阅：逐段接受或还原，git 快照 | diff 审阅 |
| 31–40 秒 | 05 人机闭环：带理由的提案、拒绝原因、提问 | 提案审阅、提问卡片 |
| 40–50 秒 | 06 开放接口：`twain` CLI 与 MCP | 终端：open / context / search |
| 49–56 秒 | 07 工作流：`.twain/commands` 与自动化 | 命令文件、自动化文件 |
| 56–62 秒 | 08 细节：⌘K、专注模式、深色外观 | 三图拼贴 |
| 61–68 秒 | 片尾 | 标题卡 |

## 重新渲染

需要 Node（playwright-core 1.63 及其 headless Chromium）、Python 3 + NumPy、FFmpeg。

```sh
cd source
npm i playwright-core@1.63
python3 music.py score.wav
node render.js video silent.mp4
ffmpeg -i silent.mp4 -i score.wav -map 0:v -map 1:a -c:v copy -af loudnorm=I=-18:TP=-1.5 -c:a aac -b:a 192k -shortest -movflags +faststart out.mp4
```
