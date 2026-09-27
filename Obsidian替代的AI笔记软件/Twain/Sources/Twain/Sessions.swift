import Darwin
import Foundation
import Observation
import TwainCore

enum SessionSource: Equatable {
    case app, terminal
    /// Started by an automation file; it may only propose changes, never write them.
    case automation
}

struct SessionItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case step(id: String, text: String, running: Bool)
        case agent(String)
        case change(rel: String, plus: Int, minus: Int)
        case error(String)
        /// The agent asked the user something (see `AppModel.questions`).
        case question(UUID)
        /// The outcome of a review with rejections, ready to send back to the agent.
        case feedback(rel: String, message: String, sent: Bool)
    }
    let id = UUID()
    var kind: Kind
}

@Observable
final class AgentSession: Identifiable {
    let id = UUID()
    let agent: AgentKind
    let source: SessionSource
    var title: String
    var items: [SessionItem] = []
    var running = false
    var cliSessionID: String?
    /// The model of the latest run started from Twain, nil when unknown (CLI default).
    var model: String?
    /// The thinking level of that run, nil when the model has none or it's unknown.
    var effort: String?
    /// Terminal sessions: the CLI process we found running inside the vault.
    var pid: Int32?
    var alive = true
    /// The automation this run belongs to, when an automation started it.
    var automationID: String?
    @ObservationIgnored var transcript: URL?
    @ObservationIgnored var transcriptStamp: Date?
    @ObservationIgnored var changeItems: [SessionItem] = []
    @ObservationIgnored var process: AgentProcess?

    init(agent: AgentKind, source: SessionSource, title: String) {
        self.agent = agent
        self.source = source
        self.title = title
    }

    /// Folds CLI events into visible items. Returns paths the agent is about to write.
    @discardableResult
    func apply(_ events: [AgentEvent]) -> [String] {
        var writes: [String] = []
        for e in events {
            switch e {
            case let .session(sid):
                cliSessionID = sid
            case let .user(t):
                items.append(SessionItem(kind: .user(t)))
                if title == "新会话" || title.isEmpty { title = String(t.prefix(10)) }
            case let .text(t):
                settleSteps()
                items.append(SessionItem(kind: .agent(t.trimmingCharacters(in: .whitespacesAndNewlines))))
            case let .step(id, text, write):
                if let w = write { writes.append(w) }
                if items.contains(where: { if case .step(id, _, _) = $0.kind { return true }; return false }) { continue }
                settleSteps()
                items.append(SessionItem(kind: .step(id: id, text: text, running: true)))
            case let .stepDone(id):
                if let i = items.lastIndex(where: { if case .step(id, _, _) = $0.kind { return true }; return false }),
                   case let .step(_, text, _) = items[i].kind {
                    items[i].kind = .step(id: id, text: text, running: false)
                }
            case let .error(msg):
                items.append(SessionItem(kind: .error(msg)))
            case .finished:
                settleSteps()
            }
        }
        return writes
    }

    func settleSteps() {
        for i in items.indices {
            if case let .step(id, text, true) = items[i].kind { items[i].kind = .step(id: id, text: text, running: false) }
        }
    }

    var lastActivity: Date { transcriptStamp ?? .distantPast }
}

/// Finds `claude` / `codex` processes whose working directory is inside the vault and
/// mirrors their session transcripts into the Agent panel.
final class TerminalWatcher {
    struct Found: Hashable {
        let pid: Int32
        let agent: AgentKind
        let cwd: String
    }

    static func scan(root: String) -> [Found] {
        let me = getpid()
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 32)
        let n = pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<Int32>.size)) }
        var out: [Found] = []
        let prefix = root.hasSuffix("/") ? root : root + "/"
        for pid in pids.prefix(Int(max(0, n))) where pid > 0 && pid != me {
            guard let path = executablePath(pid) else { continue }
            let name = (path as NSString).lastPathComponent
            guard let agent = AgentKind(rawValue: name) else { continue }
            guard let cwd = workingDirectory(pid), cwd == root || cwd.hasPrefix(prefix) else { continue }
            if isDescendant(pid, of: me) { continue }
            out.append(Found(pid: pid, agent: agent, cwd: cwd))
        }
        // codex launches a native child with the same name; keep only the outermost.
        return out.filter { f in !out.contains { $0.pid != f.pid && $0.agent == f.agent && parent(f.pid) == $0.pid } }
    }

    static func executablePath(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let r = proc_pidpath(pid, &buf, UInt32(buf.count))
        return r > 0 ? String(cString: buf) : nil
    }

    static func workingDirectory(_ pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    static func parent(_ pid: Int32) -> Int32? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Int32(info.pbi_ppid)
    }

    static func isDescendant(_ pid: Int32, of ancestor: Int32) -> Bool {
        var cur = pid
        for _ in 0..<32 {
            guard let p = parent(cur), p > 1 else { return false }
            if p == ancestor { return true }
            cur = p
        }
        return false
    }

    // MARK: transcripts

    static func claudeTranscript(cwd: String) -> URL? {
        let escaped = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects/" + escaped)
        return newest(in: dir) { $0.pathExtension == "jsonl" }
    }

    static func codexTranscript(cwd: String) -> URL? {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/sessions")
        let cal = Calendar.current
        var candidates: [(URL, Date)] = []
        for back in 0..<2 {
            guard let day = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            let dir = base.appendingPathComponent(String(format: "%04d/%02d/%02d", c.year!, c.month!, c.day!))
            for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] where u.lastPathComponent.hasPrefix("rollout-") {
                let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                candidates.append((u, d))
            }
        }
        for (u, _) in candidates.sorted(by: { $0.1 > $1.1 }) {
            guard let h = try? FileHandle(forReadingFrom: u) else { continue }
            let head = h.readData(ofLength: 64 * 1024)
            try? h.close()
            var d = head
            if let nl = d.firstIndex(of: 0x0A) { d = d[d.startIndex..<nl] }
            if let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any], CodexRollout.cwd(ofMeta: obj) == cwd {
                return u
            }
        }
        return nil
    }

    static func newest(in dir: URL, where keep: (URL) -> Bool) -> URL? {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items.filter(keep).max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    static func modified(_ u: URL) -> Date? {
        try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Parses (the tail of) a transcript into events.
    static func events(transcript u: URL, agent: AgentKind, root: String) -> [AgentEvent] {
        guard let h = try? FileHandle(forReadingFrom: u) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        let cap: UInt64 = 3 * 1024 * 1024
        try? h.seek(toOffset: size > cap ? size - cap : 0)
        var data = h.readDataToEndOfFile()
        if size > cap, let nl = data.firstIndex(of: 0x0A) { data.removeSubrange(data.startIndex...nl) }
        data.append(0x0A)
        let objs = JSONLines.drain(&data)
        var out: [AgentEvent] = []
        for (i, o) in objs.enumerated() {
            out += agent == .claude ? ClaudeStream.events(from: o, root: root, transcript: true)
                                    : CodexRollout.events(from: o, root: root, index: i)
        }
        return out.filter { if case .finished = $0 { return false }; return true }
    }
}
