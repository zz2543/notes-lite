import Foundation

/// Twain's socket speaks JSON-RPC 2.0, one message per line.
public enum RPC {
    /// Bumped when a request or result changes shape in a way old clients would misread.
    public static let protocolVersion = 1

    /// Where the app listens. Fixed and short: Unix socket paths are capped at 104 bytes.
    public static var defaultSocketPath: String {
        NSHomeDirectory() + "/Library/Application Support/Twain/run/twain.sock"
    }

    /// Splits a buffer into complete lines and leaves the trailing partial line in `buffer`.
    public static func drainLines(_ buffer: inout Data) -> [Data] {
        var out: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<nl])
            buffer.removeSubrange(buffer.startIndex...nl)
            if !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) { out.append(line) }
        }
        return out
    }
}

/// Who is calling: lets the app tie a request to the agent session that made it.
public struct RPCCaller: Codable, Equatable, Sendable {
    /// `TWAIN_SESSION` of the agent run that spawned the caller, when Twain started it.
    public var session: String?
    /// The caller's parent process (the agent's shell), for claiming terminal agents.
    public var pid: Int32?
    /// The vault the caller works in, found from its working directory.
    public var vault: String?

    public init(session: String? = nil, pid: Int32? = nil, vault: String? = nil) {
        self.session = session
        self.pid = pid
        self.vault = vault
    }
}

public struct RPCRequest: Codable, Equatable, Sendable {
    public var jsonrpc = "2.0"
    public var id: JSONValue?
    public var method: String
    public var params: [String: JSONValue]
    public var caller: RPCCaller?

    public init(id: JSONValue?, method: String, params: [String: JSONValue] = [:], caller: RPCCaller? = nil) {
        self.id = id
        self.method = method
        self.params = params
        self.caller = caller
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params, caller }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(JSONValue.self, forKey: .id)
        method = try c.decode(String.self, forKey: .method)
        params = try c.decodeIfPresent([String: JSONValue].self, forKey: .params) ?? [:]
        caller = try c.decodeIfPresent(RPCCaller.self, forKey: .caller)
    }
}

public struct RPCError: Error, Codable, Equatable, Sendable {
    public var code: Int
    public var message: String
    public var data: JSONValue?

    public init(_ code: Int, _ message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public static let parse = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
    /// The app has no vault open.
    public static let noVault = 1001
    /// The user declined what the command needed them to confirm.
    public static let declined = 1002
    /// The caller works in a different vault than the one open in the app.
    public static let otherVault = 1003
    /// The note, line or heading the command names does not exist.
    public static let notFound = 1004
    /// The command needs the app, which is not running.
    public static let appNotRunning = 1005
}

public struct RPCResponse: Codable, Equatable, Sendable {
    public var jsonrpc = "2.0"
    public var id: JSONValue?
    public var result: JSONValue?
    public var error: RPCError?

    public init(id: JSONValue?, result: JSONValue) {
        self.id = id
        self.result = result
    }

    public init(id: JSONValue?, error: RPCError) {
        self.id = id
        self.error = error
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, id, result, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(JSONValue.self, forKey: .id)
        error = try c.decodeIfPresent(RPCError.self, forKey: .error)
        // A present `"result": null` is a success with a null result.
        result = c.contains(.result) ? try c.decode(JSONValue.self, forKey: .result) : nil
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jsonrpc, forKey: .jsonrpc)
        try c.encode(id ?? .null, forKey: .id)
        if let error { try c.encode(error, forKey: .error) } else { try c.encode(result ?? .null, forKey: .result) }
    }
}

public extension RPCRequest {
    func line() -> Data { Self.encode(self) }
}

public extension RPCResponse {
    func line() -> Data { RPCRequest.encode(self) }
}

extension RPCRequest {
    static func encode<T: Encodable>(_ v: T) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var d = (try? e.encode(v)) ?? Data()
        d.append(0x0A)
        return d
    }
}
