import SwiftUI

struct GoalAssignmentSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var action: WorkAction
    @State private var selectedID: String?
    @State private var chose = false
    @State private var problem: String?

    init(task: WorkItem, tasks: [WorkItem]) {
        let group = WorkAction.grouped(tasks).first { $0.id == WorkAction.key(for: task) }
            ?? WorkAction.grouped([task])[0]
        _action = State(initialValue: group)
        _selectedID = State(initialValue: task.goalID)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("调整长期目标").font(.title2.bold())
            VStack(alignment: .leading, spacing: 6) {
                Text(action.title).font(.headline).lineLimit(2)
                Text(action.scheduleLabel).font(.caption).foregroundStyle(.secondary)
            }
            if state.goals.isEmpty {
                Text("还没有长期目标。请先取消，在“长期目标”页新增目标，再回来加入工作。")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.goals) { goal in
                            GoalChoiceRow(title: goal.title,
                                          subtitle: action.tasks.allSatisfy { $0.goalID == goal.id } ? "当前目标" : nil,
                                          selected: selectedID == goal.id) { selectedID = goal.id; chose = true; problem = nil }
                                .accessibilityIdentifier("select-goal-\(goal.id)")
                        }
                        if action.tasks.contains(where: { $0.goalID != nil }) {
                            GoalChoiceRow(title: "不属于长期目标", subtitle: "移出目标，保留每日工作",
                                          selected: chose && selectedID == nil) { selectedID = nil; chose = true; problem = nil }
                                .accessibilityIdentifier("select-goal-none")
                        }
                    }
                }.frame(maxHeight: .infinity)
            }
            GoalChangeSummary(action: action, goalID: selectedID).environmentObject(state)
            if let problem { Text(problem).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存归属") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!chose || action.tasks.allSatisfy { $0.goalID == selectedID } || state.repository == nil)
            }
        }.padding(28).frame(width: 540, height: 560).background(Style.background).tint(Style.accent)
    }
    private func save() {
        do {
            try state.requireRepository().setGoal(action: action, goalID: selectedID)
            state.didSave(selectedID == nil ? "已移出目标，每日工作与记录保留" : "已保存行动归属，每日工作与记录保留")
            dismiss()
        } catch { problem = error.localizedDescription }
    }
}

struct ExistingWorkSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    let goal: Goal
    @State private var query = ""
    @State private var selected: WorkAction?
    @State private var problem: String?
    @FocusState private var searchFocused: Bool

    func groupedCandidates(_ tasks: [WorkItem]) -> [WorkAction] {
        WorkAction.grouped(tasks).filter { $0.tasks.contains { $0.goalID != goal.id } }
    }
    private var candidates: [WorkAction] { groupedCandidates(state.tasks) }
    private var matches: [WorkAction] { candidates.filter { $0.matches(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("加入已有工作").font(.title2.bold())
            Text("加入目标：\(goal.title)").font(.headline).lineLimit(2)
            TextField("搜索工作名称、分类或日期", text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
                .onChange(of: query) { _, _ in selected = nil; problem = nil }
            Text("同一重复安排只显示一次，加入后作为推进目标的持续行动。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if matches.isEmpty {
                        Text(candidates.isEmpty ? "没有可加入的工作。可以回到每日清单新增，或使用“安排工作”。" : "没有匹配的工作，换一个名称、分类或日期试试。")
                            .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                    }
                    ForEach(matches) { action in
                        GoalChoiceRow(title: action.title,
                                      subtitle: action.scheduleLabel + "\n" + action.ownershipLabel(goals: state.goals),
                                      selected: selected?.id == action.id) { selected = action; problem = nil }
                            .accessibilityIdentifier("existing-action-\(action.id)")
                    }
                }
            }.frame(maxHeight: .infinity)
            if let selected { GoalChangeSummary(action: selected, goalID: goal.id).environmentObject(state) }
            else { Text("选一次，关联整组已安排日期；每日仍分别记录，不复制、不改时间或进度。")
                    .font(.caption).foregroundStyle(.secondary) }
            if let problem { Text(problem).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("加入目标") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || state.repository == nil)
            }
        }.padding(28).frame(width: 580, height: 590).background(Style.background).tint(Style.accent)
            .onAppear { searchFocused = true }
    }
    private func save() {
        guard let selected else { return }
        do {
            try state.requireRepository().setGoal(action: selected, goalID: goal.id)
            state.didSave("已加入目标，持续行动按天积累，原工作与记录保留")
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
                    if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
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
    let action: WorkAction
    let goalID: String?
    private var ownership: [String: Int] {
        Dictionary(grouping: action.tasks, by: { $0.goalID ?? "" }).mapValues(\.count)
    }
    private func title(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "未加入目标" }
        return state.goals.first { $0.id == id }?.title ?? "原目标已不可用"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if action.tasks.contains(where: { $0.goalID != goalID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ownership.keys.sorted(), id: \.self) { id in
                            Text("原归属：\(title(id)) · \(ownership[id]!)次安排")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: min(CGFloat(ownership.count) * 22, 66))
                Text("新归属：\(title(goalID))").foregroundStyle(Style.accent)
                if action.tasks.contains(where: { $0.goalID != nil && $0.goalID != goalID }) {
                    Text("保存后，所列安排会从原目标移出。")
                }
            }
            if action.hasTitleChanges { Text("这组曾改过名称，其他名称下的同组日期也一起处理。").foregroundStyle(.secondary) }
            Text(action.isRecurring ? "整组\(action.tasks.count)次安排一起调整（含过去与未来）；每天的时间、进度和历史不变。" : "只调整这项工作的归属，时间、进度和历史不变。")
                .foregroundStyle(.secondary)
        }.font(.caption).fixedSize(horizontal: false, vertical: true)
    }
}
