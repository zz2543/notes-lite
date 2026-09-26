import Darwin
import Foundation

/// The small amount of BSD socket plumbing both ends of Plume's socket share.
public enum UnixSocket {
    public static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
            buf[bytes.count] = 0
        }
        return addr
    }

    /// A connected socket, or nil when nobody listens on `path`.
    public static func connect(_ path: String, timeout: TimeInterval = 30) -> Int32? {
        try? open(path, timeout: timeout).get()
    }

    /// A connected socket, or why none could be opened.
    static func open(_ path: String, timeout: TimeInterval) -> Result<Int32, CallError> {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(errno == EPERM || errno == EACCES ? .denied : .unreachable) }
        guard var addr = address(path) else { close(fd); return .failure(.unreachable) }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard r == 0 else {
            let err = errno
            close(fd)
            // A sandbox (Codex's, for one) answers EPERM; a missing app answers ENOENT or ECONNREFUSED.
            return .failure(err == EPERM || err == EACCES ? .denied : .unreachable)
        }
        noSigPipe(fd)
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        return .success(fd)
    }

    /// Writing to a closed peer must fail with EPIPE, not kill the process.
    public static func noSigPipe(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Writes all of `data`; false if the peer went away.
    @discardableResult
    public static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var off = 0
            while off < raw.count {
                let w = write(fd, raw.baseAddress! + off, raw.count - off)
                if w > 0 { off += w; continue }
                if w < 0, errno == EAGAIN || errno == EINTR { usleep(1000); continue }
                return false
            }
            return true
        }
    }

    public enum CallError: Error, Equatable {
        /// Nobody listens: the app is not running.
        case unreachable
        /// The caller may not open sockets, e.g. inside an agent's sandbox.
        case denied
        /// Connected, but the answer never came or made no sense.
        case broken(String)
    }

    /// Sends one request and hands every line that comes back to `onLine` until it returns false
    /// or the app closes the connection. `timeout` 0 waits forever.
    public static func stream(_ req: RPCRequest, path: String, timeout: TimeInterval = 0,
                              onLine: (Data) -> Bool) -> CallError? {
        let fd: Int32
        switch open(path, timeout: timeout) {
        case let .success(f): fd = f
        case let .failure(e): return e
        }
        defer { close(fd) }
        guard writeAll(fd, req.line()) else { return .broken("写入失败") }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return n == 0 ? nil : .broken("等待 Plume 超时") }
            buffer.append(contentsOf: chunk[0..<n])
            for line in RPC.drainLines(&buffer) where !onLine(line) { return nil }
        }
    }

    /// Sends one request and waits for its response.
    public static func call(_ req: RPCRequest, path: String, timeout: TimeInterval = 30) -> Result<RPCResponse, CallError> {
        let fd: Int32
        switch open(path, timeout: timeout) {
        case let .success(f): fd = f
        case let .failure(e): return .failure(e)
        }
        defer { close(fd) }
        guard writeAll(fd, req.line()) else { return .failure(.broken("写入失败")) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { return .failure(.broken(n == 0 ? "Plume 关闭了连接" : "等待 Plume 回应超时")) }
            buffer.append(contentsOf: chunk[0..<n])
            if let line = RPC.drainLines(&buffer).first {
                guard let resp = try? JSONDecoder().decode(RPCResponse.self, from: line) else { return .failure(.broken("无法解析 Plume 的回应")) }
                return .success(resp)
            }
        }
    }
}
