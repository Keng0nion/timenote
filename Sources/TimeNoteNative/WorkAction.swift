import Foundation

struct WorkAction: Identifiable, Equatable, Sendable {
    let id: String
    let tasks: [WorkItem]
    private init(id: String, tasks: [WorkItem]) { self.id = id; self.tasks = tasks }

    var isRecurring: Bool { tasks[0].seriesID != nil }
    var title: String { tasks[tasks.count - 1].title }
    var hasTitleChanges: Bool { Set(tasks.map(\.title)).count > 1 }
    var dayCount: Int { Set(tasks.map(\.day)).count }
    var dateLabel: String {
        let first = tasks[0].day, last = tasks[tasks.count - 1].day
        return first == last ? first : "\(first) 至 \(last)"
    }
    var timeLabel: String {
        let labels = Set(tasks.map(\.rangeLabel))
        return labels.count == 1 ? tasks[0].rangeLabel : "时段按日期安排"
    }
    var scheduleLabel: String {
        "\(isRecurring ? "持续行动 · \(dayCount)天安排" : "单次工作") · \(dateLabel) · \(timeLabel)"
    }
    static func key(for task: WorkItem) -> String {
        task.seriesID.map { "series:" + $0 } ?? "task:" + task.id
    }
    static func grouped(_ tasks: [WorkItem]) -> [WorkAction] {
        Dictionary(grouping: tasks, by: key).map { id, members in
            WorkAction(id: id, tasks: members.sorted(by: ordered))
        }.sorted { ordered($0.tasks[0], $1.tasks[0]) }
    }
    private static func ordered(_ a: WorkItem, _ b: WorkItem) -> Bool {
        if a.day != b.day { return a.day < b.day }
        if a.start != b.start { return a.start < b.start }
        return a.id < b.id
    }
    func matches(_ query: String) -> Bool {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty || tasks.contains { task in
            [task.title, task.category, task.day].contains { $0.localizedStandardContains(search) }
        }
    }
    func destinationDay(relativeTo day: String) -> String {
        tasks.first { $0.day >= day }?.day ?? tasks[tasks.count - 1].day
    }
    func progress(through day: String) -> ActionProgress {
        let days = Dictionary(grouping: tasks.filter { $0.day <= day }, by: \.day).values
        return ActionProgress(scheduledDays: days.count,
                              recordedDays: days.filter { $0.contains { $0.percent != nil } }.count,
                              completedDays: days.filter { $0.allSatisfy { $0.percent == 100 } }.count)
    }
    func ownershipLabel(goals: [Goal]) -> String {
        let counts = Dictionary(grouping: tasks, by: { $0.goalID ?? "" })
        let parts = counts.keys.sorted().map { id in
            let name = id.isEmpty ? "未加入目标" : (goals.first { $0.id == id }?.title ?? "原目标已不可用")
            return "\(name)（\(counts[id]!.count)次）"
        }
        return parts.prefix(3).joined(separator: "、") + (parts.count > 3 ? "等\(parts.count)种归属" : "")
    }
}

struct ActionProgress: Equatable {
    let scheduledDays: Int
    let recordedDays: Int
    let completedDays: Int
    var label: String {
        scheduledDays == 0 ? "尚未到安排日期" : "截至今天：完成 \(completedDays) 天 · 已记录 \(recordedDays)/\(scheduledDays) 天"
    }
}
