import Foundation

/// The spaces Twain ships as starting points — also working examples of the plugin format
/// (docs/plugins.md). `%FOLDER%` becomes the folder the user picks when creating the space.
struct SpaceTemplate: Identifiable {
    let id: String
    let name: String
    let icon: String
    let summary: String
    let folder: String
    /// Plugin files by path inside the plugin folder; manifest.json among them.
    let files: [String: String]
    /// Notes to create in the vault (path relative to the vault, after %FOLDER% substitution).
    var notes: [String: String] = [:]

    static let all: [SpaceTemplate] = [workbench, journal, discipline, bullet, llmwiki, blank]

    static let workbench = SpaceTemplate(
        id: "workbench", name: "工作台", icon: "square.grid.2x2", summary: "整个库的总览：提问、待办、最近的笔记、流水线。模块可以增删排序。",
        folder: "", files: ["manifest.json": """
        {
          "id": "workbench",
          "name": "工作台",
          "icon": "square.grid.2x2",
          "description": "整个库的总览。点右上角「编辑」增删、排序模块，或者直接改这个文件。",
          "space": {
            "folder": "",
            "modules": [
              {"type": "ask", "title": "问库", "placeholder": "问你的笔记一个问题…", "span": 2},
              {"type": "tasks", "title": "未完成的待办", "limit": 8},
              {"type": "query", "title": "最近修改", "sort": "modified", "limit": 8},
              {"type": "pipelines", "title": "流水线", "items": ["write", "inbox", "weekly"]},
              {"type": "stats", "title": "库的概况"}
            ]
          }
        }
        """])

    static let journal = SpaceTemplate(
        id: "journal", name: "日记", icon: "book.closed", summary: "每天一篇，日历一目了然，AI 陪你做周回顾。",
        folder: "日记", files: [
            "manifest.json": """
            {
              "id": "journal",
              "name": "日记",
              "icon": "book.closed",
              "description": "每天一篇。日历上颜色越深，那天写得越多。",
              "space": {
                "folder": "%FOLDER%",
                "entry": {"title": "{{date}}", "template": "templates/day.md"},
                "rules": "rules.md",
                "modules": [
                  {"type": "today", "title": "今天"},
                  {"type": "calendar", "title": "最近 12 周", "days": 84, "span": 2},
                  {"type": "query", "title": "最近的日记", "folder": "%FOLDER%", "sort": "name", "limit": 7},
                  {"type": "tasks", "title": "日记里的待办", "folder": "%FOLDER%", "limit": 8},
                  {"type": "ask", "title": "问问这段时间的自己", "placeholder": "这个月我最常焦虑什么？", "scope": "folder:%FOLDER%"},
                  {"type": "pipelines", "title": "回顾", "items": ["journal-week"]}
                ]
              }
            }
            """,
            "templates/day.md": "# {{date}} {{weekday}}\n\n## 今天做了什么\n- \n\n## 想法\n\n## 明天\n- [ ] \n",
            "rules.md": """
            %FOLDER%/ 下是我的日记，属于私人记录：
            - 不要改写我已经写下的句子；只有我要求时才追加内容。
            - 回顾、总结时引用原句，并注明来自哪一天。
            - 不要对我的情绪下诊断式的结论，用提问代替评判。
            """,
            "pipelines/journal-week.md": """
            ---
            title: 日记周回顾
            agent: claude
            scope: vault
            icon: calendar.badge.clock
            ---
            ## 读本周日记
            gate: none
            用 skim --folder %FOLDER% 找到最近 7 天（截至 {{date}}）的日记，用 read_note 读全文。列出这一周发生的事、反复出现的情绪和念头，每条注明日期。

            ## 写周回顾
            gate: review
            根据上一步写一篇周回顾：这周的主线、做成的事、卡住的地方、值得留意的模式、下周想试的一件小事。
            引用原句要注明日期。用 propose_edit 新建 %FOLDER%/周回顾-{{date}}.md。
            """,
        ])

