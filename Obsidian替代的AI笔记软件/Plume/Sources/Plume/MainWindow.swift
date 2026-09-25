import PlumeCore
import SwiftUI

/// The single document window: floating glass sidebar, the page, and the Agent inspector.
struct MainWindow: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            NoteDetail(model: model)
                .inspector(isPresented: $model.agentPanel) {
                    AgentInspector(model: model)
                        .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
                }
        }
        .toolbar(model.zen ? .hidden : .automatic, for: .windowToolbar)
        .overlay {
            if model.palette {
                CommandPalette(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .overlay(alignment: .bottom) {
            if let t = model.toast {
                Toast(text: t)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: model.palette)
        .animation(.snappy(duration: 0.25), value: model.toast)
        .sheet(isPresented: Binding(get: { model.onboardingStep != nil }, set: { if !$0 { model.onboardingStep = nil } })) {
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
