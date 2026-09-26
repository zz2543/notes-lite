#!/bin/bash
# End-to-end check of the `twain` command against a live Twain on a throwaway vault.
# Runs a debug build in the background on its own socket, so a Twain you have open is untouched.
# Usage: scripts/e2e.sh
set -uo pipefail
cd "$(dirname "$0")/.."
swift build >/dev/null || exit 1
BIN="$(swift build --show-bin-path)"
CLI="$BIN/twain-cli"

VAULT="$(mktemp -d)/vault"
# Unix socket paths are capped at 104 bytes, so not under $TMPDIR.
SOCK="$HOME/Library/Application Support/Twain/run/e2e-$$.sock"
mkdir -p "$VAULT/.twain" "$VAULT/项目"
printf '# 收件箱\n- [ ] 读 [[同步引擎]] 的方案\n- [x] 已完成\n' > "$VAULT/收件箱.md"
printf '# 同步引擎\n## 冲突处理\n用 CRDT 处理冲突。 #工作\n- [ ] 压测\n' > "$VAULT/项目/同步引擎.md"

TWAIN_SNAPSHOT_VAULT="$VAULT" TWAIN_BACKGROUND=1 TWAIN_SOCK="$SOCK" "$BIN/Twain" >/dev/null 2>&1 &
APP=$!
trap 'kill $APP 2>/dev/null; rm -f "$SOCK"; rm -rf "$(dirname "$VAULT")"' EXIT
for _ in $(seq 50); do [ -S "$SOCK" ] && break; sleep 0.2; done
[ -S "$SOCK" ] || { echo "FAIL: Twain never opened $SOCK"; exit 1; }

export TWAIN_SOCK="$SOCK"
FAILS=0
# check <name> <expected substring> <command…>, run from inside the vault.
check() {
    local name="$1" want="$2"; shift 2
    local got
    got="$(cd "$VAULT/项目" && "$@" 2>&1)"
    if [[ "$got" == *"$want"* ]]; then echo "ok   $name"; else
        echo "FAIL $name"; echo "     wanted: $want"; echo "     got:    ${got//$'\n'/$'\n'             }"; FAILS=$((FAILS + 1))
    fi
}

check "context names the open note"   "当前笔记：收件箱.md"              "$CLI" context
check "open jumps to a heading"       "已在共笔中打开 项目/同步引擎.md（第 2 行）" "$CLI" open 同步引擎 --heading 冲突处理
check "context follows the editor"    "同步引擎 › 冲突处理"             "$CLI" context
check "context lists backlinks"       "收件箱.md:2"                     "$CLI" context
check "search ranks the title first"  "项目/同步引擎.md  （标题）"        "$CLI" search 同步引擎
check "backlinks"                     "收件箱.md:2  - [ ] 读 [[同步引擎]] 的方案" "$CLI" backlinks 同步引擎
check "tasks skip done ones"          "项目/同步引擎.md:4  - [ ] 压测"    "$CLI" tasks
check "tasks filter by tag"           "压测"                            "$CLI" tasks --tag 工作
check "outline"                       "标签：#工作"                      "$CLI" outline 同步引擎
check "json output"                   '"headingPath" : ['               "$CLI" context --json
check "notify"                        ""                                "$CLI" notify 测试
check "palette-only commands stay in" "没有命令 zen"                     "$CLI" zen
check "missing params are usage errors" "缺少参数 query"                 "$CLI" search
check "unknown notes are reported"    "找不到笔记：不存在"                "$CLI" open 不存在

# Phase 2: proposals, reviews, questions. `debug.*` commands stand in for the user's clicks.
EVENTS="$(dirname "$VAULT")/events.jsonl"
"$CLI" watch > "$EVENTS" 2>/dev/null &
WATCH=$!
sleep 0.3
check "propose leaves the file alone"  "共 1 处改动，正在等用户"          "$CLI" propose 同步引擎 --edits '[{"old":"用 CRDT 处理冲突。","new":"用 CRDT 合并冲突。","reason":"更准确"}]'
check "file still original"           "用 CRDT 处理冲突。"               cat "$VAULT/项目/同步引擎.md"
check "one pending review per note"   "还有 1 处改动等用户审阅"           "$CLI" propose 同步引擎 --content x
check "context shows the proposal"    "项目/同步引擎.md  +1 −1"          "$CLI" context
check "rejecting keeps the file"      '"done" : true'                   "$CLI" debug.review 项目/同步引擎.md --states rejected --feedback 保留原话 --json
check "file unchanged after reject"   "用 CRDT 处理冲突。"               cat "$VAULT/项目/同步引擎.md"
check "reviews keep the reason"       "原因：保留原话"                    "$CLI" reviews
(sleep 1; "$CLI" debug.review 新建.md --states accepted >/dev/null) &
check "wait returns the review"       "用户审阅了 新建.md：接受 1 处"      "$CLI" propose 新建 --content "# 新建" --wait
check "accepted new note exists"      "# 新建"                          cat "$VAULT/新建.md"
check "edits must match"              "找不到"                          "$CLI" propose 收件箱 --edits '[{"old":"不存在的句子","new":"x"}]'
(sleep 1; "$CLI" debug.answer B >/dev/null) &
check "ask returns the answer"        "用户回答：B"                      "$CLI" ask 选哪个 --options A,B
check "ask times out"                 "没有在限定时间内回答"              "$CLI" ask 没人回答 --timeout 5
check "watch saw the proposal"        '"type":"proposal.created"'       cat "$EVENTS"
check "watch saw the review"          '"status":"rejected"'             cat "$EVENTS"
kill $WATCH 2>/dev/null; wait $WATCH 2>/dev/null

# Phase 3: the vault's own commands and automations.
check "default commands are written"  "polish"                          ls "$VAULT/.twain/commands"
check "unknown commands list the rest" "可用的有：continue、polish"       "$CLI" run 不存在
check "sample automation stays off"   "inbox.md.example"                ls "$VAULT/.twain/automations"
check "twain help watch lists events" "review.resolved"                 "$CLI" help watch

kill $APP 2>/dev/null; wait $APP 2>/dev/null
check "read commands work offline"    "项目/同步引擎.md:4"              "$CLI" tasks
check "reviews work offline"          "原因：保留原话"                    "$CLI" reviews
check "app-only commands say so"      "共笔没有运行"                  "$CLI" context

[ $FAILS -eq 0 ] && echo "e2e: all passed" || { echo "e2e: $FAILS failed"; exit 1; }
