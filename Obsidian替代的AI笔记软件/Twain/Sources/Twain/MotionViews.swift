import SwiftUI

/// One character that animates while an agent works. Each activity has its own braille
/// pattern, so a glance tells thinking from searching, reading, writing or running a command,
/// and it fits inside a line of text where a spinner would push the words apart.
/// All spinners on screen step on the same clock and move in time with each other.
struct GlyphSpinner: View {
    enum Activity {
        case think, search, read, write, run

        /// The activity a step's description names (“读取 …”, “写入 …”, “$ …”).
        init(step: String) {
            if step.hasPrefix("读取") { self = .read }
            else if step.hasPrefix("写入") { self = .write }
            else if step.hasPrefix("搜索") || step.hasPrefix("查找") || step.hasPrefix("网页搜索") { self = .search }
            else if step.hasPrefix("$") { self = .run }
            else { self = .think }
        }

        var frames: [Character] {
            switch self {
            case .think: Array("⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
            case .search: Array("⣾⣽⣻⢿⡿⣟⣯⣷")
            case .read: Array("⠁⠂⠄⡀⢀⠠⠐⠈")
            case .write: Array("⣀⣄⣤⣦⣶⣷⣿⣷⣶⣦⣤⣄")
            case .run: Array("⠋⠙⠚⠞⠖⠦⠴⠲⠳⠓")
            }
        }

        /// What the agent is doing, for a status line.
        var verb: String {
            switch self {
            case .think: "正在思考"
            case .search: "正在搜索"
            case .read: "正在读取"
            case .write: "正在写入"
            case .run: "正在运行命令"
            }
        }
    }

    var activity: Activity = .think
    var tint: Color = .accentColor

    var body: some View {
        Group {
            if Motion.ambient {
                TimelineView(.periodic(from: .now, by: 0.09)) { ctx in
                    let f = activity.frames
                    Text(String(f[Int(ctx.date.timeIntervalSinceReferenceDate / 0.09) % f.count]))
                }
            } else {
                Text("•")
            }
        }
        .font(.system(size: 16, weight: .bold, design: .monospaced))
        .foregroundStyle(tint)
        .frame(width: 16, height: 14)
        .accessibilityLabel(activity.verb)
    }
}

/// Text that rolls to its new value: the old line leaves upwards while the new one rises in
/// from below, so a changing status reads as one line updating rather than a flicker.
struct RollingText: View {
    let text: String
    var animation: Animation? = Motion.quick

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text)
                .lineLimit(1)
                .id(text)
                .transition(.push(from: .bottom).combined(with: .opacity))
        }
        .clipped()
        .motion(animation, value: text)
    }
}

/// A placeholder that cycles through example requests while the field is empty — the
/// rotating hints tell a new user what they can ask. Under 简洁 it shows the first one only.
struct RotatingPrompt: View {
    let prompts: [String]
    var period: Double = 4.5

    var body: some View {
        if Motion.ambient, prompts.count > 1 {
            TimelineView(.periodic(from: .now, by: period)) { ctx in
                RollingText(text: prompts[Int(ctx.date.timeIntervalSinceReferenceDate / period) % prompts.count],
                            animation: Motion.content)
            }
        } else {
            Text(prompts.first ?? "").lineLimit(1)
        }
    }
}

/// Things that appear together arrive one after another, each rising a few points into place.
/// The first frame already shows them at rest under 简洁 and Reduce motion.
private struct Arrive: ViewModifier {
    let index: Int
    @State private var shown: Bool

    init(index: Int) {
        self.index = index
        _shown = State(initialValue: !Motion.ambient)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                guard !shown else { return }
                withAnimation(Motion.stagger(index, Motion.content)) { shown = true }
            }
    }
}

extension View {
    /// Arrive as the `index`th of a group that appears together (see `Arrive`).
    /// Not for rows of a lazy list: those appear again on every scroll.
    func arrive(_ index: Int) -> some View { modifier(Arrive(index: index)) }
}

/// A button that answers in place: after it is pressed its label turns into "已…" with a
/// check for a moment and then back, so the result shows where the eye already is.
struct ConfirmButton: View {
    let title: String
    let done: String
    let action: () -> Void
    @State private var confirmed = false
    @State private var reset: DispatchWorkItem?

    var body: some View {
        Button {
            action()
            Motion.feedback(.done)
            withMotion(Motion.morph) { confirmed = true }
            reset?.cancel()
            let w = DispatchWorkItem { withMotion(Motion.morph) { confirmed = false } }
            reset = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: w)
        } label: {
            ZStack {
                if confirmed {
                    Label(done, systemImage: "checkmark").transition(.blurReplace)
                } else {
                    Text(title).transition(.blurReplace)
                }
            }
        }
    }
}
