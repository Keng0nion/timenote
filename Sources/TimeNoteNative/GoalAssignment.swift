import SwiftUI

struct GoalAssignmentSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let task: WorkItem
    @State private var selectedID: String?
    @State private var problem: String?

    init(task: WorkItem) {
        self.task = task
        _selectedID = State(initialValue: task.goalID)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(task.goalID == nil ? "加入长期目标" : "调整长期目标").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title).font(.headline)
                Text("\(task.day) · \(task.rangeLabel)").font(.callout).foregroundStyle(.secondary)
            }
            if state.goals.isEmpty {
                Text("还没有长期目标。请先取消，在“长期目标”页新增目标，再回来加入工作。")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.goals) { goal in
                            GoalChoiceRow(title: goal.title, subtitle: goal.id == task.goalID ? "当前目标" : nil,
                                          selected: selectedID == goal.id) { selectedID = goal.id; problem = nil }
                                .accessibilityIdentifier("select-goal-\(goal.id)")
                        }
                        if task.goalID != nil {
                            GoalChoiceRow(title: "不属于长期目标", subtitle: "只移出目标，保留每日工作",
                                          selected: selectedID == nil) { selectedID = nil; problem = nil }
                                .accessibilityIdentifier("select-goal-none")
                        }
                    }
                }.frame(maxHeight: .infinity)
            }
            GoalChangeSummary(task: task, goalID: selectedID).environmentObject(state)
            if let problem { Text(problem).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存归属") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selectedID == task.goalID || state.repository == nil)
            }
        }.padding(28).frame(width: 510, height: 530).background(Style.background).tint(Style.accent)
    }
    private func save() {
        do {
            try state.requireRepository().setGoal(taskID: task.id, goalID: selectedID, expected: task)
            state.didSave(selectedID == nil ? "已移出目标，每日工作与记录保留" : "已保存目标归属，每日工作与记录保留")
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}

struct ExistingWorkSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let goal: Goal
    @State private var query = ""
    @State private var selected: WorkItem?
    @State private var problem: String?
    @FocusState private var searchFocused: Bool

    private var candidates: [WorkItem] { state.tasks.filter { $0.goalID != goal.id } }
    private var matches: [WorkItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { task in
            search.isEmpty || [task.title, task.category, task.day].contains { $0.localizedStandardContains(search) }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("加入已有工作").font(.title2.bold())
            Text("加入目标：\(goal.title)").font(.headline).lineLimit(2)
            TextField("搜索工作名称、分类或日期", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
                .onChange(of: query) { _, _ in selected = nil; problem = nil }
            Text("选择一项，已在这个目标中的工作不再列出。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if matches.isEmpty {
                        Text(candidates.isEmpty ? "没有可加入的工作。可以回到每日清单新增，或使用“安排工作”。" : "没有匹配的工作，换一个名称、分类或日期试试。")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                    }
                    ForEach(matches) { task in
                        let owner = state.goals.first { $0.id == task.goalID }?.title
                        GoalChoiceRow(title: task.title,
                                      subtitle: "\(task.day) · \(task.rangeLabel) · \(owner.map { "现属：" + $0 } ?? "未加入目标")",
                                      selected: selected?.id == task.id) { selected = task; problem = nil }
                            .accessibilityIdentifier("existing-work-\(task.id)")
                    }
                }
            }.frame(maxHeight: .infinity)
            if let selected { GoalChangeSummary(task: selected, goalID: goal.id).environmentObject(state) }
            else { Text("仅关联同一项工作，不复制、不改时间或进度；重复安排也只处理选中的这一天。")
                    .font(.caption).foregroundStyle(.secondary) }
            if let problem { Text(problem).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("加入目标") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || state.repository == nil)
            }
        }.padding(28).frame(width: 580, height: 560).background(Style.background).tint(Style.accent)
            .onAppear { searchFocused = true }
    }
    private func save() {
        guard let selected else { return }
        do {
            try state.requireRepository().setGoal(taskID: selected.id, goalID: goal.id, expected: selected)
            state.didSave("已加入目标，每日清单中的同一工作与记录保留")
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}

private struct GoalChoiceRow: View {
    let title: String
    let subtitle: String?
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(Style.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.callout.weight(.medium)).lineLimit(2)
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(selected ? Style.soft : Style.panel, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

private struct GoalChangeSummary: View {
    @EnvironmentObject var state: AppState
    let task: WorkItem
    let goalID: String?
    private func title(_ id: String?) -> String {
        guard let id else { return "未加入目标" }
        return state.goals.first { $0.id == id }?.title ?? "原目标已不可用"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if goalID != task.goalID {
                Text("原归属：\(title(task.goalID))")
                Text("新归属：\(title(goalID))").foregroundStyle(Style.accent)
                if task.goalID != nil && goalID != nil { Text("保存后会从原目标移到新目标。") }
            }
            Text("只调整这一项的归属；每日清单、时间、进度和历史都保留，不改变其他重复日期。")
                .foregroundStyle(.secondary)
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
