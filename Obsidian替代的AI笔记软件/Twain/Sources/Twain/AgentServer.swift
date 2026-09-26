import Darwin
import Foundation
import TwainCore

/// Listens on a Unix socket for `twain` commands: one JSON-RPC request per line. Requests run on
/// the main thread, like the user's own actions, and may answer later (a question waits for the
/// user); a connection can also carry events the app pushes (`twain watch`).
final class AgentServer {
    typealias Reply = (RPCResponse) -> Void
    /// Called on the main thread. `reply` may be called later, once.
    typealias Handler = (RPCRequest, Connection, @escaping Reply) -> Void

    /// One client. Safe to use from the main thread; writes happen on the server's queue.
    final class Connection {
        fileprivate let fd: Int32
        fileprivate var buffer = Data()
        fileprivate var source: DispatchSourceRead?
        fileprivate weak var server: AgentServer?
        /// Main-thread callbacks for when the client goes away.
        private var closeHandlers: [() -> Void] = []
        private(set) var closed = false

        fileprivate init(fd: Int32, server: AgentServer) {
            self.fd = fd
            self.server = server
        }

        func send(_ data: Data) {
            server?.queue.async { [self] in
                guard !closed else { return }
                UnixSocket.writeAll(fd, data)
            }
        }

        /// Runs `f` on the main thread when the connection closes (at once if it already has).
        func onClose(_ f: @escaping () -> Void) {
            if closed { f() } else { closeHandlers.append(f) }
        }

        fileprivate func didClose() {
            closed = true
            let handlers = closeHandlers
            closeHandlers.removeAll()
            handlers.forEach { $0() }
        }
    }

    let path: String
    private let handler: Handler
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Connection] = [:]
    fileprivate let queue = DispatchQueue(label: "twain.server")

    init(path: String = RPC.defaultSocketPath, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    /// False when another Twain already answers on the socket, or the socket can't be made.
    @discardableResult
    func start() -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if Self.isAlive(path) { return false }
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        guard var addr = UnixSocket.address(path) else { close(fd); return false }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return false }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        listenFD = fd

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptAll() }
        src.resume()
        acceptSource = src
        return true
    }

    func stop() {
        // Never wait on `queue` here: it may be busy writing to a slow client.
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 { close(listenFD); listenFD = -1; unlink(path) }
        queue.async { [self] in
            for c in clients.values { drop(c) }
        }
    }

    private func acceptAll() {
        while true {
            let cfd = accept(listenFD, nil, nil)
            guard cfd >= 0 else { return }
            UnixSocket.noSigPipe(cfd)
            let c = Connection(fd: cfd, server: self)
            let src = DispatchSource.makeReadSource(fileDescriptor: cfd, queue: queue)
            src.setEventHandler { [weak self, weak c] in
                guard let self, let c else { return }
                self.read(c)
            }
            src.setCancelHandler { close(cfd) }
            c.source = src
            clients[cfd] = c
            src.resume()
        }
    }

    private func drop(_ c: Connection) {
        guard clients[c.fd] != nil else { return }
        clients[c.fd] = nil
        c.source?.cancel()
        DispatchQueue.main.async { c.didClose() }
    }

    private func read(_ c: Connection) {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let n = Darwin.read(c.fd, &chunk, chunk.count)
        guard n > 0 else { drop(c); return }
        c.buffer.append(contentsOf: chunk[0..<n])
        if c.buffer.count > 8 * 1024 * 1024 {
            UnixSocket.writeAll(c.fd, RPCResponse(id: nil, error: RPCError(RPCError.invalidRequest, "请求过大")).line())
            drop(c)
            return
        }
        for line in RPC.drainLines(&c.buffer) {
            guard let req = try? JSONDecoder().decode(RPCRequest.self, from: line) else {
                UnixSocket.writeAll(c.fd, RPCResponse(id: nil, error: RPCError(RPCError.parse, "不是合法的 JSON-RPC 请求")).line())
                continue
            }
            let handler = self.handler
            DispatchQueue.main.async {
                var answered = false
                handler(req, c) { resp in
                    // Notifications (no id) get no answer, and nothing is answered twice.
                    guard !answered, req.id != nil else { return }
                    answered = true
                    c.send(resp.line())
                }
            }
        }
    }

    /// Whether something accepts connections on `path` right now.
    static func isAlive(_ path: String) -> Bool {
        guard let fd = UnixSocket.connect(path, timeout: 1) else { return false }
        close(fd)
        return true
    }
}

extension AppModel {
    /// Runs one socket request. Every failure becomes a JSON-RPC error, never a crash.
    func handle(_ req: RPCRequest, connection: AgentServer.Connection, reply: @escaping AgentServer.Reply) {
        guard let cmd = CommandRegistry.command(req.method, in: self), cmd.agents else {
            reply(RPCResponse(id: req.id, error: RPCError(RPCError.methodNotFound, "没有命令 \(req.method)，运行 twain commands 查看全部")))
            return
        }
        do {
            try cmd.spec.validate(req.params)
            if let want = req.caller?.vault, let v = vault, !Self.samePath(want, v.rootPath) {
                throw RPCError(RPCError.otherVault, "共笔当前打开的是 \(v.displayPath)，不是 \(want)",
                               data: ["open": .string(v.rootPath)])
            }
            let call = CommandCall(params: req.params, caller: req.caller, session: session(for: req.caller), connection: connection)
            cmd.perform(self, call) { result in
                switch result {
                case let .success(v): reply(RPCResponse(id: req.id, result: v))
                case let .failure(e): reply(RPCResponse(id: req.id, error: e))
                }
            }
        } catch let e as RPCError {
            reply(RPCResponse(id: req.id, error: e))
        } catch {
            reply(RPCResponse(id: req.id, error: RPCError(RPCError.internalError, error.localizedDescription)))
        }
    }

    /// The agent session a caller belongs to: the one whose id it carries (runs Twain started),
    /// else the terminal session whose process it runs under.
    func session(for caller: RPCCaller?) -> AgentSession? {
        if let id = caller?.session, let s = sessions.first(where: { $0.id.uuidString == id }) { return s }
        guard let pid = caller?.pid else { return nil }
        return sessions.first { s in
            guard s.source == .terminal, let spid = s.pid else { return false }
            return spid == pid || TerminalWatcher.isDescendant(pid, of: spid)
        }
    }

    static func samePath(_ a: String, _ b: String) -> Bool {
        func norm(_ p: String) -> String { URL(fileURLWithPath: p).standardizedFileURL.resolvingSymlinksInPath().path }
        return norm(a) == norm(b)
    }

    func startServer() {
        guard server == nil else { return }
        TwainTool.prepare()
        var path = RPC.defaultSocketPath
        #if DEBUG
        // Test runs listen elsewhere so they never take over a Twain the user has open.
        if let p = ProcessInfo.processInfo.environment["TWAIN_SOCK"] { path = p }
        #endif
        let s = AgentServer(path: path) { [weak self] req, conn, reply in
            guard let self else {
                reply(RPCResponse(id: req.id, error: RPCError(RPCError.noVault, "共笔正在退出")))
                return
            }
            self.handle(req, connection: conn, reply: reply)
        }
        if s.start() { server = s }
    }
}
