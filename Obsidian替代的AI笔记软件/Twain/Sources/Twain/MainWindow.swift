import TwainCore
import SwiftUI

/// The single document window: floating glass sidebar, then one of three workspaces —
/// the page with the agent beside it, the agent with the page beside it, or the desk.
struct MainWindow: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView(columnVisibility: $model.columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 250, max: 340)
        } detail: {
            switch model.workspace {
            case .write:
                NoteDetail(model: model)
                    .inspector(isPresented: $model.agentPanel) {
                        AgentInspector(model: model)
                            .inspectorColumnWidth(min: 300, ideal: 360, max: 520)
                    }
            case .agent:
                AgentStage(model: model)
                    .inspector(isPresented: $model.notePanel) {
                        NoteDetail(model: model, embedded: true)
                            .inspectorColumnWidth(min: 360, ideal: 480, max: 760)
                    }
            case .desk:
                Workbench(model: model)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) { WorkspacePicker(model: model) }
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
        .animation(.snappy(duration: 0.25), value: model.workspace)
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
