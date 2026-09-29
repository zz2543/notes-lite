import AppKit
import Network
import TwainCore

/// Twain's door for other apps: HTTP on 127.0.0.1 only, with a bearer token. Any app — a video
/// summarizer, a health exporter, a shortcut — can import notes, add data, or call the same
/// commands agents use, under the same rules (changes to existing notes go through review).
///
///     GET  /v1/ping                         no token needed
///     POST /v1/call/<command>               body: params          → any agent-facing command
///     GET  /v1/data                         collections
///     POST /v1/data/<collection>            body: record or [records]
///     GET  /v1/data/<collection>?since=7d&field=hours&reduce=avg
///     POST /v1/notes                        {title, content, folder?, source?, source_id?}
///     GET  /v1/notes?q=&folder=&tag=        note cards (skim)
///     GET  /v1/notes/<path>?level=1|2|3     one note, by level
/// What Settings shows about the listener.
struct HTTPStatus: Equatable {
    var port: UInt16 = 0
    var error: String?
}

final class HTTPGateway {
    static let defaultPort: UInt16 = 27182
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "twain.http")
    weak var model: AppModel?
    private(set) var port: UInt16 = 0
    private(set) var error: String?

    static var tokenURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Twain/http-token")
    }

    /// Read once: every request checks it, and the file only changes when Twain resets it.
    private static var cachedToken: String?

    /// The token, created on first use (random, 0600).
    static func token(reset: Bool = false) -> String {
        if !reset, let t = cachedToken { return t }
        let u = tokenURL
        if !reset, let t = try? String(contentsOf: u, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), t.count >= 32 {
            cachedToken = t
            return t
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let t = "tw_" + bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? t.write(to: u, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
        cachedToken = t
        return t
    }

    func start(port: UInt16) {
        stop()
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready: self?.port = port; self?.error = nil
                    case let .failed(e): self?.error = "端口 \(port) 不可用：\(e.localizedDescription)"; self?.port = 0
                    default: break
                    }
                    if let self { self.model?.httpStatus = HTTPStatus(port: self.port, error: self.error) }
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    // MARK: HTTP

    private struct Request {
        var method: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: Data
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        read(c, Data())
    }

    private func read(_ c: NWConnection, _ buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if buf.count > 8 << 20 { return self.send(c, 413, ["error": "请求太大"]) }
            if let req = Self.parse(buf) {
                DispatchQueue.main.async { self.handle(req) { status, body in self.send(c, status, body) } }
            } else if done || error != nil {
                c.cancel()
            } else {
                self.read(c, buf)
            }
        }
    }

    /// A complete request, or nil while more bytes are needed.
    private static func parse(_ data: Data) -> Request? {
        guard let headEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<headEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return Request(method: "BAD", path: "", query: [:], headers: [:], body: Data()) }
        var headers: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[headEnd.upperBound...]
        guard body.count >= length else { return nil }
        let target = String(first[1])
        let comps = URLComponents(string: "http://x" + target)
        var query: [String: String] = [:]
        for q in comps?.queryItems ?? [] { query[q.name] = q.value ?? "" }
        return Request(method: String(first[0]), path: comps?.percentEncodedPath.removingPercentEncoding ?? target,
                       query: query, headers: headers, body: Data(body.prefix(length)))
    }

    private func send(_ c: NWConnection, _ status: Int, _ body: JSONValue) {
        let data = body.encoded(pretty: true)
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 409: "Conflict", 413: "Payload Too Large",
                      500: "Internal Server Error", 503: "Service Unavailable"][status] ?? "OK"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(data)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: routes

    @MainActor private func handle(_ r: Request, reply: @escaping (Int, JSONValue) -> Void) {
        guard let m = model else { return reply(503, ["error": "共笔没有就绪"]) }
        let parts = r.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.first == "v1" else { return reply(404, ["error": .string("没有这个接口：\(r.path)")]) }
        let route = Array(parts.dropFirst())
        if route == ["ping"] {
            return reply(200, ["app": "twain", "api": 1, "vault": JSONValue(m.vault?.name)])
        }
        let auth = r.headers["authorization"].map { $0.replacingOccurrences(of: "Bearer ", with: "") } ?? r.headers["x-twain-token"]
        guard let auth, Secrets.equal(auth, Self.token()) else { return reply(401, ["error": "需要令牌：Authorization: Bearer <令牌>（在共笔的 设置 → 开放接口 里查看）"]) }
        guard m.vault != nil else { return reply(503, ["error": "共笔没有打开任何库"]) }
        let body: JSONValue = r.body.isEmpty ? .object([:]) : ((try? JSONDecoder().decode(JSONValue.self, from: r.body)) ?? .null)
        if !r.body.isEmpty, body.isNull { return reply(400, ["error": "请求体不是合法的 JSON"]) }

        @MainActor func run(_ id: String, _ params: [String: JSONValue]) {
            guard let cmd = CommandRegistry.command(id, in: m), cmd.agents else { return reply(404, ["error": .string("没有命令 \(id)")]) }
            do { try cmd.spec.validate(params) } catch let e as RPCError { return reply(400, ["error": .string(e.message)]) } catch {}
            cmd.perform(m, CommandCall(params: params)) { result in
                switch result {
                case let .success(v): reply(200, ["result": v])
                case let .failure(e): reply(e.code == RPCError.notFound ? 404 : 400, ["error": .string(e.message), "code": JSONValue(e.code)])
                }
            }
        }
        let query = r.query.mapValues { v -> JSONValue in Int(v).map { JSONValue($0) } ?? .string(v) }

        switch (r.method, route.first, route.count) {
        case ("POST", "call", 2):
            run(route[1], body.object ?? [:])
        case ("GET", "data", 1):
            run("data", [:])
        case ("POST", "data", 2):
            run("data.add", ["collection": .string(route[1]), "record": body])
        case ("GET", "data", 2):
            var p = query
            p["collection"] = .string(route[1])
            run("data.query", p)
        case ("POST", "notes", 1):
            do { reply(200, try m.importNote(body)) } catch let e as RPCError { reply(400, ["error": .string(e.message)]) } catch {
                reply(500, ["error": .string(error.localizedDescription)])
            }
        case ("GET", "notes", 1):
            var p = query
            if let q = r.query["q"] { p["query"] = .string(q) }
            run("skim", p)
        case ("GET", "notes", _):
            var p = query
            p["note"] = .string(route.dropFirst().joined(separator: "/"))
            run("read", p)
        default:
            reply(404, ["error": .string("没有这个接口：\(r.method) \(r.path)")])
        }
    }
}

