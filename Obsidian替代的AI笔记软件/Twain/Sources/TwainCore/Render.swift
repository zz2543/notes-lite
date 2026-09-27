import Foundation

/// Plain-text forms of command results: `path:line  text` where it fits, like `grep -n`,
/// because that is what agents (and people) read most easily in a terminal.
public enum Render {
    public static func text(_ id: String, _ r: JSONValue) -> String {
        switch id {
        case "context": return context(r)
        case "search": return hits(r["results"], empty: "没有找到“\(r["query"]?.string ?? "")”")
        case "backlinks": return hits(r["backlinks"], empty: "没有笔记链接到 \(r["note"]?.string ?? "")")
        case "notes": return (r["notes"]?.array ?? []).compactMap { $0["path"]?.string }.joined(separator: "\n")
        case "outline": return outline(r)
        case "skim": return skim(r)
        case "data":
            let cs = r["collections"]?.array ?? []
            if cs.isEmpty { return "还没有数据集合。用 twain data add <集合> --record '{…}' 新建。" }
            return cs.map { "\($0["name"]?.string ?? "")  \($0["count"]?.int ?? 0) 条  字段：\(($0["fields"]?.array ?? []).compactMap(\.string).joined(separator: ", "))" }
                .joined(separator: "\n")
        case "data.add", "data.import": return "已向 \(r["collection"]?.string ?? "") 添加 \(r["added"]?.int ?? 0) 条记录"
        case "data.query":
            if let days = r["days"]?.array {
                return days.map { "\($0["date"]?.string ?? "")  \($0["value"]?.number.map { String(format: "%g", $0) } ?? "—")" }.joined(separator: "\n")
            }
            return (r["records"]?.array ?? []).map { $0.text() }.joined(separator: "\n")
        case "read": return read(r)
        case "tasks": return tasks(r)
        case "commands": return commands(r)
        case "open":
            return "已在共笔中打开 \(r["note"]?.string ?? "")" + (r["line"]?.int.map { $0 > 1 ? "（第 \($0) 行）" : "" } ?? "")
        case "reveal": return "已在侧栏中定位 \(r["note"]?.string ?? "")"
        case "propose": return proposal(r)
        case "ask":
            if r["answered"]?.bool == true { return "用户回答：\(r["answer"]?.string ?? "")" }
            return r["reason"]?.string == "timeout" ? "用户没有在限定时间内回答" : "问题已取消，没有得到回答"
        case "run": return "已在共笔中运行命令 /\(r["command"]?.string ?? "")（\(r["agent"]?.string ?? "")）"
        case "reviews": return reviews(r)
        default:
            if let o = r.object, o.keys.allSatisfy({ ["done", "shown"].contains($0) }) { return "" }
            return r.text(pretty: true)
        }
    }

    static func card(_ c: JSONValue) -> String {
        var line = "\(c["path"]?.string ?? "") · \(c["summary"]?.string ?? "")"
        let tags = (c["tags"]?.array ?? []).compactMap(\.string)
        if !tags.isEmpty { line += "  " + tags.map { "#" + $0 }.joined(separator: " ") }
        line += "（\(c["words"]?.int ?? 0) 字）"
        let heads = (c["headings"]?.array ?? []).compactMap(\.string)
        if !heads.isEmpty { line += "\n    标题：" + heads.joined(separator: " / ") }
        return line
    }

    static func skim(_ r: JSONValue) -> String {
        let cards = r["cards"]?.array ?? []
        if cards.isEmpty { return "没有符合条件的笔记" }
        let total = r["total"]?.int ?? cards.count
        return cards.map(card).joined(separator: "\n") + (total > cards.count ? "\n（共 \(total) 篇，只列出前 \(cards.count) 篇；缩小 folder、tag 或 query 再看）" : "")
    }

