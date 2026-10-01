import AppKit
import Observation
import SwiftUI
import TwainCore

// The app's state, by the part of the window it belongs to. AppModel owns one of each and
// coordinates them; a view reads the part it shows. Reactions that involve more than one
// part (a new selection opens a note; a new editor version recounts words) go through the
// callbacks AppModel sets, so each part stays a plain record of its own state.

/// The user's settings, saved to UserDefaults as they change.
@MainActor @Observable
final class Preferences {
    enum Change { case ghost, syncContext, watchTerminal, http }
    /// Settings whose change has to do something beyond being saved.
    @ObservationIgnored var changed: ((Change) -> Void)?
    @ObservationIgnored private let store: UserDefaults

    var font: EditorFont { didSet { save("font", font.rawValue) } }
    var typewriter: Bool { didSet { save("typewriter", typewriter) } }
    var dim: Bool { didSet { save("dim", dim) } }
    /// How pasted pictures are named (`Attachments.swift`).
    var attachmentNaming: AttachmentNaming { didSet { save("attachmentName", attachmentNaming.rawValue) } }
    var ghostOn: Bool { didSet { save("ghostOn", ghostOn); changed?(.ghost) } }
    var syncContext: Bool { didSet { save("syncCtx", syncContext); changed?(.syncContext) } }
    var watchTerminal: Bool { didSet { save("watchExt", watchTerminal); changed?(.watchTerminal) } }
    var gitSnapshot: Bool { didSet { save("snapshot", gitSnapshot) } }
    var reviewMode: ReviewMode { didSet { save("review", reviewMode.rawValue) } }
    var claudeOn: Bool { didSet { save("claudeOn", claudeOn) } }
    var codexOn: Bool { didSet { save("codexOn", codexOn) } }
    /// Give runs Twain's MCP tools (propose_edit, ask_user, …) besides the `twain` command.
    var mcpOn: Bool { didSet { save("mcpOn", mcpOn) } }
    /// Master switch for `.twain/automations/`.
    var automationsOn: Bool { didSet { save("automationsOn", automationsOn) } }
    var automationDailyLimit: Int { didSet { save("automationLimit", automationDailyLimit) } }
    /// AI summaries a day at most (each is one note in a batched call to a small model).
    var summaryDailyLimit: Int { didSet { save("summaryLimit", summaryDailyLimit) } }
    /// The writing companion (`Companion.swift`): off unless the user turns it on.
    var companionOn: Bool { didSet { save("companion", companionOn) } }
    /// Local HTTP API for other apps (`HTTPGateway.swift`).
    var httpOn: Bool { didSet { save("httpOn", httpOn); if oldValue != httpOn { changed?(.http) } } }
    var httpPort: UInt16 { didSet { save("httpPort", Int(httpPort)) } }
    /// Model per agent; "" means whatever the CLI is configured to use.
    var agentModel: [AgentKind: String] {
        didSet { for k in AgentKind.allCases { save("model." + k.rawValue, agentModel[k] ?? "") } }
    }
    /// Thinking level per agent; "" means the CLI's own default for the chosen model.
    var agentEffort: [AgentKind: String] {
        didSet { for k in AgentKind.allCases { save("effort." + k.rawValue, agentEffort[k] ?? "") } }
    }
    var editorWidth: CGFloat = 680
    /// How much the app moves (Motion.swift).
    var motionStyle: MotionStyle { didSet { save("motion", motionStyle.rawValue); Motion.style = motionStyle } }
    /// Short sounds when something is finished.
    var motionSound: Bool { didSet { save("motionSound", motionSound); Motion.sound = motionSound } }

