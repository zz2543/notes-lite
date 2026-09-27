#!/usr/bin/env python3
"""Send 懂听 GotIt summaries into 共笔 Twain through Twain's local HTTP API.

An example of the "open door" rather than a Twain feature: nothing in Twain knows GotIt.
It reads GotIt's own files (read-only), posts each finished episode's summary.md to
POST /v1/notes with source=GotIt and source_id=<episode id>. Twain creates the note the
first time; when a summary changes later, Twain turns it into a proposal for review instead
of overwriting edits. Standard library only.

    python3 twain-gotit-sync.py                # sync once
    python3 twain-gotit-sync.py --watch 60     # keep syncing every 60 s
    python3 twain-gotit-sync.py --folder 视频总结 --dry-run
"""
import argparse, json, os, sqlite3, sys, time, urllib.request, urllib.error

GOTIT = os.path.expanduser("~/Library/Application Support/GotIt/data")
TOKEN_FILE = os.path.expanduser("~/Library/Application Support/Twain/http-token")


def episodes(data_dir):
    db = sqlite3.connect(f"file:{os.path.join(data_dir, 'podsum.sqlite3')}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    rows = db.execute("""
        select e.id, e.title, e.podcast_name, e.source_type, e.source_ref, e.data_dir, e.created_at,
               c.name as category
        from episode e left join category c on c.id = e.category_id
        where e.status in ('done', 'partial') order by e.created_at""").fetchall()
    db.close()
    for r in rows:
        folder = r["data_dir"] if os.path.isabs(r["data_dir"] or "") else os.path.join(data_dir, r["data_dir"] or r["id"])
        path = os.path.join(folder, "summary.md")
        if os.path.exists(path):
            yield r, path


def note_for(r, summary_path):
    with open(summary_path, encoding="utf-8") as f:
        body = f.read().strip()
    tags = ["视频总结"] + ([r["category"]] if r["category"] else [])
    front = ["---", f"source: {r['source_ref']}", f"gotit_id: {r['id']}", f"created: {r['created_at']}",
             "tags: [" + ", ".join(tags) + "]", "---", ""]
    return "\n".join(front) + body + "\n"


def post(port, token, payload):
    req = urllib.request.Request(f"http://127.0.0.1:{port}/v1/notes", data=json.dumps(payload).encode(),
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
                                 method="POST")
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp)


def sync(args, token):
    created = updated = same = 0
    for r, path in episodes(args.gotit):
        title = (r["title"] or r["id"]).replace("/", "-")
        payload = {"title": title, "content": note_for(r, path), "source": "GotIt", "source_id": r["id"], "folder": args.folder}
        if args.dry_run:
            print("would send", title)
            continue
        res = post(args.port, token, payload)
        if res.get("created"): created += 1; print("新建", res["path"])
        elif res.get("status") == "proposed": updated += 1; print("有更新，已提交审阅", res["path"])
        else: same += 1
    print(f"GotIt → 共笔：新建 {created}，更新待审 {updated}，无变化 {same}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gotit", default=GOTIT, help="GotIt data folder")
    ap.add_argument("--folder", default="视频总结", help="folder in the Twain vault")
    ap.add_argument("--port", type=int, default=int(os.environ.get("TWAIN_HTTP_PORT", 27182)))
    ap.add_argument("--token", default=os.environ.get("TWAIN_TOKEN"))
    ap.add_argument("--watch", type=int, metavar="SECONDS")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()
    token = args.token or (open(TOKEN_FILE).read().strip() if os.path.exists(TOKEN_FILE) else None)
    if not token and not args.dry_run:
        sys.exit("找不到共笔的接口令牌：打开共笔（设置 → 开放接口），或用 --token 传入")
    while True:
        try:
            sync(args, token)
        except urllib.error.URLError as e:
            print("连不上共笔：", e, file=sys.stderr)
            if not args.watch: sys.exit(1)
        if not args.watch: break
        time.sleep(args.watch)


if __name__ == "__main__":
    main()