    static func read(_ r: JSONValue) -> String {
        let path = r["note"]?.string ?? ""
        if let lines = r["lines"]?.array {
            let from = r["from"]?.int ?? 1
            let head = r["section"]?.string.map { "\(path) · \($0)" } ?? path
            return head + "\n" + lines.enumerated().map { i, l in "\(from + i)| \(l.string ?? "")" }.joined(separator: "\n")
        }
        var out = r["card"].map(card) ?? path
        if let o = r["outline"]?.array {
            out += "\n提纲："
            for h in o {
                let pad = String(repeating: "  ", count: max(0, (h["level"]?.int ?? 1) - 1))
                out += "\n  \(pad)\(h["line"]?.int ?? 0): \(h["text"]?.string ?? "")（\(h["lines"]?.int ?? 0) 行）"
                if let op = h["opening"]?.string, !op.isEmpty { out += " — " + op }
            }
            if let t = r["tasks"]?.int, t > 0 { out += "\n未完成待办：\(t)" }
            let links = (r["links"]?.array ?? []).compactMap(\.string)
            if !links.isEmpty { out += "\n链接到：" + links.map { "[[\($0)]]" }.joined(separator: " ") }
        }
        return out
    }

    static func proposal(_ r: JSONValue) -> String {
        let path = r["path"]?.string ?? ""
        switch r["status"]?.string ?? "" {
        case "unchanged": return "\(path) 的内容没有变化，没有提交提案"
        case "pending":
            return "已提交修改提案 \(r["id"]?.string ?? "")：\(path) 共 \(r["hunks"]?.int ?? 0) 处改动，正在等用户在共笔里审阅。"
                + "要知道审阅结果，下次加上 wait。"
        case "stale": return "\(path) 在提案之后被修改过，这份提案已作废。请重新读取文件后再提交。"
        default:
            let hunks = r["hunks"]?.array ?? []
            let rejected = hunks.filter { $0["state"]?.string == "rejected" }
            var lines = ["用户审阅了 \(path)：接受 \(hunks.count - rejected.count) 处，拒绝 \(rejected.count) 处。"]
            for h in rejected {
                lines.append("  第 \(h["lines"]?.string ?? "?") 行被拒绝" + (h["feedback"]?.string.map { "，原因：\($0)" } ?? "（没有写原因）"))
            }
            return lines.joined(separator: "\n")
        }
    }

