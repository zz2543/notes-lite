import Foundation

/// Syntax colouring for one line of a fenced code block. Line by line on purpose: the editor
/// restyles single lines as they change, so a token never depends on lines above it, except
/// for the usual shape of block comments (`/*`, ` * `, ` */` at the start of a line).
public enum CodeHighlight {
    public enum Token: Equatable, Sendable { case keyword, string, comment, number, type, literal, tag, attribute }

    struct Grammar {
        var keywords: Set<String> = []
        var literals: Set<String> = ["true", "false", "null"]
        var lineComments: [String] = []
        var blockComment: (String, String)?
        var quotes: Set<unichar> = [0x22, 0x27]
        /// Capitalised identifiers read as types.
        var capsAreTypes = true
        var markup = false
        var caseInsensitive = false
    }

    static let cFamily = ["swift", "js", "javascript", "jsx", "ts", "typescript", "tsx", "java", "kotlin", "kt", "c", "h", "cpp", "c++",
                          "cc", "hpp", "objc", "objective-c", "m", "cs", "csharp", "c#", "go", "golang", "rust", "rs", "dart", "scala",
                          "php", "css", "scss", "less", "json", "jsonc", "groovy", "gradle", "zig"]

    static func grammar(_ lang: String) -> Grammar? {
        var g = Grammar()
        switch lang {
        case "swift":
            g.keywords = ["func", "let", "var", "if", "else", "guard", "return", "for", "in", "while", "repeat", "switch", "case", "default",
                          "break", "continue", "struct", "class", "enum", "protocol", "extension", "import", "init", "deinit", "self", "Self",
                          "static", "private", "fileprivate", "public", "internal", "open", "final", "override", "mutating", "throws",
                          "throw", "try", "catch", "do", "defer", "where", "as", "is", "some", "any", "async", "await", "actor",
                          "typealias", "associatedtype", "inout", "lazy", "weak", "unowned", "super", "subscript", "fallthrough", "rethrows"]
            g.literals = ["true", "false", "nil"]
        case "js", "javascript", "jsx", "ts", "typescript", "tsx", "mjs", "cjs":
            g.keywords = ["function", "const", "let", "var", "if", "else", "return", "for", "of", "in", "while", "do", "switch", "case",
                          "default", "break", "continue", "class", "extends", "new", "this", "super", "import", "export", "from", "as",
                          "async", "await", "try", "catch", "finally", "throw", "typeof", "instanceof", "delete", "void", "yield",
                          "static", "get", "set", "interface", "type", "enum", "implements", "private", "public", "protected",
                          "readonly", "declare", "namespace", "abstract", "keyof", "satisfies"]
            g.literals = ["true", "false", "null", "undefined", "NaN", "Infinity"]
            g.quotes.insert(0x60)
        case "java", "kotlin", "kt", "scala", "groovy", "gradle", "dart":
            g.keywords = ["public", "private", "protected", "class", "interface", "enum", "extends", "implements", "static", "final",
                          "void", "int", "long", "double", "float", "boolean", "char", "byte", "short", "if", "else", "for", "while", "do",
                          "switch", "case", "default", "break", "continue", "return", "new", "this", "super", "import", "package",
                          "try", "catch", "finally", "throw", "throws", "abstract", "synchronized", "volatile", "transient", "var",
                          "val", "fun", "object", "when", "is", "in", "as", "data", "sealed", "override", "open", "lateinit", "suspend",
                          "def", "trait", "match", "yield", "lazy", "implicit", "record", "async", "await", "late", "required"]
            g.literals = ["true", "false", "null"]
        case "c", "h", "cpp", "c++", "cc", "hpp", "objc", "objective-c", "m", "cs", "csharp", "c#", "zig":
            g.keywords = ["int", "long", "short", "char", "float", "double", "void", "unsigned", "signed", "const", "static", "extern",
                          "struct", "union", "enum", "typedef", "sizeof", "if", "else", "for", "while", "do", "switch", "case", "default",
                          "break", "continue", "return", "goto", "auto", "register", "volatile", "inline", "class", "public", "private",
                          "protected", "virtual", "override", "template", "typename", "namespace", "using", "new", "delete", "this",
                          "operator", "friend", "try", "catch", "throw", "bool", "constexpr", "nullptr", "noexcept", "static_cast",
                          "dynamic_cast", "reinterpret_cast", "include", "define", "ifdef", "ifndef", "endif", "pragma", "import",
                          "interface", "implementation", "end", "property", "self", "string", "var", "readonly", "async", "await",
                          "foreach", "in", "out", "ref", "fn", "pub", "comptime"]
            g.literals = ["true", "false", "NULL", "nullptr", "nil", "YES", "NO", "null"]
        case "go", "golang":
            g.keywords = ["func", "package", "import", "var", "const", "type", "struct", "interface", "map", "chan", "if", "else", "for",
                          "range", "switch", "case", "default", "break", "continue", "return", "go", "defer", "select", "fallthrough",
                          "goto", "string", "int", "int64", "int32", "uint", "byte", "rune", "float64", "bool", "error", "make", "new",
                          "len", "cap", "append"]
            g.literals = ["true", "false", "nil", "iota"]
            g.quotes.insert(0x60)
            g.capsAreTypes = false
        case "rust", "rs":
            g.keywords = ["fn", "let", "mut", "const", "static", "if", "else", "match", "for", "in", "while", "loop", "break", "continue",
                          "return", "struct", "enum", "impl", "trait", "type", "use", "mod", "pub", "crate", "self", "Self", "super",
                          "where", "as", "ref", "move", "async", "await", "dyn", "unsafe", "extern", "i32", "i64", "u8", "u32", "u64",
                          "usize", "f32", "f64", "bool", "str", "String", "Vec", "Option", "Result", "Some", "None", "Ok", "Err"]
            g.literals = ["true", "false"]
            g.quotes = [0x22]
        case "php":
            g.keywords = ["function", "class", "public", "private", "protected", "static", "return", "if", "else", "elseif", "foreach",
                          "for", "while", "as", "new", "echo", "use", "namespace", "extends", "implements", "try", "catch", "throw",
                          "array", "fn", "match", "require", "include"]
            g.lineComments = ["#"]
        case "css", "scss", "less":
            g.keywords = ["important", "media", "import", "keyframes", "font-face", "supports", "root", "hover", "before", "after"]
            g.literals = []
            g.capsAreTypes = false
        case "json", "jsonc", "json5":
            g.literals = ["true", "false", "null"]
            g.quotes = [0x22]
            g.capsAreTypes = false
        case "python", "py", "python3":
            g.keywords = ["def", "class", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is", "import",
                          "from", "as", "with", "try", "except", "finally", "raise", "pass", "break", "continue", "lambda", "yield",
                          "global", "nonlocal", "assert", "del", "async", "await", "self", "print", "match", "case"]
            g.literals = ["True", "False", "None"]
            g.lineComments = ["#"]
        case "ruby", "rb":
            g.keywords = ["def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until", "for", "in", "do", "return",
                          "yield", "begin", "rescue", "ensure", "raise", "require", "include", "extend", "attr_accessor", "self",
                          "then", "case", "when", "and", "or", "not", "puts", "lambda", "proc"]
            g.literals = ["true", "false", "nil"]
            g.lineComments = ["#"]
        case "sh", "bash", "zsh", "shell", "fish", "console", "shellscript", "powershell", "ps1", "dockerfile", "docker", "makefile", "make":
            g.keywords = ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in", "function",
                          "return", "export", "local", "readonly", "set", "unset", "echo", "cd", "source", "exit", "sudo", "alias",
                          "FROM", "RUN", "CMD", "COPY", "ADD", "WORKDIR", "ENV", "EXPOSE", "ENTRYPOINT", "ARG", "LABEL", "VOLUME", "USER"]
            g.literals = ["true", "false"]
            g.lineComments = ["#"]
            g.quotes.insert(0x60)
            g.capsAreTypes = false
        case "yaml", "yml", "toml", "ini", "conf", "properties", "env":
            g.literals = ["true", "false", "null", "yes", "no", "on", "off", "~"]
            g.lineComments = ["#", ";"]
            g.capsAreTypes = false
        case "r":
            g.keywords = ["function", "if", "else", "for", "while", "repeat", "in", "next", "break", "return", "library", "require"]
            g.literals = ["TRUE", "FALSE", "NULL", "NA", "Inf", "NaN"]
            g.lineComments = ["#"]
            g.capsAreTypes = false
        case "perl", "pl":
            g.keywords = ["my", "our", "sub", "if", "elsif", "else", "unless", "while", "for", "foreach", "return", "use", "package"]
            g.lineComments = ["#"]
        case "sql", "mysql", "postgresql", "postgres", "sqlite", "plsql":
            g.keywords = ["select", "from", "where", "and", "or", "not", "insert", "into", "values", "update", "set", "delete", "create",
                          "table", "index", "view", "drop", "alter", "add", "join", "left", "right", "inner", "outer", "on", "group",
                          "by", "order", "having", "limit", "offset", "as", "distinct", "union", "all", "case", "when", "then", "else",
                          "end", "primary", "key", "foreign", "references", "default", "unique", "in", "is", "like", "between",
                          "exists", "count", "sum", "avg", "min", "max", "with", "int", "integer", "varchar", "text", "boolean",
                          "date", "timestamp", "begin", "commit", "rollback", "asc", "desc"]
            g.literals = ["null", "true", "false"]
            g.lineComments = ["--"]
            g.caseInsensitive = true
            g.capsAreTypes = false
        case "lua":
            g.keywords = ["function", "local", "if", "then", "elseif", "else", "end", "for", "in", "do", "while", "repeat", "until",
                          "return", "break", "and", "or", "not"]
            g.literals = ["true", "false", "nil"]
            g.lineComments = ["--"]
        case "haskell", "hs", "elm":
            g.keywords = ["module", "import", "where", "let", "in", "case", "of", "if", "then", "else", "data", "type", "class",
                          "instance", "deriving", "do", "newtype"]
            g.literals = ["True", "False"]
            g.lineComments = ["--"]
        case "matlab", "octave", "tex", "latex":
            g.keywords = ["function", "end", "if", "else", "elseif", "for", "while", "return", "switch", "case",
                          "begin", "documentclass", "usepackage", "section", "subsection", "label", "ref", "cite"]
            g.lineComments = ["%"]
            g.capsAreTypes = false
        case "html", "xml", "svg", "xhtml", "vue", "plist", "markup":
            g.markup = true
            g.capsAreTypes = false
            return g
        case "diff", "patch", "text", "txt", "plain", "plaintext", "markdown", "md", "mermaid", "":
            return nil
        default:
            // Something code-like: strings, numbers and both common comment styles.
            g.lineComments = ["//", "#"]
            g.blockComment = ("/*", "*/")
            g.capsAreTypes = false
            return g
        }
        if cFamily.contains(lang) {
            g.lineComments.insert("//", at: 0)
            g.blockComment = ("/*", "*/")
        }
        if ["css", "scss", "less"].contains(lang) { g.lineComments = lang == "css" ? [] : ["//"] }
        return g
    }

    /// Tokens of `line` in `language` (a fence's info string, lowercased). Empty for plain text.
    public static func tokens(_ line: String, language: String) -> [(range: NSRange, token: Token)] {
        guard !line.isEmpty, let g = grammar(language) else { return [] }
        let ns = line as NSString
        let n = ns.length
        var c = [unichar](repeating: 0, count: n)
        ns.getCharacters(&c, range: NSRange(location: 0, length: n))
        if g.markup { return markup(c) }
        var out: [(NSRange, Token)] = []

        func starts(_ s: String, at i: Int) -> Bool {
            let u = Array(s.utf16)
            guard i + u.count <= n else { return false }
            for k in 0..<u.count where c[i + k] != u[k] { return false }
            return true
        }
        func find(_ s: String, from i: Int) -> Int? {
            var j = i
            while j < n { if starts(s, at: j) { return j }; j += 1 }
            return nil
        }
        var i = 0
        while i < n, c[i] == 0x20 || c[i] == 0x09 { i += 1 }
        // The inside of a block comment spanning lines: ` * text` or `*/`.
        if g.blockComment != nil, i < n, c[i] == 0x2A, i + 1 >= n || c[i + 1] == 0x20 || c[i + 1] == 0x2F {
            return [(NSRange(location: i, length: n - i), .comment)]
        }
        func isIdentStart(_ u: unichar) -> Bool { (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A) || u == 0x5F || u == 0x40 || u == 0x24 }
        func isIdent(_ u: unichar) -> Bool { isIdentStart(u) || (u >= 0x30 && u <= 0x39) || u == 0x2D && language.hasPrefix("css") }
        let lowerKeywords = g.caseInsensitive ? Set(g.keywords.map { $0.lowercased() }) : g.keywords
        while i < n {
            let u = c[i]
            if let bc = g.blockComment, starts(bc.0, at: i) {
                let end = find(bc.1, from: i + bc.0.utf16.count).map { $0 + bc.1.utf16.count } ?? n
                out.append((NSRange(location: i, length: end - i), .comment))
                i = end
                continue
            }
            if let lc = g.lineComments.first(where: { starts($0, at: i) }) {
                // `#` only comments at a word boundary (not in `a#b` or `#include`-style C lines).
                if lc != "#" || i == 0 || c[i - 1] == 0x20 || c[i - 1] == 0x09 {
                    out.append((NSRange(location: i, length: n - i), .comment))
                    break
                }
            }
            if g.quotes.contains(u) {
                var j = i + 1
                while j < n, c[j] != u { j += c[j] == 0x5C ? 2 : 1 }
                let end = min(n, j + 1)
                out.append((NSRange(location: i, length: end - i), .string))
                i = end
                continue
            }
            if u >= 0x30 && u <= 0x39, i == 0 || !isIdent(c[i - 1]) {
                var j = i + 1
                while j < n, isIdent(c[j]) || c[j] == 0x2E { j += 1 }
                out.append((NSRange(location: i, length: j - i), .number))
                i = j
                continue
            }
            if isIdentStart(u) {
                var j = i + 1
                while j < n, isIdent(c[j]) { j += 1 }
                let word = String(utf16CodeUnits: Array(c[i..<j]), count: j - i)
                let key = g.caseInsensitive ? word.lowercased() : word
                if u == 0x40, j - i > 1 {
                    out.append((NSRange(location: i, length: j - i), .attribute))
                } else if lowerKeywords.contains(key) {
                    out.append((NSRange(location: i, length: j - i), .keyword))
                } else if g.literals.contains(word) {
                    out.append((NSRange(location: i, length: j - i), .literal))
                } else if g.capsAreTypes, u >= 0x41, u <= 0x5A, j - i > 1 {
                    out.append((NSRange(location: i, length: j - i), .type))
                }
                i = j
                continue
            }
            i += 1
        }
        return out
    }

    /// HTML and XML: tag names, attribute names, quoted values, comments.
    static func markup(_ c: [unichar]) -> [(range: NSRange, token: Token)] {
        let n = c.count
        var out: [(NSRange, Token)] = []
        var i = 0
        while i < n {
            if c[i] == 0x3C, i + 3 < n, c[i + 1] == 0x21, c[i + 2] == 0x2D, c[i + 3] == 0x2D {   // <!--
                var j = i + 4
                while j + 2 < n, !(c[j] == 0x2D && c[j + 1] == 0x2D && c[j + 2] == 0x3E) { j += 1 }
                let end = min(n, j + 3)
                out.append((NSRange(location: i, length: end - i), .comment))
                i = end
                continue
            }
            if c[i] == 0x3C {   // <
                var j = i + 1
                if j < n, c[j] == 0x2F || c[j] == 0x3F || c[j] == 0x21 { j += 1 }
                let nameStart = j
                while j < n, c[j] != 0x20, c[j] != 0x3E, c[j] != 0x2F, c[j] != 0x09 { j += 1 }
                if j > nameStart { out.append((NSRange(location: nameStart, length: j - nameStart), .tag)) }
                // Attributes up to the closing >.
                while j < n, c[j] != 0x3E {
                    if c[j] == 0x22 || c[j] == 0x27 {
                        let q = c[j]
                        var k = j + 1
                        while k < n, c[k] != q { k += 1 }
                        let end = min(n, k + 1)
                        out.append((NSRange(location: j, length: end - j), .string))
                        j = end
                        continue
                    }
                    if c[j] != 0x20, c[j] != 0x3D, c[j] != 0x2F, c[j] != 0x09 {
                        let a = j
                        while j < n, c[j] != 0x20, c[j] != 0x3D, c[j] != 0x3E, c[j] != 0x2F { j += 1 }
                        out.append((NSRange(location: a, length: j - a), .attribute))
                        continue
                    }
                    j += 1
                }
                i = j + 1
                continue
            }
            i += 1
        }
        return out
    }
}