    static let discipline = SpaceTemplate(
        id: "discipline", name: "自律", icon: "figure.run", summary: "习惯打卡、睡眠和运动数据，从任何地方导入，AI 帮你复盘。",
        folder: "自律", files: [
            "manifest.json": """
            {
              "id": "discipline",
              "name": "自律",
              "icon": "figure.run",
              "description": "数据不用手抄：twain data add、HTTP 接口、或把 CSV 丢进 .twain/inbox/<集合>/ 都能记录。",
              "collections": {
                "sleep": {"label": "睡眠", "fields": {"hours": {"label": "时长", "unit": "小时"}}},
                "workout": {"label": "运动", "fields": {"minutes": {"label": "时长", "unit": "分钟"}}},
                "habits": {"label": "习惯"}
              },
              "space": {
                "folder": "%FOLDER%",
                "entry": {"title": "复盘 {{week}}", "template": "templates/review.md"},
                "rules": "rules.md",
                "modules": [
                  {"type": "habits", "title": "今天的习惯", "collection": "habits", "items": ["早起", "运动", "阅读", "冥想"], "days": 7, "span": 2},
                  {"type": "stat", "title": "近 7 天平均睡眠", "collection": "sleep", "field": "hours", "reduce": "avg", "days": 7, "goal": 7.5},
                  {"type": "stat", "title": "近 7 天运动", "collection": "workout", "field": "minutes", "reduce": "sum", "days": 7, "goal": 150},
                  {"type": "chart", "title": "睡眠", "collection": "sleep", "field": "hours", "reduce": "avg", "days": 30, "kind": "line", "span": 2},
                  {"type": "chart", "title": "运动", "collection": "workout", "field": "minutes", "reduce": "sum", "days": 30, "kind": "bar", "span": 2},
                  {"type": "log", "title": "记一笔", "fields": [
                    {"collection": "sleep", "field": "hours", "label": "昨晚睡了几小时"},
                    {"collection": "workout", "field": "minutes", "label": "今天运动几分钟"}
                  ]},
                  {"type": "html", "title": "连续打卡", "file": "widgets/streaks.html", "height": 190},
                  {"type": "pipelines", "title": "复盘", "items": ["discipline-review"]},
                  {"type": "text", "title": "导入数据", "text": "`twain data add sleep --record '{\\"hours\\": 7.5}'`\\nPOST http://127.0.0.1:27182/v1/data/sleep\\n或把 CSV 丢进 .twain/inbox/sleep/"}
                ]
              }
            }
            """,
            "templates/review.md": "# 复盘 {{week}}\n\n## 数据\n\n## 做得好的\n\n## 要调整的\n\n## 下周试一件事\n- [ ] \n",
            "rules.md": """
            %FOLDER%/ 是我的自律记录。复盘时：
            - 先用 `twain data query <集合> --since 7d`（sleep、workout、habits）拿到数据，结论必须有数据支撑，写出具体数字。
            - 语气平实，不说教，不打鸡血；指出一个最值得调整的点就够了。
            """,
            "pipelines/discipline-review.md": """
            ---
            title: 自律周复盘
            agent: claude
            scope: vault
            icon: chart.xyaxis.line
            ---
            ## 看数据
            gate: none
            运行 `twain data query sleep --since 7d --field hours --reduce avg`、`twain data query workout --since 7d --field minutes`、
            `twain data query habits --since 7d`，再读 %FOLDER% 里最近的复盘。列出这一周的事实：每天的睡眠、运动、各习惯完成天数，以及和上周比的变化。

            ## 写复盘
            gate: review
            根据上一步的事实写本周复盘：做得好的、要调整的（只挑一个最关键的）、下周试一件具体的小事。每个判断写出对应的数字。
            用 propose_edit 新建 %FOLDER%/复盘 {{date}}.md。
            """,
            "widgets/streaks.html": """
            <!doctype html>
            <html><head><meta charset="utf-8"><style>
              body { margin: 0; font: 13px -apple-system, system-ui; color: var(--tw-text); background: transparent; }
              .row { display: flex; align-items: center; gap: 10px; margin: 6px 0; }
              .name { width: 56px; }
              .days { display: flex; gap: 3px; flex: 1; }
              .d { width: 12px; height: 12px; border-radius: 3px; background: var(--tw-fill); }
              .d.on { background: var(--tw-accent); }
              .n { width: 64px; text-align: right; color: var(--tw-secondary); font-variant-numeric: tabular-nums; }
            </style></head><body><div id="list">载入中…</div>
            <script>
            // An HTML module: it calls the same commands agents use, through window.twain.
            async function draw() {
              const res = await twain.call("data.query", { collection: "habits", since: "30d", limit: 2000 });
              const items = (twain.module.items || ["早起", "运动", "阅读", "冥想"]);
              const days = [...Array(30)].map((_, i) => { const d = new Date(); d.setDate(d.getDate() - 29 + i); return d.toISOString().slice(0, 10); });
              const done = {};
              for (const r of res.records || []) {
                const day = (r.date || r.time || "").slice(0, 10);
                done[r.habit + "|" + day] = r.done !== false;
              }
              document.getElementById("list").innerHTML = items.map(h => {
                let streak = 0;
                for (let i = days.length - 1; i >= 0 && done[h + "|" + days[i]]; i--) streak++;
                const dots = days.map(d => `<div class="d ${done[h + "|" + d] ? "on" : ""}" title="${d}"></div>`).join("");
                return `<div class="row"><div class="name">${h}</div><div class="days">${dots}</div><div class="n">连续 ${streak} 天</div></div>`;
              }).join("");
            }
            draw();
            twain.onDataChange(draw);
            </script></body></html>
            """,
        ])