    /// Reads every setting (assignments in init neither save nor notify).
    init(store: UserDefaults = .standard) {
        self.store = store
        func b(_ k: String, _ d: Bool) -> Bool { store.object(forKey: "pref." + k) as? Bool ?? d }
        font = EditorFont(rawValue: store.string(forKey: "pref.font") ?? "") ?? .serif
        typewriter = b("typewriter", true)
        dim = b("dim", true)
        attachmentNaming = AttachmentNaming(rawValue: store.string(forKey: "pref.attachmentName") ?? "") ?? .pasted
        ghostOn = b("ghostOn", false)
        syncContext = b("syncCtx", true)
        watchTerminal = b("watchExt", true)
        gitSnapshot = b("snapshot", true)
        reviewMode = ReviewMode(rawValue: store.string(forKey: "pref.review") ?? "") ?? .queue
        claudeOn = b("claudeOn", true)
        codexOn = b("codexOn", true)
        mcpOn = b("mcpOn", true)
        automationsOn = b("automationsOn", true)
        automationDailyLimit = store.object(forKey: "pref.automationLimit") as? Int ?? 20
        summaryDailyLimit = store.object(forKey: "pref.summaryLimit") as? Int ?? 100
        companionOn = b("companion", false)
        httpOn = b("httpOn", true)
        httpPort = UInt16(store.object(forKey: "pref.httpPort") as? Int ?? Int(HTTPGateway.defaultPort))
        agentModel = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, store.string(forKey: "pref.model." + $0.rawValue) ?? "") })
        agentEffort = Dictionary(uniqueKeysWithValues: AgentKind.allCases.map { ($0, store.string(forKey: "pref.effort." + $0.rawValue) ?? "") })
        motionStyle = MotionStyle(rawValue: store.string(forKey: "pref.motion") ?? "") ?? .calm
        motionSound = b("motionSound", false)
        Motion.style = motionStyle
        #if DEBUG
        // TWAIN_MOTION=lively|calm|minimal: a run in that style without touching the saved setting.
        if let raw = ProcessInfo.processInfo.environment["TWAIN_MOTION"], let st = MotionStyle(rawValue: raw) { Motion.style = st }
        #endif
        Motion.sound = motionSound
    }

    private func save(_ key: String, _ value: Any) { store.set(value, forKey: "pref." + key) }
}

/// The window around the page: which columns show, what floats above them, what the sidebar selects.
@MainActor @Observable
final class ChromeState {
    var columnVisibility: NavigationSplitViewVisibility = .all
    var agentPanel = true
    var modelPickerOpen = false
    var zen = false
    var palette = false
    var paletteQuery = ""
    var paletteSel = 0
    /// Where the palette grows from: under the toolbar's search button when that was clicked.
    var paletteAnchor: UnitPoint = .top
    var settingsTab: SettingsTab = .editor
    var sidebarFilter = ""
    /// The sidebar row whose name is being edited in place.
    var renaming: String?
    /// Sidebar list selection; choosing a row opens it (AppModel.select).
    var selection: String? { didSet { if let s = selection, s != oldValue { selected?(s) } } }
    @ObservationIgnored var selected: ((String) -> Void)?
    var onboardingStep: Int?
    /// The newest message, kept for the RPC replies that report it.
    var toast: String?
    /// Messages still on screen, newest first; several arriving together stack up.
    var toasts: [ToastItem] = []
    /// The pointer is over the stack: keep it until the pointer leaves.
    var toastHeld = false
    var openFolders: Set<String> = []
    var noteInfoOpen = false
    /// Where the click that opened a grow panel landed (window coordinates); nil from the keyboard.
    var panelOrigin: WindowPoint?
    var newSpaceSheet = false
    /// The sidebar's 「+」 has grown into its panel.
    var newMenuOpen = false
    /// 活泼: the space whose cover is swinging open over its page (`SpaceCover`).
    var spaceCover: String?
    /// The space shown in place of a note (`Spaces.swift`).
    var activeSpace: String?
    /// The 问库 desk shown in place of a note (`ResearchDesk.swift`).
    var openDesk: String?
}

/// The open note and what the editor shows around it.
@MainActor @Observable
final class EditorState {
    var activeRel: String?
    /// The open note's text. While the user types, the editor owns it: a keystroke only marks
    /// this stale, and the text is copied out of the editor when someone reads it (a save, an
    /// agent's `context`, the word count after a pause), never once per key. Not observed: the
    /// editor redraws on `editorVersion`, which changes whenever the model replaces the text.
    var editorText: String {
        get {
            if stale, let text = live?() {
                stored = text
                stale = false
            }
            return stored
        }
        set {
            stored = newValue
            stale = false
        }
    }
    @ObservationIgnored private var stored = ""
    @ObservationIgnored private var stale = false
    /// Reads the editor's current text; set by the editor.
    @ObservationIgnored var live: (() -> String?)?

