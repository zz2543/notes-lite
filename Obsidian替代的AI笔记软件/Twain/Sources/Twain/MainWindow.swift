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
                    AgentInspector(model: model)
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
