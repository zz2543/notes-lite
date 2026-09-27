import Foundation

/// A collaboration pipeline, `.twain/pipelines/<key>.md`: several steps run by one agent in one
/// session, with a gate after each where the user decides before the next begins. Long work
/// arrives in reviewable pieces instead of one wall of text.
///
/// ```markdown
/// ---
/// title: 研究并写成文章
/// agent: claude
/// scope: vault
/// ---
/// ## 调研
/// gate: ask
/// 围绕 {{input}} 先 skim 再 read_note，列出要点和出处。
///
/// ## 大纲
/// gate: review
/// model: sonnet
/// 根据上一步的要点写大纲，用 propose_edit 新建 写作/{{input}}.md。
/// ```
public struct Pipeline: Equatable, Sendable {
    public enum Gate: String, Sendable {
        /// Wait until every change the step proposed has been reviewed.
        case review
        /// Wait for the user to continue, redo the step with feedback, or stop.
        case ask
        case none
    }

    public struct Step: Equatable, Sendable {
        public var title: String
        public var gate: Gate
        public var model: String?
        public var effort: String?
        public var prompt: String
    }

    public var key: String
    public var title: String
    public var agent: AgentKind
    public var model: String?
    public var scope: UserCommand.Scope
    public var icon: String
    public var steps: [Step]
    public var file: String
    /// Optional MCP tools the run gets (`annotate`, `cards`).
    public var tools: [String] = []

    /// Whether starting it needs the user to type something first (`{{input}}`).
    public var needsInput: Bool { steps.contains { Template.uses($0.prompt, "input") } }

    static let optionRe = try! NSRegularExpression(pattern: #"^(gate|model|effort)\s*[:：]\s*(\S.*)$"#)

    public static func parse(file: String, text: String) -> Pipeline? {
        let (f, body) = Frontmatter.split(text)
        let stem = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let agent = AgentKind(rawValue: (f["agent"] ?? "claude").lowercased()) else { return nil }
        var steps: [Step] = []
        var current: Step?
        var readingOptions = false
        func close() {
            if var c = current {
                c.prompt = c.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !c.prompt.isEmpty { steps.append(c) }
            }
        }
        for line in body.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                close()
                let title = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                current = Step(title: title, gate: .review, model: nil, effort: nil, prompt: "")
                readingOptions = true
                continue
            }
            guard current != nil else { continue }
            let ns = line as NSString
            if readingOptions, let m = optionRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let k = ns.substring(with: m.range(at: 1)), v = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
                switch k {
                case "gate": current?.gate = Gate(rawValue: v.lowercased()) ?? .review
                case "model": current?.model = v
                default: current?.effort = v
                }
                continue
            }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { readingOptions = false }
            current?.prompt += line + "\n"
        }
        close()
        guard !steps.isEmpty else { return nil }
        let key = (f["key"] ?? stem).trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return Pipeline(key: key.isEmpty ? stem : key, title: f["title"] ?? stem, agent: agent,
                        model: f["model"].flatMap { $0.isEmpty ? nil : $0 },
                        scope: UserCommand.Scope(rawValue: f["scope"] ?? "") ?? .note,
                        icon: f["icon"] ?? "arrow.triangle.branch", steps: steps, file: file,
                        tools: (f["tools"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