    /// The user changed the text in the editor; it is read from there when next needed.
    func textEdited() { stale = true }

    /// Bumped whenever the model replaces the editor's text (note switch, disk reload).
    var editorVersion = 0 { didSet { versionChanged?() } }
    @ObservationIgnored var versionChanged: (() -> Void)?
    var dirty = false
    var focusRequest: (caret: Int, token: Int)?
    /// The editor's selection (UTF-16), read by agents through `twain context`. Not observed:
    /// nothing on screen depends on it.
    @ObservationIgnored var editorSelection = NSRange(location: 0, length: 0) {
        didSet { if editorSelection != oldValue { selectionChanged?() } }
    }
    @ObservationIgnored var selectionChanged: (() -> Void)?
    var ghost = ""
    var slash: SlashState?
    /// Annotations on the open note (`Annotations.swift`).
    var annotations: [Annotation] = []
    var selectedAnnotation: String?
    var showDiff = false
    /// HTML notes show their source in the editor instead of the rendered page.
    var htmlSource = false
    /// Why the open file can't be shown as text (binary, far too large); nil when it can.
    var unreadable: String?
    /// The open note while iCloud downloads it.
    var downloading: String?
    /// The open note has a line too long to typeset and edit smoothly: it is shown as plain,
    /// read-only text instead of risking a hang in the text system.
    var oversized = false { didSet { if !oversized { oversizedDisplay = nil } } }
    /// What the editor shows for an oversized note: the text with its huge lines clipped, since
    /// TextKit cannot typeset a paragraph of millions of characters. The file is never written from it.
    @ObservationIgnored var oversizedDisplay: String?
    /// Words in the open note, recounted a moment after typing stops rather than on every key.
    var wordCount = 0
    /// The open note's headings, refreshed with the word count once typing pauses.
    var outline: [OutlineEntry] = []
    /// The heading whose section is at the top of the page.
    var outlineCurrent = 0
    @ObservationIgnored var typed: [(Date, Int)] = []
    @ObservationIgnored var netTyped = 0
    var companionTip: CompanionTip?
    var companionThinking = false
}

/// Agents: the CLIs found, the conversations, and what they left for the user to decide.
@MainActor @Observable
final class AgentState {
    var cli: [AgentKind: CLIInfo] = [:]
    var sessions: [AgentSession] = []
    var activeSessionID: UUID?
    var agentInput = ""
    var agentPick: AgentKind = .claude
    var modelChoices: [AgentKind: [AgentModel]] = [:]
    /// What each CLI runs when Twain passes no model, when we can tell.
    var modelFallback: [AgentKind: String] = [:]
    var effortFallback: [AgentKind: String] = [:]
    var modelsListedBy: [AgentKind: String] = [:]
    var pending: [String: PendingReview] = [:] { didSet { pendingChanged?() } }
    @ObservationIgnored var pendingChanged: (() -> Void)?
    /// Questions agents asked, by id; answered ones stay so the transcript can show the answer.
    var questions: [UUID: AgentQuestion] = [:]
    /// The vault's pipelines (`.twain/pipelines/`) and the runs in progress (`Pipelines.swift`).
    var pipelines: [Pipeline] = []
    var pipelineRuns: [UUID: PipelineRun] = [:]
    /// Notes an agent is writing right now.
    var writing: Set<String> = []
}

/// One message in the toast stack.
struct ToastItem: Identifiable, Equatable {
    enum Kind { case done, problem, info }
    let id = UUID()
    let text: String
    let kind: Kind

    init(_ text: String) {
        self.text = text
        let problem = ["没能", "没有找到", "找不到", "失败", "作废", "停用", "上限", "不认识", "没有命令", "还在运行", "还在找", "已经结束", "请选择", "稍后再"]
        if problem.contains(where: text.contains) { kind = .problem }
        else if text.hasPrefix("已") || text.contains("完成") || text.contains(" 已") { kind = .done }
        else { kind = .info }
    }
}
