# 懂听 GotIt → 共笔

一个接入示例：共笔里没有任何针对懂听的代码。这个脚本只读取懂听自己的数据，通过共笔的本地 HTTP 接口把每期节目的摘要导入库里。

```bash
python3 twain-gotit-sync.py              # 同步一次
python3 twain-gotit-sync.py --watch 60   # 每 60 秒同步一次
```

- 导入位置：`视频总结/`（`--folder` 可改）。每篇加上 frontmatter：`source`、`gotit_id`、`tags`。
- 按 `source_id`（节目 id）去重。同一期再次同步时，内容相同就跳过；内容变了则由共笔提交为**修改提案**，你审阅后才写入，不会覆盖你的修改。
- 令牌：自动读取 `~/Library/Application Support/Twain/http-token`（共笔的“设置 → 开放接口”里也能看到和重置）。

其他 app 接入方法相同：`POST http://127.0.0.1:27182/v1/notes`，请求体为 `{title, content, folder?, source, source_id}`。完整接口见 `docs/plugins.md`。
