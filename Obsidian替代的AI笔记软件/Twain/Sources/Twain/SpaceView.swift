import Charts
import SwiftUI
import TwainCore

/// A space's dashboard: its modules in a grid, drawn natively from the manifest.
struct SpaceView: View {
    @Bindable var model: AppModel
    let plugin: Plugin
    @State private var editing = false
    /// Two module columns or one. Switched with a gap between the two thresholds so a width
    /// right at the edge cannot flip it back and forth.
    @State private var twoColumns = true

    private struct WidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 900
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }

    /// Module indexes grouped into rows.
    private func rows(_ modules: [JSONValue]) -> [[Int]] {
        guard twoColumns else { return modules.indices.map { [$0] } }
        var out: [[Int]] = [], pending: Int?
        for (i, m) in modules.enumerated() {
            if m["span"]?.int == 2 {
                if let p = pending { out.append([p]); pending = nil }
                out.append([i])
            } else if let p = pending {
                out.append([p, i]); pending = nil
            } else {
                pending = i
            }
        }
        if let p = pending { out.append([p]) }
        return out
    }

    var body: some View {
        let modules = plugin.space?.modules ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                GeometryReader { geo in
                    Color.clear.preference(key: WidthKey.self, value: geo.size.width)
                }
                .frame(height: 0)
                .onPreferenceChange(WidthKey.self) { w in
                    if twoColumns, w < 640 { twoColumns = false } else if !twoColumns, w > 720 { twoColumns = true }
                }
                // Two columns when there's room; a module with "span": 2 takes a whole row.
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(rows(modules).enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(row, id: \.self) { i in
                                ModuleCard(model: model, plugin: plugin, module: modules[i], editing: editing,
                                           move: { d in move(i, by: d, in: modules) }, remove: { remove(i, in: modules) })
                            }
                            if row.count == 1, twoColumns, modules[row[0]]["span"]?.int != 2 { Color.clear.frame(maxWidth: .infinity) }
                        }
                    }
                }
                if editing { addMenu(modules) }
            }
            .padding(.horizontal, 28).padding(.top, 64).padding(.bottom, 40)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
        .id(plugin.id)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: plugin.icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .glassEffect(.regular.tint(.accentColor.opacity(0.15)), in: .rect(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.name).font(.system(size: 26, weight: .bold))
                if !plugin.summary.isEmpty { Text(plugin.summary).font(.callout).foregroundStyle(.secondary) }
                if let f = plugin.space?.folder, !f.isEmpty {
                    Label(f, systemImage: "folder").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if plugin.space?.entryTitle != nil {
                        Button("新条目", systemImage: "square.and.pencil") { model.openEntry(plugin) }
                            .buttonStyle(.glassProminent)
                    }
                    Button(editing ? "完成" : "编辑", systemImage: editing ? "checkmark" : "slider.horizontal.3") { editing.toggle() }
                        .buttonStyle(.glass)
                    Menu {
                        Button("在 Finder 中显示插件", systemImage: "folder") {
                            if let v = model.vault { NSWorkspace.shared.activateFileViewerSelecting([v.root.appendingPathComponent(plugin.dir)]) }
                        }
                        Button("编辑 manifest.json", systemImage: "curlybraces") {
                            if let v = model.vault { NSWorkspace.shared.open(v.root.appendingPathComponent(plugin.dir).appendingPathComponent("manifest.json")) }
                        }
                        Divider()
                        Button("停用这个空间", systemImage: "pause.circle") { model.setPluginEnabled(plugin, false) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.button).buttonStyle(.glass).menuIndicator(.hidden).fixedSize()
                }
                .buttonBorderShape(.capsule)
            }
        }
    }

    private func move(_ i: Int, by d: Int, in modules: [JSONValue]) {
        let j = i + d
        guard modules.indices.contains(j) else { return }
        var m = modules
        m.swapAt(i, j)
        model.saveModules(plugin, m)
    }

    private func remove(_ i: Int, in modules: [JSONValue]) {
        var m = modules
        m.remove(at: i)
        model.saveModules(plugin, m)
    }

    private func addMenu(_ modules: [JSONValue]) -> some View {
        let folder = plugin.space?.folder ?? ""
        let presets: [(String, String, JSONValue)] = [
            ("今天的条目", "sun.max", ["type": "today", "title": "今天"]),
            ("日历", "calendar", ["type": "calendar", "title": "最近 12 周", "days": 84, "span": 2]),
            ("笔记列表", "list.bullet", ["type": "query", "title": "最近的笔记", "folder": .string(folder), "sort": "modified", "limit": 8]),
            ("待办", "checklist", ["type": "tasks", "title": "待办", "folder": .string(folder), "limit": 8]),
            ("问库", "rectangle.stack.badge.person.crop", ["type": "ask", "title": "提问", "scope": .string(folder.isEmpty ? "" : "folder:" + folder)]),
            ("数字", "number", ["type": "stat", "title": "近 7 天", "collection": "sleep", "field": "hours", "reduce": "avg", "days": 7]),
            ("图表", "chart.xyaxis.line", ["type": "chart", "title": "趋势", "collection": "sleep", "field": "hours", "days": 30, "kind": "line", "span": 2]),
            ("习惯打卡", "checkmark.circle", ["type": "habits", "title": "习惯", "collection": "habits", "items": ["早起", "运动"], "span": 2]),
            ("记一笔", "square.and.pencil", ["type": "log", "title": "记一笔", "fields": [["collection": "sleep", "field": "hours", "label": "睡了几小时"]]]),
            ("流水线按钮", "arrow.triangle.branch", ["type": "pipelines", "title": "流水线", "items": .array(model.agents.pipelines.prefix(3).map { .string($0.key) })]),
            ("嵌入笔记", "doc.text", ["type": "note", "title": "笔记", "path": .string(model.editor.activeRel ?? "")]),
            ("说明文字", "text.alignleft", ["type": "text", "title": "说明", "text": "在 manifest.json 里改这段文字。"]),
            ("库的概况", "chart.bar", ["type": "stats", "title": "概况"]),
        ]
        return Menu {
            ForEach(presets, id: \.0) { name, icon, m in
                Button(name, systemImage: icon) { model.saveModules(plugin, modules + [m]) }
            }
        } label: {
            Label("添加模块", systemImage: "plus")
        }
        .menuStyle(.button).buttonStyle(.glass).buttonBorderShape(.capsule).fixedSize()
    }
}

