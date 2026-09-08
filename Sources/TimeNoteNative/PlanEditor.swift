import SwiftUI

struct PlanEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let context: EditorContext
    @State private var draft: PlanDraft
    @State private var clock: TimeInput
    @State private var series = false
    @State private var problem: String?
    @State private var comparison: [WorkItem]?
    @FocusState private var titleFocused: Bool

    init(context: EditorContext) {
        self.context = context
        _draft = State(initialValue: context.draft)
        _clock = State(initialValue: TimeInput(start: context.draft.start, end: context.draft.end, nextDay: context.draft.nextDay))
    }
    private var range: TimeRange? { clock.range }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(context.task == nil ? "安排一件工作" : "修改未来安排").font(.title2.bold())
            if let comparison { comparisonView(comparison) } else { form }
            if let problem { Text(problem).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if comparison != nil {
                    Button("返回修改") { comparison = nil }
                    Button("确认修改") { saveEdit() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button(context.task == nil ? "保存安排" : "查看修改对比") { prepare() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(28).frame(width: 570).background(Style.background).tint(Style.accent)
            .onAppear { titleFocused = true }
    }
    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("想做什么？例如阅读一章", text: $draft.title).textFieldStyle(.roundedBorder)
                .font(.title3).focused($titleFocused).accessibilityIdentifier("plan-title")
            HStack {
                TextField("分类（可选）", text: $draft.category).textFieldStyle(.roundedBorder)
                if !state.categories.isEmpty {
                    Menu("已有分类") { ForEach(state.categories, id: \.self) { name in Button(name) { draft.category = name } } }
                }
            }
            HStack {
                Text("日期").frame(width: 76, alignment: .leading)
                DatePicker("工作日期", selection: dateBinding(\.day), displayedComponents: .date).labelsHidden()
                    .disabled(context.task?.seriesID != nil)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("每天几点到几点").font(.headline)
                HStack(spacing: 12) {
                    TextField("09:00", text: Binding(get: { clock.startText }, set: { clock.setStart($0) })).textFieldStyle(.roundedBorder).frame(width: 105)
                        .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        .accessibilityLabel("开始时间").accessibilityIdentifier("plan-start")

                    Text("至").foregroundStyle(.secondary)
                    TextField("10:00", text: Binding(get: { clock.endText }, set: { clock.setEnd($0) })).textFieldStyle(.roundedBorder).frame(width: 105)
                        .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        .accessibilityLabel("结束时间").accessibilityIdentifier("plan-end")
                    Toggle("次日结束", isOn: $clock.nextDay).toggleStyle(.checkbox)
                }
                Text(range.map { "计划 \($0.minutes) 分钟 · 自动计算，不是实际计时" } ?? "请填写有效时段，使用24小时制，例如09:30。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Style.soft, in: RoundedRectangle(cornerRadius: 10))
            if context.task == nil {
                Picker("重复", selection: $draft.repeatKind) {
                    ForEach(RepeatKind.allCases) { item in Text(item.rawValue).tag(item) }
                }.pickerStyle(.segmented)
                if draft.repeatKind != .once {
                    HStack {
                        Text("安排至")
                        DatePicker("重复结束日期", selection: dateBinding(\.until), displayedComponents: .date).labelsHidden()
                        Spacer()
                        Text("最多366天").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if draft.repeatKind == .custom {
                    HStack {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            Toggle(["", "日", "一", "二", "三", "四", "五", "六"][day], isOn: Binding(
                                get: { draft.weekdays.contains(day) },
                                set: { if $0 { draft.weekdays.insert(day) } else { draft.weekdays.remove(day) } }
                            )).toggleStyle(.button)
                        }
                    }
                }
                if let count = try? currentDraft().makeTasks().count, count > 1 {
                    Text("将保存 \(count) 次每日安排，每天分别记录进度。").font(.caption).foregroundStyle(.secondary)
                }
            } else if context.task?.seriesID != nil {
                Toggle("同时修改本次及后续尚未开始、没有记录的同组工作", isOn: $series)
                Text("重复日期不会移动；已有历史不会改变。").font(.caption).foregroundStyle(.secondary)
            }
            Picker("归属目标", selection: Binding(get: { draft.goalID ?? "" }, set: { draft.goalID = $0.isEmpty ? nil : $0 })) {
                Text("不归属目标").tag("")
                ForEach(state.goals) { goal in Text(goal.title).tag(goal.id) }
            }
            Text("提醒尚未启用，保存安排不会设置系统闹钟。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func dateBinding(_ key: WritableKeyPath<PlanDraft, String>) -> Binding<Date> {
        Binding(get: { (try? Day.date(draft[keyPath: key], time: 720)) ?? Date() }, set: { draft[keyPath: key] = Day.string($0) })
    }

    private func currentDraft() throws -> PlanDraft {
        var value = draft
        value.start = try Day.parseClock(clock.startText); value.end = try Day.parseClock(clock.endText)
        value.nextDay = clock.nextDay
        return value
    }
    private func prepare() {
        do {
            let value = try currentDraft()
            _ = try value.makeTasks()
            if let task = context.task {
                comparison = try state.requireRepository().editableTasks(taskID: task.id, series: series, now: Date())
                problem = nil
            } else {
                try state.requireRepository().add(value, now: Date())
                state.didSave("安排已保存在本机"); dismiss()
            }
        } catch { problem = error.localizedDescription }
    }
    private func comparisonView(_ tasks: [WorkItem]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认后修改 \(tasks.count) 项未来安排").font(.headline)
            if let old = tasks.first(where: { $0.id == context.task?.id }) {
                Text("修改前\n\(old.title) · \(old.category.isEmpty ? "无分类" : old.category)\n\(old.day) · \(old.rangeLabel)")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("修改后\n\(draft.title) · \(draft.category.isEmpty ? "无分类" : draft.category)\n\(draft.day) · \(range?.label ?? "无效时段")")
                    .fixedSize(horizontal: false, vertical: true)
                Text("目标：\(state.goals.first { $0.id == old.goalID }?.title ?? "无") → \(state.goals.first { $0.id == draft.goalID }?.title ?? "无")")
                    .font(.callout)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tasks) { task in Text("\(task.day) · \(task.title)").font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 100)
            Text("历史不回改。保存时会再次检查是否已经开始，防止修改过期安排。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func saveEdit() {
        guard let task = context.task, let comparison else { return }
        do {
            try state.requireRepository().edit(taskID: task.id, draft: currentDraft(), series: series, now: Date(), expected: comparison)
            state.didSave("未来安排已修改，历史保留"); dismiss()
        } catch { problem = error.localizedDescription }
    }
}
