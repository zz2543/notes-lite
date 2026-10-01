import TwainCore
import SwiftUI

/// The single document window: floating glass sidebar, the page, and the Agent inspector.
struct MainWindow: View {
    @Bindable var model: AppModel
    static let minWidth: CGFloat = 920
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView(columnVisibility: Bindable(model.chrome).columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            NoteDetail(model: model)
                .inspector(isPresented: Bindable(model.chrome).agentPanel) {
                    FixedHost(content: AgentInspector(model: model))
                        .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
                }
        }
        .toolbar(model.chrome.zen ? .hidden : .automatic, for: .windowToolbar)
        .overlay {
            if model.chrome.palette {
                Color.black.opacity(0.14)
                    .ignoresSafeArea()
                    .contentShape(.rect)
                    .onTapGesture { model.chrome.palette = false }
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if model.chrome.palette {
                CommandPalette(model: model)
                    .transition(.growGlass(from: model.chrome.paletteAnchor))
            }
        }
        .overlay(alignment: .bottom) {
            ToastStack(model: model)
                .padding(.bottom, 56)
        }
        // Picking a template for a new space grows out of the 「新建空间」 that was clicked.
        .growPanel(isPresented: Bindable(model.chrome).newSpaceSheet, origin: model.chrome.panelOrigin,
                   fallback: UnitPoint(x: 0.5, y: 0.12), width: 660, dims: true) {
            NewSpaceSheet(model: model)
        }
        // The note's card grows out of the toolbar button that opened it.
        .growPanel(isPresented: Bindable(model.chrome).noteInfoOpen, origin: model.chrome.panelOrigin, width: 340) {
            NoteInfoPopover(model: model)
        }
        .motion(Motion.overlay, value: model.chrome.palette)
        .sheet(isPresented: Binding(get: { model.chrome.onboardingStep != nil }, set: { if !$0 { model.chrome.onboardingStep = nil } })) {
            OnboardingSheet(model: model)
        }
        .onAppear { model.openSettingsAction = { openSettings() } }
        // The Agent panel hides rather than going away: a model list left open in it would stay
        // open, unseen, and keep catching ⎋ and clicks. It closes with the panel.
        .onChange(of: model.chrome.agentPanel) { _, shown in if !shown { model.chrome.modelPickerOpen = false } }
    }
}

/// Hosts `content` in an NSHostingView of its own that takes whatever size it is given.
///
/// While the inspector slides in or out, AppKit resizes the column on every frame and the
/// window's SwiftUI layout runs again from the top: the Agent bar's `ViewThatFits`, the
/// transcript and the composer were all measured afresh each frame (10–15 ms of a 16.7 ms
/// frame with a conversation open), although the panel's own width never changes. Behind this
/// boundary the content is laid out only when its size or its own state changes.
struct FixedHost<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let host = NSHostingView(rootView: content)
        // No min/ideal size constraints: working those out is the measuring this avoids.
        host.sizingOptions = []
        return host
    }

    func updateNSView(_ host: NSHostingView<Content>, context: Context) {
        host.rootView = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSHostingView<Content>, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// Messages float up from the bottom edge. A new one pushes in from below and the earlier
/// ones step back behind it, so a burst of results reads as one pile rather than a flicker;
/// hovering the pile fans it out into a list and keeps it there.
struct ToastStack: View {
    @Bindable var model: AppModel
    @State private var fanned = false

    var body: some View {
        let items = Array(model.chrome.toasts.prefix(4))
        ZStack(alignment: .bottom) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, t in
                let d = CGFloat(i)
                Toast(item: t)
                    .scaleEffect(fanned ? 1 : 1 - d * 0.06, anchor: .bottom)
                    .offset(y: fanned ? -d * 48 : -d * 11)
                    .opacity(fanned || i == 0 ? 1 : i < 3 ? 0.95 - Double(i) * 0.2 : 0)
                    .zIndex(-Double(i))
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.94, anchor: .bottom))))
            }
        }
        // A single message lets clicks through to the page; a pile can be hovered open.
        .allowsHitTesting(items.count > 1)
        .onHover { inside in
            withMotion(Motion.morph) { fanned = inside && items.count > 1 }
            if inside { model.chrome.toastHeld = true } else { model.releaseToasts() }
        }
        .onChange(of: items.isEmpty) { _, empty in if empty { fanned = false; model.chrome.toastHeld = false } }
        .help(items.count > 1 ? "\(items.count) 条消息" : "")
    }
}

struct Toast: View {
    let item: ToastItem
    /// Bumped on appear, for the lively style's shake on a problem.
    @State private var shake = 0

    var body: some View {
        Label(item.text, systemImage: icon)
            .labelStyle(ToastLabelStyle(tint: tint))
            .font(.callout)
            .lineLimit(1)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .capsuleSurface(tint: item.kind == .problem ? Color.red.opacity(0.14) : nil)
            .shadow(color: item.kind == .problem && Motion.style != .minimal ? .red.opacity(0.18) : .clear, radius: 12)
            .keyframeAnimator(initialValue: 0.0, trigger: shake) { content, x in
                content.offset(x: x)
            } keyframes: { _ in
                if item.kind == .problem, Motion.style == .lively, !Motion.reduce {
                    LinearKeyframe(-6, duration: 0.06)
                    LinearKeyframe(5, duration: 0.08)
                    LinearKeyframe(-3, duration: 0.08)
                    SpringKeyframe(0, duration: 0.2, spring: .bouncy)
                } else {
                    LinearKeyframe(0, duration: 0.01)
                }
            }
            .onAppear { shake += 1 }
    }

    private var icon: String {
        switch item.kind {
        case .done: "checkmark.circle.fill"
        case .problem: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch item.kind {
        case .done: .accentColor
        case .problem: .red
        case .info: .secondary
        }
    }

    private struct ToastLabelStyle: LabelStyle {
        let tint: Color
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 8) {
                configuration.icon.foregroundStyle(tint)
                configuration.title
            }
        }
    }
}

func agentLabel(_ a: AgentKind?) -> String { a?.displayName ?? "外部程序" }