    static let bullet = SpaceTemplate(
        id: "bullet", name: "子弹笔记", icon: "circle.grid.cross", summary: "快速记录、每日日志、任务迁移（Bullet Journal）。",
        folder: "子弹笔记", files: [
            "manifest.json": """
            {
              "id": "bullet",
              "name": "子弹笔记",
              "icon": "circle.grid.cross",
              "description": "每天一页日志，用符号快速记录；没做完的任务每天迁移一次。",
              "space": {
                "folder": "%FOLDER%",
                "entry": {"title": "{{date}}", "template": "templates/daily.md"},
                "rules": "rules.md",
                "modules": [
                  {"type": "today", "title": "今日日志"},
                  {"type": "tasks", "title": "待迁移的任务", "folder": "%FOLDER%", "limit": 12},
                  {"type": "query", "title": "最近的日志", "folder": "%FOLDER%", "sort": "name", "limit": 7},
                  {"type": "pipelines", "title": "迁移", "items": ["bullet-migrate"]},
                  {"type": "text", "title": "符号", "text": "- [ ] 任务　- [x] 完成　- [>] 已迁移　- [<] 已排期\\n- ○ 事件　- – 笔记　在符号前加 ! 表示重要"}
                ]
              }
            }
            """,
            "templates/daily.md": "# {{date}} {{weekday}}\n\n- [ ] \n",
            "rules.md": """
            %FOLDER%/ 是子弹笔记（Bullet Journal）。符号：`- [ ]` 任务、`- [x]` 完成、`- [>]` 已迁移、`- [<]` 已排期、`- ○` 事件、`- –` 笔记，前面加 `!` 表示重要。
            - 每条一行，短句，保留我的原话。
            - 迁移：把旧日志里的 `- [ ]` 改成 `- [>]`，并把同一条原样追加到今天的日志。
            """,
            "pipelines/bullet-migrate.md": """
            ---
            title: 迁移未完成任务
            agent: claude
            scope: vault
            icon: arrow.turn.down.right
            ---
            ## 列出待迁移
            gate: ask
            用 twain tasks --folder %FOLDER% 找出今天（{{date}}）以前日志里所有未完成的任务。列成表：任务 · 来自哪天 · 建议（迁移到今天 / 排期 / 放弃）及一句理由。先不要改文件。

            ## 执行迁移
            gate: review
            按上一步的表（以我给的意见为准）执行：旧日志里对应的 `- [ ]` 改成 `- [>]`（放弃的改成删除线），迁移的任务原样追加到 %FOLDER%/{{date}}.md（不存在就新建，标题 `# {{date}} {{weekday}}`）。
            每篇笔记用一次 propose_edit 提交。
            """,
        ])