extension AppModel {
    /// A note from another app. New notes are written straight away (the user started the import
    /// in that app); a later version of the same `source_id` is proposed for review instead of
    /// overwriting what the user may have edited since.
    func importNote(_ body: JSONValue) throws -> JSONValue {
        guard let v = vault else { throw RPCError(RPCError.noVault, "共笔没有打开任何库") }
        guard let content = body["content"]?.string, !content.isEmpty else { throw RPCError(RPCError.invalidParams, "需要 content") }
        let source = body["source"]?.string.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        let sourceID = body["source_id"]?.string ?? body["sourceId"]?.string
        var title = body["title"]?.string ?? Markdown.titleHeading(content) ?? "导入的笔记"
        title = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        if title.hasPrefix(".") { title = "_" + title }
        let folder = (body["folder"]?.string ?? (source.map { "导入/" + $0 } ?? "导入"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !folder.split(separator: "/").contains(where: { $0 == ".." || $0.hasPrefix(".") }) else {
            throw RPCError(RPCError.invalidParams, "文件夹不合法：\(folder)")
        }
        let mapURL = v.root.appendingPathComponent(".twain/imports.json")
        var map = (try? Data(contentsOf: mapURL)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let key = sourceID.map { (source ?? "") + ":" + $0 }
        if let key, let rel = map[key], v.note(rel) != nil || FileManager.default.fileExists(atPath: v.url(rel).path) {
            if v.diskContent(rel) == content { return ["path": .string(rel), "created": false, "status": "unchanged"] }
            // An update: the user reviews it like any other change.
            var result: JSONValue = .null
            var failure: RPCError?
            propose(CommandCall(params: ["note": .string(rel), "content": .string(content),
                                         "reason": .string("\(source ?? "外部程序") 发来了新版本")])) { r in
                switch r {
                case let .success(v): result = v
                case let .failure(e): failure = e
                }
            }
            if let failure { throw failure }
            return ["path": .string(rel), "created": false, "status": "proposed", "proposal": result]
        }
        let rel = v.create(title: title, folder: folder, content: content.hasSuffix("\n") ? content : content + "\n")
        if let key {
            map[key] = rel
            try? FileManager.default.createDirectory(at: mapURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let d = try? JSONEncoder().encode(map) { try? d.write(to: mapURL, options: .atomic) }
        }
        emit("note.imported", source: source.map { "app:" + $0 } ?? "external", ["path": .string(rel)])
        showToast("\(source ?? "外部程序") 导入了「\(NoteRef(rel: rel).title)」")
        if body["open"]?.bool == true { open(rel) }
        return ["path": .string(rel), "created": true]
    }
}

extension AppModel {
    func handleURL(_ u: URL) {
        guard u.scheme == "twain", let host = u.host() else { return }
        var q: [String: String] = [:]
        for item in URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? [] { q[item.name] = item.value ?? "" }
        NSApp.activate(ignoringOtherApps: true)
        switch host {
        case "open":
            guard let ref = q["note"] ?? q["path"] else { return showToast("找不到笔记：") }
            withFreshIndex { [weak self] r in
                guard let self else { return }
                guard case let .success((index, _)) = r, let rel = index.resolve(ref) else { return self.showToast("找不到笔记：\(ref)") }
                self.open(rel)
                if let line = q["line"].flatMap(Int.init) { self.requestFocus(caret: NoteFile.offset(ofLine: line, in: self.editor.editorText)) }
            }
        case "new":
            var body: [String: JSONValue] = ["content": .string(q["content"] ?? "# \(q["title"] ?? "未命名")\n"), "open": true]
            if let t = q["title"] { body["title"] = .string(t) }
            if let f = q["folder"] { body["folder"] = .string(f) }
            if let s = q["source"] { body["source"] = .string(s) }
            do { _ = try importNote(.object(body)) } catch let e as RPCError { showToast(e.message) } catch {}
        case "ask":
            newDesk()
            if let text = q["q"], !text.isEmpty, let id = chrome.openDesk { ask(desk: id, question: text, scope: q["scope"] ?? "") }
        case "run":
            guard let name = q["name"] else { return }
            do {
                if let c = userCommand(named: name) { _ = try runUserCommand(c, input: q["input"]) }
                else if let p = pipeline(named: name) { _ = try runPipeline(p, input: q["input"]) }
                else { showToast("没有命令 \(name)") }
            } catch let e as RPCError { showToast(e.message) } catch {}
        default:
            showToast("不认识的链接：\(u.absoluteString)")
        }
    }
}
