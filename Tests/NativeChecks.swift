import Foundation
import GRDB

struct CheckFailure: Error { let message: String }
func check(_ value: Bool, _ message: String) throws {
    guard value else { throw CheckFailure(message: message) }
    print("通过：\(message)")
}
func rejects(_ message: String, _ body: () throws -> Void) throws {
    do { try body() } catch { print("通过：\(message)"); return }
    throw CheckFailure(message: message + "未拒绝")
}

@main struct NativeChecks {
    @MainActor static func main() {
        do { try run() }
        catch { print("检查失败：\(error)"); exit(1) }
    }
    @MainActor static func run() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("tasks.sqlite").path
        let repo = try Repository(path: path)
        let now = try Day.date("2026-09-08", time: 600)
        try check(try repo.tasks().isEmpty, "空库不注入示例")
        try check(try TimeRange(start: 570, end: 645, nextDay: false).minutes == 75, "起止自动换算")
        try check(try TimeRange(start: 1410, end: 45, nextDay: true).minutes == 75, "跨日75分钟")
        try check(try TimeRange(start: 600, end: 600, nextDay: true).minutes == 1440, "24小时时段")
        try rejects("反向时段") { _ = try TimeRange(start: 600, end: 500, nextDay: false) }
        try rejects("超24小时") { _ = try TimeRange(start: 600, end: 700, nextDay: true) }
        try rejects("非法日期") { _ = try Day.date("2026-02-30") }
        var draft = PlanDraft(title: "学习", category: "自学", day: "2026-09-08", start: 660, end: 690)
        draft.repeatKind = .weekdays; draft.until = "2026-09-14"
        let repeated = try draft.makeTasks()
        try check(repeated.map(\.day) == ["2026-09-08", "2026-09-09", "2026-09-10", "2026-09-11", "2026-09-14"], "工作日重复日期")
        try repo.add(draft, now: now)
        try check(try repo.tasks().count == 5, "重复一次事务写入")
        var custom = draft; custom.repeatKind = .custom; custom.weekdays = []
        try rejects("未选周几") { _ = try custom.makeTasks() }
        let goal = try repo.addGoal(title: "完成第一章")
        try check(try repo.goals().count == 1, "手动新增长期目标")
        let a = PlanDraft(title: "阅读", category: "学习", day: "2026-09-08", start: 480, end: 510, goalID: goal.id)
        let b = PlanDraft(title: "写作", category: "写作", day: "2026-09-08", start: 510, end: 600)
        try repo.add(a, now: now); try repo.add(b, now: now)
        let first = try repo.tasks().first { $0.title == "阅读" }!
        let second = try repo.tasks().first { $0.title == "写作" }!
        try repo.record(taskID: first.id, percent: 100, note: "", now: now)
        try repo.record(taskID: second.id, percent: 50, note: "写了一半", now: now)
        var today = try repo.tasks().filter { $0.day == "2026-09-08" }
        var summary = try Statistics.summary(today)
        try check(summary.completionPercent == 62.5 && summary.missingCount == 1, "62.5%加权，未记录单列")
        try repo.record(taskID: first.id, percent: 35, note: "修正", now: now)
        today = try repo.tasks().filter { $0.day == "2026-09-08" }
        summary = try Statistics.summary(today)
        try check(summary.completionPercent == 46.25, "百分比修正按原时长加权")
        try check(try repo.entries(taskID: first.id).count == 2, "追加记录不覆盖历史")
        try repo.undoLast(taskID: first.id, now: now)
        try check(try repo.entries(taskID: first.id).count == 3, "撤销追加恢复记录")
        try check(try repo.tasks().first { $0.id == first.id }?.percent == 100, "撤销恢复100%")
        try rejects("未来不可填成绩") {
            let future = try repo.tasks().first { $0.day == "2026-09-09" }!
            try repo.record(taskID: future.id, percent: 10, note: "", now: now)
        }
        try rejects("非法进度不写入") { try repo.record(taskID: first.id, percent: 101, note: "", now: now) }
        try rejects("历史安排保护") { try repo.edit(taskID: first.id, draft: a, series: false, now: now) }
        let upcoming = try repo.tasks().first { $0.day == "2026-09-09" }!
        var edit = PlanDraft(task: upcoming); edit.title = "修改后的学习"; edit.start = 720; edit.end = 750
        try repo.edit(taskID: upcoming.id, draft: edit, series: true, now: now)
        try check(try repo.tasks().filter { $0.title == "修改后的学习" }.count == 4, "重复修改仅选中及后续未来")
        try check(try repo.tasks().contains { $0.day == "2026-09-08" && $0.title == "学习" }, "不改前面日期节奏")
        let reopened = try Repository(path: path)
        try check(try reopened.tasks() == repo.tasks(), "数据库重开及迁移重入无损")
        let backup = try repo.backup()
        let restored = try Repository(path: root.appendingPathComponent("restored.sqlite").path)
        let preview = try restored.previewImport(backup)
        try check(preview.newTasks == 7 && preview.newGoals == 1, "备份预览数量")
        try restored.importBackup(backup)
        try check(try restored.tasks() == repo.tasks(), "备份恢复任务历史无损")
        try restored.importBackup(backup)
        try check(try restored.tasks().count == 7, "重复导入不重复任务")
        try restored.record(taskID: first.id, percent: 70, note: "冲突", now: now)
        try rejects("编号冲突拒绝覆盖") { try restored.importBackup(backup) }
        try check(try restored.tasks().first { $0.id == first.id }?.percent == 70, "冲突保留现有记录")
        try rejects("非法备份不写入") { try restored.importBackup(Data("{}".utf8)) }
        try check(try restored.tasks().count == 7, "失败不留半份数据")
        try check(try Statistics.summary([]).status == .noPlan, "无计划不是0%")
        let zero = try Repository(path: root.appendingPathComponent("zero.sqlite").path)
        var standalone = a; standalone.goalID = nil
        try zero.add(standalone, now: now)
        let z = try zero.tasks()[0]
        try zero.record(taskID: z.id, percent: 0, note: "", now: now)
        try check(try Statistics.summary(zero.tasks()).completionPercent == 0, "明确0%不是未记录")
        try zero.undoLast(taskID: z.id, now: now)
        try check(try zero.tasks()[0].percent == nil, "撤销首条恢复未记录")
        try check(try zero.entries(taskID: z.id).count == 2, "恢复未记录也留历史")
        var clock = TimeInput(start: 540, end: 600, nextDay: false)
        clock.setStart(""); clock.setStart("10:30")
        try check(clock.endText == "11:30", "清空再输入开始保留原时长")
        clock.setEnd("12:00"); clock.setStart("11:00")
        try check(clock.endText == "12:30", "单独改结束后按新时长平移")
        clock.setEnd(""); clock.setStart("13:00")
        try check(clock.endText.isEmpty, "主动清空结束不自动补回")
        var overnight = TimeInput(start: 1380, end: 0, nextDay: true)
        overnight.setStart("23:30")
        try check(overnight.endText == "00:30" && overnight.nextDay, "原生时间跨日平移")
        let before = try repo.backup()
        var invalidGoal = b; invalidGoal.goalID = UUID().uuidString
        invalidGoal.repeatKind = .daily; invalidGoal.until = "2026-09-10"
        try rejects("无效目标整批回滚") { try repo.add(invalidGoal, now: now) }
        try check(try repo.backup() == before, "整批失败无任务或历史残留")
        let damaged = root.appendingPathComponent("damaged.sqlite")
        try Data("不是数据库".utf8).write(to: damaged)
        try rejects("损坏库不清空重建") { _ = try Repository(path: damaged.path) }
        try check(try Data(contentsOf: damaged) == Data("不是数据库".utf8), "损坏文件原样保留")
        var wrong = try JSONDecoder().decode(Backup.self, from: before)
        wrong.version = 999
        try rejects("拒绝新版本备份") { try repo.importBackup(JSONEncoder().encode(wrong)) }
        wrong.version = 1; wrong.tasks.append(wrong.tasks[0])
        try rejects("备份重复编号拒绝") { try repo.importBackup(JSONEncoder().encode(wrong)) }
        try check(try repo.backup() == before, "备份校验失败原数据未变")
        let state = AppState(folder: root.appendingPathComponent("refresh-failure"))
        let saved = state.perform("已保存", {
            let storage = try state.requireRepository()
            try storage.addGoal(title: "已实际保存的目标")
            let connection = try DatabaseQueue(path: storage.path)
            try connection.write { try $0.execute(sql: "DROP TABLE work") }
        })
        try check(try state.requireRepository().goals().count == 1, "刷新失败测试先确认真实写入")
        try check(saved, "写入成功后刷新失败仍不误报保存失败")
        try check(state.status.contains("已保存") && state.status.contains("刷新失败"), "刷新失败明确提示勿重复提交")
        let previewRepo = try Repository(path: root.appendingPathComponent("stale-preview.sqlite").path)
        let initial = PlanDraft(title: "原安排", day: "2026-09-09", start: 540, end: 600)
        try previewRepo.add(initial, now: now)
        let previewTask = try previewRepo.tasks()[0]
        let confirmed = try previewRepo.editableTasks(taskID: previewTask.id, series: false, now: now)
        var other = PlanDraft(task: previewTask); other.title = "其他窗口已修改"
        try previewRepo.edit(taskID: previewTask.id, draft: other, series: false, now: now)
        var proposed = PlanDraft(task: previewTask); proposed.title = "过时表单的修改"
        try rejects("对比后数据已变化拒绝过时确认") {
            try previewRepo.edit(taskID: previewTask.id, draft: proposed, series: false, now: now, expected: confirmed)
        }
        try check(try previewRepo.tasks()[0].title == other.title, "过时对比不覆盖新内容")
        let fresh = try previewRepo.editableTasks(taskID: previewTask.id, series: false, now: now)
        try previewRepo.edit(taskID: previewTask.id, draft: proposed, series: false, now: now, expected: fresh)
        try check(try previewRepo.tasks()[0].title == proposed.title, "重新确认最新对比可保存")
        try goalAssignmentChecks(root: root, now: now)
        try actionChecks(root: root, now: now)
        try cockpitChecks(root: root, now: now)
        print("原生数据检查全部通过；不代表标准 XCTest 或严格提醒通过。")
    }

    static func goalAssignmentChecks(root: URL, now: Date) throws {
        let repo = try Repository(path: root.appendingPathComponent("goal-assignment.sqlite").path)
        let goal = try repo.addGoal(title: "目标甲"), other = try repo.addGoal(title: "目标乙")
        var draft = PlanDraft(title: "每日练习", category: "学习", day: "2026-09-07", start: 480, end: 540)
        draft.repeatKind = .daily; draft.until = "2026-09-09"
        try repo.add(draft, now: now)
        let id = try repo.tasks()[0].id
        try repo.record(taskID: id, percent: 50, note: "保留原备注", now: now)
        try repo.record(taskID: id, percent: 100, note: "已完成", now: now)
        try repo.undoLast(taskID: id, now: now)
        let before = try repo.tasks(), entries = try repo.entries(taskID: id), oldBackup = try repo.backup()
        let task = before[0]
        try repo.setGoal(taskID: id, goalID: goal.id, expected: task)
        var expected = task; expected.goalID = goal.id
        let linked = try repo.tasks()
        try check(linked[0] == expected, "历史任务关联只改变目标，日期时段和进度不变")
        try check(linked.count == before.count && linked.dropFirst() == before.dropFirst(), "重复安排只关联选中单项，不复制或影响其他日期")
        try check(try repo.entries(taskID: id) == entries, "关联不改动任何进展、备注和撤销历史")
        try check(try Statistics.summary(linked).completionPercent == Statistics.summary(before).completionPercent,
                  "关联后整体统计不重复计数")
        try check(try Repository(path: repo.path).tasks() == linked, "目标关联在数据库重开后保留")
        try repo.setGoal(taskID: id, goalID: goal.id, expected: expected)
        let linkedBackup = try repo.backup()
        try check(try repo.tasks() == linked && repo.entries(taskID: id) == entries, "已加入同一目标不产生重复工作或记录")
        let restored = try Repository(path: root.appendingPathComponent("goal-restored.sqlite").path)
        try restored.importBackup(linkedBackup)
        try check(try restored.backup() == linkedBackup, "关联后的版本1备份完整往返")
        try rejects("旧备份归属不同拒绝覆盖") { try repo.importBackup(oldBackup) }
        try check(try repo.backup() == linkedBackup, "备份冲突不丢新的目标归属")
        try rejects("已记录工作关联后仍禁止改历史安排") {
            try repo.edit(taskID: id, draft: PlanDraft(task: expected), series: false, now: now)
        }
        try rejects("不存在的目标拒绝关联") {
            try repo.setGoal(taskID: id, goalID: UUID().uuidString, expected: expected)
        }
        try rejects("不存在的任务拒绝关联") {
            try repo.setGoal(taskID: UUID().uuidString, goalID: goal.id, expected: expected)
        }
        try rejects("不同任务的快照拒绝关联") {
            try repo.setGoal(taskID: id, goalID: other.id, expected: before[1])
        }
        try check(try repo.backup() == linkedBackup, "关联校验失败完全不写入")
        try repo.setGoal(taskID: id, goalID: other.id, expected: expected)
        var moved = expected; moved.goalID = other.id
        try check(try repo.tasks()[0] == moved && repo.tasks().filter { $0.goalID == goal.id }.isEmpty,
                  "更换目标移动归属而不是复制")
        let movedBackup = try repo.backup()
        try rejects("过时目标选择不覆盖新归属") {
            try repo.setGoal(taskID: id, goalID: nil, expected: expected)
        }
        try check(try repo.backup() == movedBackup, "过时归属操作不留下部分修改")
        try repo.setGoal(taskID: id, goalID: nil, expected: moved)
        try check(try repo.tasks() == before && repo.entries(taskID: id) == entries, "移出目标不删除任务或历史")
        let started = try repo.tasks()[1]
        try repo.setGoal(taskID: started.id, goalID: goal.id, expected: started)
        var startedLinked = started; startedLinked.goalID = goal.id
        try check(try repo.tasks()[1] == startedLinked, "已开始但未记录的工作可补充归属")
        try rejects("已开始工作关联后仍不能改时段") {
            try repo.edit(taskID: started.id, draft: PlanDraft(task: startedLinked), series: false, now: now)
        }
        let future = try repo.tasks()[2]
        try repo.setGoal(taskID: future.id, goalID: other.id, expected: future)
        var futureLinked = future; futureLinked.goalID = other.id
        try check(try repo.tasks()[2] == futureLinked, "未来工作可单独关联目标")
        try repo.record(taskID: id, percent: 75, note: "另一个窗口保存", now: now)
        let newer = try repo.backup()
        try rejects("选目标期间进度变化拒绝过时表单") {
            try repo.setGoal(taskID: id, goalID: goal.id, expected: task)
        }
        try check(try repo.backup() == newer, "过时表单不会覆盖较新的进度")
        let fresh = try repo.tasks()[0]
        try repo.setGoal(taskID: id, goalID: goal.id, expected: fresh)
        try check(try repo.tasks()[0].percent == 75 && repo.tasks()[0].goalID == goal.id, "重新打开最新任务后可关联并保留新进度")
    }
}