    static let llmwiki = SpaceTemplate(
        id: "llmwiki", name: "LLM Wiki", icon: "books.vertical", summary: "Karpathy 的 LLM Wiki：资料放 raw/，agent 维护 wiki/，你提问和审阅。",
        folder: "Wiki", files: [
            "manifest.json": """
            {
              "id": "llmwiki",
              "name": "LLM Wiki",
              "icon": "books.vertical",
              "description": "原始资料放进 raw/（不改原文），由 agent 维护 wiki/ 里的页面、index.md 和 log.md；你负责提问、审阅、指方向。",
              "space": {
                "folder": "%FOLDER%",
                "rules": "rules.md",
                "modules": [
                  {"type": "ask", "title": "问 Wiki", "placeholder": "关于……wiki 里怎么说？", "scope": "folder:%FOLDER%/wiki", "span": 2},
                  {"type": "pipelines", "title": "维护", "items": ["wiki-ingest", "wiki-lint"]},
                  {"type": "note", "title": "索引", "path": "%FOLDER%/wiki/index.md"},
                  {"type": "query", "title": "最近更新的页面", "folder": "%FOLDER%/wiki", "sort": "modified", "limit": 8},
                  {"type": "query", "title": "原始资料", "folder": "%FOLDER%/raw", "sort": "modified", "limit": 8},
                  {"type": "text", "title": "怎么用", "text": "1. 把文章、论文、会议记录放进 %FOLDER%/raw/，原文不改。\\n2. 运行「摄入资料」：agent 读新资料，提议更新 wiki 页面、index.md 和 log.md，你逐段审阅。\\n3. 用「问 Wiki」提问；定期运行「体检」，找矛盾、孤立页面和过时说法。"}
                ]
              }
            }
            """,
            "rules.md": """
            %FOLDER%/ 是一个由 agent 维护的 LLM Wiki（Karpathy 模式）：
            - `raw/` 是原始资料，只读，永远不要修改。
            - `wiki/` 由你维护：一个概念一页，页名就是概念名；每个说法都用 [[raw/资料名]] 注明出处；页面之间多用 [[双链]]。
            - `wiki/index.md` 列出所有页面，每页一行摘要；`wiki/log.md` 只追加，格式 `## [日期] ingest|query|lint | 标题`。
            - 所有修改用 propose_edit 提交，写明理由；新资料和旧说法冲突时，保留两种说法并标出冲突，不要悄悄覆盖。
            """,
            "pipelines/wiki-ingest.md": """
            ---
            title: 摄入资料
            agent: claude
            scope: vault
            icon: tray.and.arrow.down.fill
            ---
            ## 看新资料
            gate: ask
            读 %FOLDER%/wiki/log.md，找出 %FOLDER%/raw/ 里还没摄入过的资料。逐份读完，列出：要点、会新建或修改哪些 wiki 页面、和已有说法有没有冲突。先不要改文件。

            ## 更新 wiki
            gate: review
            按上一步的计划（以我的意见为准）更新：新建或修改 %FOLDER%/wiki/ 下的页面（每个说法注明 [[raw/…]] 出处），更新 index.md，在 log.md 末尾追加 `## [{{date}}] ingest | 资料名`。
            每篇笔记用一次 propose_edit 提交，写明理由。
            """,
            "pipelines/wiki-lint.md": """
            ---
            title: Wiki 体检
            agent: claude
            scope: vault
            icon: stethoscope
            tools: annotate
            ---
            ## 体检
            gate: none
            通读 %FOLDER%/wiki/（先 skim 再按需 read_note）。找出：页面之间互相矛盾的说法、被新资料推翻的旧说法、没有任何页面链接到的孤立页面、应该互相链接却没有链接的页面、值得单独成页的概念。
            用 annotate 在对应页面的具体位置留批注说明问题和建议；最后在回答里列一份清单。不要直接修改页面。
            """,
        ],
        notes: ["%FOLDER%/wiki/index.md": "# 索引\n\n> 由 agent 维护：每个 wiki 页面一行摘要。\n",
                "%FOLDER%/wiki/log.md": "# 日志\n\n> 只追加：`## [日期] ingest|query|lint | 标题`\n",
                "%FOLDER%/raw/把资料放在这里.md": "# 把资料放在这里\n\n文章、论文、会议记录……原文放进 raw/，不要修改。然后在「LLM Wiki」空间里运行「摄入资料」。\n"])

    static let blank = SpaceTemplate(
        id: "blank", name: "空白空间", icon: "square.dashed", summary: "一个文件夹加一块仪表盘，从这里开始搭你自己的模式。",
        folder: "新空间", files: ["manifest.json": """
        {
          "id": "%ID%",
          "name": "%NAME%",
          "icon": "square.dashed",
          "description": "在右上角「编辑」里添加模块，或者直接修改 .twain/plugins/%ID%/manifest.json。",
          "space": {
            "folder": "%FOLDER%",
            "entry": {"title": "{{date}}"},
            "modules": [
              {"type": "today", "title": "今天"},
              {"type": "query", "title": "最近的笔记", "folder": "%FOLDER%", "sort": "modified", "limit": 8},
              {"type": "tasks", "title": "待办", "folder": "%FOLDER%", "limit": 8},
              {"type": "ask", "title": "提问", "placeholder": "问问这个空间里的笔记…", "scope": "folder:%FOLDER%"}
            ]
          }
        }
        """])
}