/// One module: a card with a title, drawn by type.
struct ModuleCard: View {
    @Bindable var model: AppModel
    let plugin: Plugin
    let module: JSONValue
    let editing: Bool
    let move: (Int) -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(module["title"]?.string ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if editing {
                    Button { move(-1) } label: { Image(systemName: "arrow.up") }.help("上移")
                    Button { move(1) } label: { Image(systemName: "arrow.down") }.help("下移")
                    Button(role: .destructive, action: remove) { Image(systemName: "trash") }.help("移除")
                }
            }
            .buttonStyle(.borderless)
            content
        }
        .padding(16)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
        .clipped()
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(editing ? 1 : 0.5),
                                                                                     style: StrokeStyle(lineWidth: editing ? 1 : 0.5, dash: editing ? [5, 4] : [])))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    @ViewBuilder private var content: some View {
        switch module["type"]?.string ?? "" {
        case "today": TodayModule(model: model, plugin: plugin)
        case "calendar": CalendarModule(model: model, plugin: plugin, days: module["days"]?.int ?? 84)
        case "query": QueryModule(model: model, module: module)
        case "tasks": TasksModule(model: model, module: module)
        case "ask": AskModule(model: model, module: module)
        case "stat": StatModule(model: model, plugin: plugin, module: module)
        case "chart": ChartModule(model: model, plugin: plugin, module: module)
        case "habits": HabitsModule(model: model, module: module)
        case "log": LogModule(model: model, module: module)
        case "pipelines": PipelinesModule(model: model, module: module)
        case "note": NoteModule(model: model, module: module)
        case "html": WidgetModule(model: model, plugin: plugin, module: module)
        case "stats": StatsModule(model: model)
        case "text":
            Text(.init(module["text"]?.string ?? "")).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        default:
            Label("不认识的模块类型：\(module["type"]?.string ?? "（空）")", systemImage: "questionmark.square.dashed")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Modules

private struct TodayModule: View {
    @Bindable var model: AppModel
    let plugin: Plugin

    var body: some View {
        let rel = model.entryRel(plugin, date: Date())
        let vars = DateVars.vars()
        VStack(alignment: .leading, spacing: 8) {
            Text("\(vars["date"]!) \(vars["weekday"]!)").font(.title3.weight(.semibold))
            // The index holds the notes' text already: nothing is read from disk while drawing.
            if let rel, let lines = model.index?.notes[rel]?.lines ?? (model.vault?.diskContent(rel)).map(Markdown.lines) {
                let body = lines.dropFirst().filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(4)
                Text(body.joined(separator: "\n")).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                Button("继续写", systemImage: "pencil") { model.open(rel, focus: true) }.buttonStyle(.glass)
            } else {
                Text("今天还没有写。").font(.callout).foregroundStyle(.secondary)
                Button("开始写今天的", systemImage: "square.and.pencil") { model.openEntry(plugin) }.buttonStyle(.glassProminent)
            }
        }
        .controlSize(.small).buttonBorderShape(.capsule)
    }
}

private struct CalendarModule: View {
    @Bindable var model: AppModel
    let plugin: Plugin
    let days: Int

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Columns are weeks, rows weekdays, like a contribution graph.
        let weeks = max(1, (days + 6) / 7)
        let start = cal.date(byAdding: .day, value: -(weeks * 7 - 1), to: today)!
        let dates = (0..<(weeks * 7)).map { cal.date(byAdding: .day, value: $0, to: start)! }
        let index = model.index
        let sizes: [Int] = dates.map { d in
            guard let rel = model.entryRel(plugin, date: d) else { return -1 }
            return index?.notes[rel]?.lines.reduce(0) { $0 + $1.count } ?? 0
        }
        let written = sizes.filter { $0 >= 0 }.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { r in
                            let i = w * 7 + r
                            let size = sizes[i]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(size < 0 ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(Color.accentColor.opacity(0.3 + min(0.7, Double(size) / 1500))))
                                .frame(width: 13, height: 13)
                                .overlay { if dates[i] == today { RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.5), lineWidth: 1) } }
                                .help(DateVars.vars(dates[i])["date"]! + (size >= 0 ? " · \(size) 字" : " · 没有写"))
                                .onTapGesture { model.openEntry(plugin, date: dates[i]) }
                        }
                    }
                }
            }
            Text("\(weeks * 7) 天里写了 \(written) 天").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct QueryModule: View {
    @Bindable var model: AppModel
    let module: JSONValue

    var body: some View {
        let folder = module["folder"]?.string ?? ""
        let tag = module["tag"]?.string?.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let limit = module["limit"]?.int ?? 8
        let notes = (model.vault?.notes ?? []).filter { n in
            (folder.isEmpty || n.rel.hasPrefix(folder + "/")) && !n.isAgentFile
                && (tag == nil || model.index?.notes[n.rel]?.outline.tags.contains(tag!) == true)
        }
        let sorted: [NoteRef] = {
            switch module["sort"]?.string {
            case "name": return notes.sorted { $0.title > $1.title }
            default:
                // Dates from the last walk of the folder; the index changing means a note was saved.
                _ = model.index?.generation
                let stamps = model.vault?.stamps ?? [:]
                return notes.sorted { (stamps[$0.rel] ?? .distantPast) > (stamps[$1.rel] ?? .distantPast) }
            }
        }()
        VStack(alignment: .leading, spacing: 2) {
            if sorted.isEmpty { Text("还没有笔记").font(.callout).foregroundStyle(.secondary) }
            ForEach(sorted.prefix(limit)) { n in
                Button { model.open(n.rel) } label: {
                    HStack {
                        Image(systemName: n.isHTML ? "globe" : "doc.text").foregroundStyle(.secondary)
                        Text(n.title).lineLimit(1)
                        Spacer(minLength: 0)
                        if !folder.isEmpty && n.folder != folder { Text(n.folder).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                    }
                    .padding(.vertical, 4).contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.callout)
    }
}

private struct TasksModule: View {
    @Bindable var model: AppModel
    let module: JSONValue

    var body: some View {
        // From the index as of the last walk: it follows the files without reading any here.
        let tasks = model.index?.tasks(folder: module["folder"]?.string, tag: module["tag"]?.string) ?? []
        VStack(alignment: .leading, spacing: 4) {
            if tasks.isEmpty { Text("没有未完成的待办").font(.callout).foregroundStyle(.secondary) }
            ForEach(Array(tasks.prefix(module["limit"]?.int ?? 8).enumerated()), id: \.offset) { _, t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button { model.toggleTask(rel: t.rel, line: t.task.line) } label: {
                        Image(systemName: t.task.done ? "checkmark.square.fill" : "square").foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(t.task.text).lineLimit(2)
                        Button(NoteRef(rel: t.rel).title + ":\(t.task.line)") {
                            model.open(t.rel)
                            model.requestFocus(caret: CommandRegistry.offset(ofLine: t.task.line, in: model.editor.editorText))
                        }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            if tasks.count > (module["limit"]?.int ?? 8) { Text("还有 \(tasks.count - (module["limit"]?.int ?? 8)) 条").font(.caption).foregroundStyle(.tertiary) }
        }
        .font(.callout)
    }
}

private struct AskModule: View {
    @Bindable var model: AppModel
    let module: JSONValue
    @State private var q = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField(module["placeholder"]?.string ?? "问个问题…", text: $q)
                .textFieldStyle(.plain).font(.body).onSubmit(ask)
            Button("提问", systemImage: "arrow.up", action: ask)
                .labelStyle(.iconOnly).buttonStyle(.glassProminent).buttonBorderShape(.circle)
                .disabled(q.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
        .background(.fill.quinary, in: .rect(cornerRadius: 12, style: .continuous))
    }

    private func ask() {
        let text = q.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        model.newDesk()
        if let id = model.chrome.openDesk { model.ask(desk: id, question: text, scope: module["scope"]?.string ?? "") }
        q = ""
    }
}

private func formatted(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

private struct StatModule: View {
    @Bindable var model: AppModel
    let plugin: Plugin
    let module: JSONValue

    var body: some View {
        let collection = module["collection"]?.string ?? ""
        let field = module["field"]?.string ?? "value"
        let days = module["days"]?.int ?? 7
        let reduce = module["reduce"]?.string ?? "avg"
        let (_, unit) = plugin.label(collection: collection, field: field)
        // Each day reduced the same way first (an average of daily averages; sums of daily sums).
        let key = DataKey(root: model.vault?.root, collection: collection, field: field, days: days,
                          reduce: reduce == "count" ? "sum" : reduce, version: model.dataVersion)
        Loaded(key: key, load: DataKey.series) { series in
        let values = (series ?? []).compactMap(\.value)
        let value: Double? = values.isEmpty ? nil : reduce == "avg" ? values.reduce(0, +) / Double(values.count)
            : reduce == "last" ? values.last : reduce == "count" ? Double(values.count) : values.reduce(0, +)
        let goal = module["goal"]?.number
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value.map(formatted) ?? "—").font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                Text(unit).font(.callout).foregroundStyle(.secondary)
            }
            if let goal, let value {
                ProgressView(value: min(value, goal), total: goal).tint(value >= goal ? .green : .accentColor)
                Text(value >= goal ? "达到目标 \(formatted(goal))" : "目标 \(formatted(goal))，还差 \(formatted(goal - value))")
                    .font(.caption).foregroundStyle(.secondary)
            } else if value == nil, series != nil {
                Text("还没有数据 · \(collection)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .contentTransition(.numericText())
        }
    }
}

private struct ChartModule: View {
    @Bindable var model: AppModel
    let plugin: Plugin
    let module: JSONValue

    var body: some View {
        let collection = module["collection"]?.string ?? ""
        let field = module["field"]?.string ?? "value"
        let (label, unit) = plugin.label(collection: collection, field: field)
        let key = DataKey(root: model.vault?.root, collection: collection, field: field, days: module["days"]?.int ?? 30,
                          reduce: module["reduce"]?.string ?? "sum", version: model.dataVersion)
        Loaded(key: key, load: DataKey.series) { series in
        let points = (series ?? []).compactMap { d in d.value.map { (DataStore.day.date(from: d.day) ?? Date(), $0) } }
        if series == nil {
            Color.clear.frame(maxWidth: .infinity, minHeight: 160)
        } else if points.isEmpty {
            Text("还没有 \(collection) 数据。用「记一笔」、twain data add 或 HTTP 接口导入。").font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        } else {
            Chart {
                ForEach(points, id: \.0) { d, v in
                    if module["kind"]?.string == "bar" {
                        BarMark(x: .value("日期", d, unit: .day), y: .value(label, v)).foregroundStyle(Color.accentColor.gradient)
                            .cornerRadius(3)
                    } else {
                        LineMark(x: .value("日期", d, unit: .day), y: .value(label, v)).interpolationMethod(.catmullRom)
                            .foregroundStyle(Color.accentColor)
                        PointMark(x: .value("日期", d, unit: .day), y: .value(label, v)).symbolSize(18).foregroundStyle(Color.accentColor)
                    }
                }
                if let goal = module["goal"]?.number {
                    RuleMark(y: .value("目标", goal)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYAxisLabel(unit)
            .frame(height: 160)
        }
        }
    }
}

private struct HabitsModule: View {
    @Bindable var model: AppModel
    let module: JSONValue

    var body: some View {
        let collection = module["collection"]?.string ?? "habits"
        let items = (module["items"]?.array ?? []).compactMap(\.string)
        let days = module["days"]?.int ?? 7
        Loaded(key: DataKey(root: model.vault?.root, collection: collection, field: "", days: days, reduce: "", version: model.dataVersion),
               load: DataKey.habits) { loaded in
        let state = loaded ?? [:]
        let dates = (0..<days).map { DataStore.day.string(from: Calendar.current.date(byAdding: .day, value: $0 - days + 1, to: Date())!) }
        let today = dates.last!
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { h in
                let done = state[h + "|" + today] == true
                HStack(spacing: 10) {
                    Button { model.setHabit(collection, h, !done) } label: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                    }
                    .buttonStyle(.plain)
                    Text(h).frame(width: 64, alignment: .leading)
                    HStack(spacing: 3) {
                        ForEach(dates, id: \.self) { d in
                            Circle().fill(state[h + "|" + d] == true ? AnyShapeStyle(Color.green.opacity(0.8)) : AnyShapeStyle(.fill.tertiary))
                                .frame(width: 10, height: 10).help(d)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .font(.callout)
        }
    }
}

private struct LogModule: View {
    @Bindable var model: AppModel
    let module: JSONValue
    @State private var values: [String: String] = [:]

    var body: some View {
        let fields = module["fields"]?.array ?? []
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.offset) { i, f in
                let key = "\(i)"
                HStack {
                    Text(f["label"]?.string ?? f["field"]?.string ?? "").frame(maxWidth: .infinity, alignment: .leading)
                    TextField("数值", text: Binding(get: { values[key] ?? "" }, set: { values[key] = $0 }))
                        .textFieldStyle(.roundedBorder).frame(width: 80).multilineTextAlignment(.trailing)
                        .onSubmit { save(f, key) }
                    Button("记录") { save(f, key) }.buttonStyle(.glass).disabled((values[key] ?? "").isEmpty)
                }
            }
        }
        .font(.callout).controlSize(.small).buttonBorderShape(.capsule)
    }

    private func save(_ f: JSONValue, _ key: String) {
        guard let c = f["collection"]?.string, let field = f["field"]?.string, let raw = values[key], !raw.isEmpty else { return }
        let v: JSONValue = Double(raw).map(JSONValue.number) ?? .string(raw)
        model.addData(c, ["date": .string(DataStore.day.string(from: Date())), field: v])
        values[key] = ""
    }
}

private struct PipelinesModule: View {
    @Bindable var model: AppModel
    let module: JSONValue

    var body: some View {
        let keys = (module["items"]?.array ?? []).compactMap(\.string)
        let list = keys.isEmpty ? model.agents.pipelines : keys.compactMap { model.pipeline(named: $0) }
        VStack(alignment: .leading, spacing: 6) {
            if list.isEmpty { Text("没有找到流水线：\(keys.joined(separator: "、"))").font(.callout).foregroundStyle(.secondary) }
            ForEach(list, id: \.key) { p in
                Button {
                    do { try model.runPipeline(p) } catch let e as RPCError { model.showToast(e.message) } catch {}
                } label: {
                    HStack {
                        Label(p.title, systemImage: p.icon)
                        Spacer(minLength: 0)
                        Text("\(p.steps.count) 步").font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass).buttonBorderShape(.capsule)
            }
        }
    }
}

private struct NoteModule: View {
    @Bindable var model: AppModel
    let module: JSONValue

    var body: some View {
        let path = module["path"]?.string ?? ""
        let rel = model.index?.resolve(path) ?? path
        VStack(alignment: .leading, spacing: 8) {
            if let lines = model.index?.notes[rel]?.lines ?? (model.vault?.diskContent(rel)).map(Markdown.lines) {
                Text(.init(lines.prefix(14).joined(separator: "\n"))).font(.callout).foregroundStyle(.secondary)
                    .lineLimit(14).textSelection(.enabled)
                Button("打开", systemImage: "arrow.up.right") { model.open(rel) }.buttonStyle(.glass).controlSize(.small).buttonBorderShape(.capsule)
            } else {
                Text("找不到笔记：\(path)").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatsModule: View {
    @Bindable var model: AppModel

    var body: some View {
        let notes = model.vault?.notes.count ?? 0
        let tasks = model.index?.tasks().count ?? 0
        let pending = model.agents.pending.values.reduce(0) { $0 + $1.hunks.count }
        Loaded(key: DataKey(root: model.vault?.root, collection: "", field: "", days: 0, reduce: "", version: model.dataVersion),
               load: DataKey.collectionCount) { data in
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow { stat("\(notes)", "篇笔记"); stat("\(tasks)", "条待办") }
                GridRow { stat("\(pending)", "处改动待审"); stat(data.map(String.init) ?? "—", "个数据集合") }
            }
            .contentTransition(.numericText())
        }
    }

    private func stat(_ n: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Data helpers

/// What a data card reads, and when to read it again: `version` changes whenever a collection does.
struct DataKey: Equatable, Sendable {
    var root: URL?
    var collection: String
    var field: String
    var days: Int
    var reduce: String
    var version: Int

    struct Day: Sendable { var day: String; var value: Double? }

    @Sendable static func series(_ k: DataKey) -> [Day] {
        guard let root = k.root else { return [] }
        return DataStore(vault: root).daily(k.collection, field: k.field, days: k.days, reduce: k.reduce).map { Day(day: $0.day, value: $0.value) }
    }

    /// habit|day → done, the latest record for each winning.
    @Sendable static func habits(_ k: DataKey) -> [String: Bool] {
        guard let root = k.root else { return [:] }
        var out: [String: Bool] = [:]
        for r in DataStore(vault: root).query(k.collection, since: DataStore.parseSince("\(k.days)d")) {
            guard let h = r["habit"]?.string, let t = DataStore.time(of: r) else { continue }
            out[h + "|" + DataStore.day.string(from: t)] = r["done"]?.bool ?? true
        }
        return out
    }

    @Sendable static func collectionCount(_ k: DataKey) -> Int {
        k.root.map { DataStore(vault: $0).collections().count } ?? 0
    }
}

extension AppModel {
    func setHabit(_ collection: String, _ habit: String, _ done: Bool) {
        addData(collection, ["habit": .string(habit), "done": .bool(done), "date": .string(DataStore.day.string(from: Date()))])
    }

    func addData(_ collection: String, _ record: [String: JSONValue]) {
        guard let v = vault else { return }
        do {
            let n = try DataStore(vault: v.root).add(collection, records: [.object(record)])
            dataChanged(collection, added: n, source: "user")
        } catch let e as RPCError { showToast(e.message) } catch {}
    }
}

// MARK: - New space

/// Pick a template, name the space and its folder.
struct NewSpaceSheet: View {
    @Bindable var model: AppModel
    @State private var pick = SpaceTemplate.journal.id
    @State private var name = SpaceTemplate.journal.name
    @State private var folder = SpaceTemplate.journal.folder
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建空间").font(.title2.weight(.bold))
            Text("空间是你自己的模式：一个文件夹、一块仪表盘、给 agent 的约定和几条流水线。从模板开始，之后随意改。")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                ForEach(SpaceTemplate.all.filter { $0.id != "workbench" }) { t in
                    let on = pick == t.id
                    Button {
                        pick = t.id
                        name = t.name
                        folder = t.folder
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: t.icon).font(.title2).foregroundStyle(.tint)
                            Text(t.name).font(.headline)
                            Text(t.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                        .padding(12)
                        .background(.fill.quinary, in: .rect(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: on ? 2 : 0.5))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            Form {
                TextField("名字", text: $name)
                TextField("文件夹", text: $folder, prompt: Text("笔记放在库里的哪个文件夹"))
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("创建") {
                    guard let t = SpaceTemplate.all.first(where: { $0.id == pick }) else { return }
                    do { try model.installTemplate(t, name: name.trimmingCharacters(in: .whitespaces).isEmpty ? t.name : name, folder: folder) }
                    catch { model.showToast(error.localizedDescription) }
                    dismiss()
                }
                .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 660)
    }
}
