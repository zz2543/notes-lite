import Foundation

/// A JSON document both ends of the Plume socket can encode, compare and inspect.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case let .object(o) = self { return o[key] }
        return nil
    }

    public var string: String? { if case let .string(s) = self { return s }; return nil }
    public var bool: Bool? { if case let .bool(b) = self { return b }; return nil }
    public var int: Int? {
        switch self {
        case let .number(n) where n.rounded() == n: return Int(n)
        case let .string(s): return Int(s)
        default: return nil
        }
    }
    public var array: [JSONValue]? { if case let .array(a) = self { return a }; return nil }
    public var object: [String: JSONValue]? { if case let .object(o) = self { return o }; return nil }
    public var isNull: Bool { self == .null }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(arrayLiteral v: JSONValue...) { self = .array(v) }
    public init(dictionaryLiteral v: (String, JSONValue)...) { self = .object(Dictionary(v, uniquingKeysWith: { $1 })) }
}

public extension JSONValue {
    init(_ v: Int) { self = .number(Double(v)) }
    init(_ v: String?) { self = v.map(JSONValue.string) ?? .null }
    init(_ v: [String]) { self = .array(v.map(JSONValue.string)) }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n):
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int(n)) } else { try c.encode(n) }
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }
}

public extension JSONValue {
    /// Compact, key-sorted JSON on one line.
    func encoded(pretty: Bool = false) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(self)) ?? Data("null".utf8)
    }

    func text(pretty: Bool = false) -> String { String(decoding: encoded(pretty: pretty), as: UTF8.self) }
}
