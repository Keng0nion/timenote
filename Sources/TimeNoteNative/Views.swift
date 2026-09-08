import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: AppState
    private let minute = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("时间便签", systemImage: "note.text").font(.system(size: 19, weight: .semibold))
                    .padding(.top, 18).padding(.bottom, 24)
                ForEach(AppState.Page.allCases) { page in
                    Button { state.page = page } label: {
                        Label(page.rawValue, systemImage: page.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 11).padding(.horizontal, 10)
                            .background(state.page == page ? Style.soft : .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).foregroundStyle(state.page == page ? Style.accent : .primary)
                        .accessibilityIdentifier("page-\(page.id)")
                }
                Spacer()
                Text("0.1.0 · 公开预览版").font(.caption).foregroundStyle(.secondary)
                Text("严格提醒尚未启用").font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(width: 200).background(Style.panel.opacity(0.45))
            Divider()
            VStack(spacing: 0) {
                Group {
                    switch state.page {
                    case .today: TodayView()
                    case .goals: GoalsView()
                    case .review: ReviewView()
                    case .settings: SettingsView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack {
                    Image(systemName: state.repository == nil ? "exclamationmark.triangle" : "internaldrive")
                    Text(state.status).lineLimit(2)
                    Spacer()
                    Text("不上传 · 不需账号")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 10)
            }
        }
        .background(Style.background).tint(Style.accent)
        .frame(minWidth: 920, minHeight: 660)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .sheet(item: $state.editor) { context in PlanEditor(context: context).environmentObject(state) }
        .sheet(item: $state.recordTask) { task in RecordEditor(task: task).environmentObject(state) }
        .sheet(item: $state.historyTask) { task in HistoryView(task: task).environmentObject(state) }
        .sheet(isPresented: $state.showGoal) { GoalEditor().environmentObject(state) }
        .sheet(isPresented: Binding(get: { state.importPreview != nil }, set: { if !$0 { state.importPreview = nil; state.importData = nil } })) {
            ImportSheet().environmentObject(state)
        }
        .alert("操作未完成", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("知道了") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .onReceive(minute) { date in
            let wasToday = state.day == Day.string(state.now)
            state.now = date
            if wasToday { state.selectedDate = date }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(state.day == Day.string(state.now) ? "今天，按自己的节奏" : "每日清单")
                        .font(.system(size: 25, weight: .semibold))
                    Text(state.selectedDate.formatted(.dateTime.year().month(.wide).day().weekday(.wide)))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.newWork() } label: { Label("新增工作", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("add-work")
                    .disabled(state.repository == nil)
            }
            HStack {
                Button { state.stepDay(-1) } label: { Image(systemName: "chevron.left") }.help("前一天")
                DatePicker("日期", selection: $state.selectedDate, displayedComponents: .date).labelsHidden().frame(width: 145)
                Button { state.stepDay(1) } label: { Image(systemName: "chevron.right") }.help("后一天")
                Button("回到今天") { state.selectedDate = Date() }
                Spacer()
                Text("\(state.dayTasks.count) 项安排").foregroundStyle(.secondary)
            }
            SummaryBar(tasks: state.day > Day.string(state.now) ? state.dayTasks.map { var t = $0; t.percent = nil; return t } : state.dayTasks)
            if state.dayTasks.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "note.text.badge.plus").font(.system(size: 40, weight: .light)).foregroundStyle(Style.accent)
                    Text("这一天还没有安排").font(.title3)
                    Text("写下一件想做的事，再选每天几点到几点。\n休息的日子不计作 0%。")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("添加第一项工作") { state.newWork() }.controlSize(.large).disabled(state.repository == nil)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.dayTasks) { task in
                            WorkRow(task: task)
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                Text(state.day > Day.string(state.now) ? "未来安排只显示计划，不提前计入历史成绩。" : "未记录不等于没完成。点百分比记录进展，原计划和每次修改都会留下。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28)
    }
}

struct WorkRow: View {
    @EnvironmentObject var state: AppState
    let task: WorkItem
    var body: some View {
        HStack(spacing: 14) {
            Button {
                _ = state.perform("已记录完成，保留历史") { try state.requireRepository().record(taskID: task.id, percent: 100, note: "", now: Date()) }
            } label: {
                Image(systemName: task.percent == 100 ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 25, weight: .light)).foregroundStyle(task.percent == 100 ? Style.accent : .secondary)
                    .frame(width: 34, height: 40)
            }.buttonStyle(.plain).help("记录为100%完成")
                .disabled(task.day > Day.string(state.now) || task.percent == 100)
            VStack(alignment: .leading, spacing: 7) {
                Text(task.title).font(.system(size: 16, weight: .medium)).lineLimit(2)
                HStack(spacing: 12) {
                    Text(task.rangeLabel).monospacedDigit()
                    if !task.category.isEmpty { Text(task.category) }
                    if task.seriesID != nil { Image(systemName: "repeat").help("重复安排") }
                }.font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button(task.day > Day.string(state.now) ? "待开始" : Statistics.percentLabel(task.percent)) { state.recordTask = task }
                .buttonStyle(.bordered).frame(minWidth: 70).disabled(task.day > Day.string(state.now))
            Menu {
                Button("记录进展…") { state.recordTask = task }.disabled(task.day > Day.string(state.now))
                Button("查看历史…") { state.historyTask = task }
                Button("修改未来安排…") { state.editWork(task) }.disabled(!task.editable(at: state.now))
                Divider()
                Button("撤销最后一次手动记录") {
                    _ = state.perform("已追加撤销记录") { try state.requireRepository().undoLast(taskID: task.id, now: Date()) }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 18, height: 24) }
                .menuStyle(.borderlessButton).fixedSize().help("更多操作")
        }.padding(.vertical, 15)
    }
}

struct RecordEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let task: WorkItem
    @State private var percent = ""
    @State private var note = ""
    @State private var problem: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("记录进展").font(.title2.bold())
            Text(task.title).font(.title3)
            Text("\(task.day) · \(task.rangeLabel)").foregroundStyle(.secondary)
            HStack {
                TextField("0 至 100", text: $percent).textFieldStyle(.roundedBorder).frame(width: 110).focused($focused)
                Text("%")
                Spacer()
                ForEach([0, 25, 50, 75, 100], id: \.self) { value in
                    Button("\(value)%") { percent = String(value) }
                }
            }
            TextField("原因或备注（可不填，最多1000字）", text: $note, axis: .vertical)
                .lineLimit(3...5).textFieldStyle(.roundedBorder)
            Text("只记录计划完成程度，不等于实际工作时间。旧记录会保留。")
                .font(.caption).foregroundStyle(.secondary)
            if let problem { Text(problem).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存进展") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 550)
            .onAppear { percent = task.percent.map { String($0) } ?? ""; focused = true }
    }
    private func save() {
        guard let value = Double(percent.trimmingCharacters(in: .whitespacesAndNewlines)) else { problem = "请填写0至100的数字。"; return }
        do {
            try state.requireRepository().record(taskID: task.id, percent: value, note: note, now: Date())
            state.didSave("进展已保存"); dismiss()
        } catch { problem = error.localizedDescription }
    }
}

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let task: WorkItem
    @State private var entries: [Entry] = []
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("记录历史").font(.title2.bold()); Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction) }
            Text(task.title).font(.title3)
            Text("原计划：\(task.day) · \(task.rangeLabel)\n时区：\(task.zone)").foregroundStyle(.secondary)
            Divider()
            if let problem { Text(problem).foregroundStyle(.red) }
            if entries.isEmpty { Text("还没有进度记录。原计划已经保存在本机。").foregroundStyle(.secondary) }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(entry.kind + " · " + Statistics.percentLabel(entry.percent)).bold(); Spacer() }
                            Text(Date(timeIntervalSince1970: entry.recordedAt).formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if !entry.note.isEmpty { Text(entry.note).textSelection(.enabled) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(28).frame(width: 540, height: 480)
            .onAppear {
                do { entries = try state.requireRepository().entries(taskID: task.id) }
                catch { problem = error.localizedDescription }
            }
    }
}
