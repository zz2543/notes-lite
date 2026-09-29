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
                CommandPalette(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .overlay(alignment: .bottom) {
            if let t = model.chrome.toast {
                Toast(text: t)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .motion(Motion.overlay, value: model.chrome.palette)
        .motion(Motion.overlay, value: model.chrome.toast)
        .sheet(isPresented: Binding(get: { model.chrome.onboardingStep != nil }, set: { if !$0 { model.chrome.onboardingStep = nil } })) {
            OnboardingSheet(model: model)
        }
        .onAppear { model.openSettingsAction = { openSettings() } }
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

struct Toast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .labelStyle(ToastLabelStyle())
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule()
            .allowsHitTesting(false)
    }

    private struct ToastLabelStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 8) {
                configuration.icon.foregroundStyle(.tint)
                configuration.title
            }
        }
    }
}

func agentLabel(_ a: AgentKind?) -> String { a?.displayName ?? "外部程序" }
