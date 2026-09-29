import TwainCore
import SwiftUI

struct PaletteEntry: Identifiable {
    enum Section: String { case notes = "笔记", commands = "命令" }
    let id: String
    let section: Section
    let label: String
    let hint: String
    let icon: String
    var tint: Color? = nil
    let run: () -> Void
}

/// ⌘K: one field that finds notes and runs commands, floating above the window like Spotlight.
struct CommandPalette: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    private var entries: [PaletteEntry] {
        let m = model
        let cmds: [PaletteEntry] = CommandRegistry.all(m).compactMap { c in
            guard let p = c.palette, p.visible(m) else { return nil }
            return PaletteEntry(id: c.spec.id, section: .commands, label: p.label(m), hint: p.hint, icon: p.icon, tint: p.tint) {
                c.perform(m, CommandCall()) { result in
                    if case let .failure(e) = result { m.showToast(e.message) }
                }
            }
        }
        let notes = (m.vault?.notes ?? []).map { n in
            PaletteEntry(id: "n:" + n.rel, section: .notes, label: n.displayName, hint: n.folder,
                         icon: n.isAgentFile ? "doc.badge.gearshape" : "doc.text") {
                m.open(n.rel, focus: true)
            }
        }
        let q = m.chrome.paletteQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return Array(notes.filter { $0.id != "n:" + (m.editor.activeRel ?? "") }.prefix(4)) + cmds
        }
        return (notes + cmds).filter { $0.label.lowercased().contains(q) || $0.hint.lowercased().contains(q) }
    }

    var body: some View {
        let list = entries
        let sel = min(model.chrome.paletteSel, max(0, list.count - 1))
        ZStack(alignment: .top) {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { model.chrome.palette = false }
            VStack(spacing: 0) {
                searchField(list: list, sel: sel)
                if !list.isEmpty || !model.chrome.paletteQuery.isEmpty {
                    Divider().padding(.horizontal, 14)
                    results(list: list, sel: sel)
                    footer
                }
            }
            .frame(width: 640)
            // A dense list needs a steadier backdrop than bare glass: tint the glass with the
            // window color so the page behind cannot compete with the results.
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.55),
                        in: .rect(cornerRadius: Metrics.panelRadius, style: .continuous))
            .floatingGlass(radius: Metrics.panelRadius)
            .padding(.top, 96)
        }
        .onAppear { focused = true }
    }

    private func searchField(list: [PaletteEntry], sel: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索笔记，或输入命令", text: Bindable(model.chrome).paletteQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($focused)
                .onChange(of: model.chrome.paletteQuery) { _, _ in model.chrome.paletteSel = 0 }
                .onKeyPress(.downArrow) { if imeComposing() { return .ignored }; move(1, list.count); return .handled }
                .onKeyPress(.upArrow) { if imeComposing() { return .ignored }; move(-1, list.count); return .handled }
                .onKeyPress(.escape) { if imeComposing() { return .ignored }; model.chrome.palette = false; return .handled }
                .onKeyPress(.return) {
                    if imeComposing() { return .ignored }
                    model.chrome.palette = false
                    if list.isEmpty {
                        let q = model.chrome.paletteQuery.trimmingCharacters(in: .whitespaces)
                        if !q.isEmpty { model.openByTitle(q) }
                    } else {
                        list[sel].run()
                    }
                    return .handled
                }
        }
        .padding(.horizontal, 20).frame(height: 60)
    }

    private func results(list: [PaletteEntry], sel: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, e in
                        if i == 0 || list[i - 1].section != e.section {
                            Text(e.section.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, i == 0 ? 4 : 10).padding(.bottom, 2)
                        }
                        row(e, on: i == sel)
                            .id(i)
                            .onHover { if $0 { model.chrome.paletteSel = i } }
                            .onTapGesture { model.chrome.palette = false; e.run() }
                    }
                    if list.isEmpty {
                        Label("没有匹配项 · 按 ↩ 新建「\(model.chrome.paletteQuery)」", systemImage: "plus.circle")
                            .foregroundStyle(.secondary)
                            .padding(14)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 360)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: model.chrome.paletteSel) { _, v in proxy.scrollTo(v) }
        }
    }

    private func row(_ e: PaletteEntry, on: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: e.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(on ? AnyShapeStyle(.white) : e.tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
                .frame(width: 28, height: 28)
                .background(on ? AnyShapeStyle(.white.opacity(0.18)) : AnyShapeStyle(.fill.tertiary),
                            in: .rect(cornerRadius: 7, style: .continuous))
            Text(e.label).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(e.hint)
                .font(e.hint.hasPrefix("⌘") || e.hint.hasPrefix("⇧") ? .callout.monospaced() : .caption)
                .foregroundStyle(on ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
                .lineLimit(1)
        }
        .foregroundStyle(on ? .white : .primary)
        .padding(.horizontal, 8).frame(height: 42)
        .background(RowHighlight(on: on))
        .contentShape(.rect)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("选择", systemImage: "arrow.up.arrow.down")
            Label("打开", systemImage: "return")
            Label("关闭", systemImage: "escape")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20).padding(.vertical, 10)
        .overlay(alignment: .top) { Divider().padding(.horizontal, 14) }
    }

    private func move(_ d: Int, _ n: Int) {
        guard n > 0 else { return }
        model.chrome.paletteSel = (min(model.chrome.paletteSel, n - 1) + d + n) % n
    }
}