    static func reviews(_ r: JSONValue) -> String {
        let items = r["reviews"]?.array ?? []
        if items.isEmpty { return "还没有处理过的修改" }
        return items.map { p in
            let hunks = p["hunks"]?.array ?? []
            var lines = ["\(p["path"]?.string ?? "") · \(p["status"]?.string ?? "") · \(p["agent"]?.string ?? "未知 agent")"
                         + (p["reason"]?.string.map { " · \($0)" } ?? "")]
            for h in hunks where h["state"]?.string == "rejected" {
                let old = h["old"]?.string ?? "", new = h["new"]?.string ?? ""
                let what = old.isEmpty ? "在第 \(h["lines"]?.string ?? "?") 行插入“\(new)”"
                    : new.isEmpty ? "删除第 \(h["lines"]?.string ?? "?") 行“\(old)”"
                    : "第 \(h["lines"]?.string ?? "?") 行：“\(old)” → “\(new)”"
                lines.append("  拒绝 " + what + (h["feedback"]?.string.map { "，原因：\($0)" } ?? ""))
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    static func loc(_ h: JSONValue) -> String {
        let p = h["path"]?.string ?? ""
        return h["line"]?.int.map { "\(p):\($0)" } ?? p
    }

    static func hits(_ list: JSONValue?, empty: String) -> String {
        let items = list?.array ?? []
        if items.isEmpty { return empty }
        return items.map { h in
            h["line"]?.int == nil ? "\(loc(h))  （标题）" : "\(loc(h))  \(h["text"]?.string ?? "")"
        }.joined(separator: "\n")
    }

    static func tasks(_ r: JSONValue) -> String {
        let items = r["tasks"]?.array ?? []
        if items.isEmpty { return "没有待办" }
        return items.map { t in
            "\(loc(t))  - [\(t["done"]?.bool == true ? "x" : " ")] \(t["text"]?.string ?? "")"
        }.joined(separator: "\n")
    }

    static func outline(_ r: JSONValue) -> String {
        var lines = [r["note"]?.string ?? ""]
        let headings = r["headings"]?.array ?? []
        if !headings.isEmpty {
            lines += ["", "标题："]
            for h in headings {
                let level = h["level"]?.int ?? 1
                lines.append(String(format: "%5d  ", h["line"]?.int ?? 0) + String(repeating: "#", count: level) + " " + (h["text"]?.string ?? ""))
            }
        }
        let tasks = r["tasks"]?.array ?? []
        if !tasks.isEmpty {
            lines += ["", "待办："]
            for t in tasks {
                lines.append(String(format: "%5d  ", t["line"]?.int ?? 0) + "- [\(t["done"]?.bool == true ? "x" : " ")] " + (t["text"]?.string ?? ""))
            }
        }
        let links = r["links"]?.array ?? []
        if !links.isEmpty {
            lines += ["", "链接："]
            for l in links {
                let target = l["target"]?.string ?? ""
                let to = l["path"]?.string.map { " → \($0)" } ?? "（不存在）"
                lines.append(String(format: "%5d  ", l["line"]?.int ?? 0) + "[[\(target)]]" + to)
            }
        }
        let tags = (r["tags"]?.array ?? []).compactMap(\.string)
        if !tags.isEmpty { lines += ["", "标签：" + tags.map { "#" + $0 }.joined(separator: " ")] }
        return lines.joined(separator: "\n")
    }

    static func commands(_ r: JSONValue) -> String {
        (r["commands"]?.array ?? []).map { c in
            let usage = c["usage"]?.string ?? ""
            let summary = c["summary"]?.string ?? ""
            return summary.isEmpty ? usage : usage + "\n    " + summary
        }.joined(separator: "\n")
    }

    static func context(_ r: JSONValue) -> String {
        var lines = ["库：" + (r["vault"]?.string ?? "")]
        if let s = r["session"], let title = s["title"]?.string {
            lines.append("会话：\(title)（\(s["agent"]?.string ?? "")）")
        }
        guard let n = r["note"], !n.isNull else {
            lines.append("当前没有打开的笔记")
            return lines.joined(separator: "\n") + pending(r)
        }
        lines.append("当前笔记：" + (n["path"]?.string ?? "") + (n["unsaved"]?.bool == true ? "（有未保存的修改）" : "")
                     + (n["pendingReview"]?.bool == true ? "（有待审阅的改动）" : ""))
        var cursor = "光标：第 \(n["cursor"]?["line"]?.int ?? 1) 行"
        let path = (n["headingPath"]?.array ?? []).compactMap(\.string)
        if !path.isEmpty { cursor += " · " + path.joined(separator: " › ") }
        lines.append(cursor)
        if let sel = n["selection"], !sel.isNull {
            let a = sel["start"]?["line"]?.int ?? 0, b = sel["end"]?["line"]?.int ?? 0
            lines.append("选区：" + (a == b ? "第 \(a) 行" : "第 \(a)–\(b) 行") + (sel["truncated"]?.bool == true ? "（已截断）" : ""))
            lines.append("<<<")
            lines.append(sel["text"]?.string ?? "")
            lines.append(">>>")
        } else {
            lines.append("选区：无")
        }
        let back = n["backlinks"]?.array ?? []
        lines.append("反链：" + (back.isEmpty ? "无" : "\(back.count) 处"))
        for h in back { lines.append("  \(loc(h))  \(h["text"]?.string ?? "")") }
        return lines.joined(separator: "\n") + pending(r)
    }

    static func pending(_ r: JSONValue) -> String {
        let items = r["pending"]?.array ?? []
        guard !items.isEmpty else { return "\n待审阅：无" }
        return "\n待审阅：\n" + items.map { p in
            "  \(p["path"]?.string ?? "")  +\(p["plus"]?.int ?? 0) −\(p["minus"]?.int ?? 0)" + (p["by"]?.string.map { "（\($0)）" } ?? "")
        }.joined(separator: "\n")
    }
}
