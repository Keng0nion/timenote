import Foundation
import GRDB

extension NativeChecks {
    static func actionChecks(root: URL, now: Date) throws {
        let repo = try Repository(path: root.appendingPathComponent("actions.sqlite").path)
        let goal = try repo.addGoal(title: "完成学习目标"), other = try repo.addGoal(title: "另一个目标")
        var draft = PlanDraft(title: "每日练习", category: "学习", day: "2026-09-07", start: 480, end: 540)
        draft.repeatKind = .daily; draft.until = "2026-09-20"
        try repo.add(draft, now: now)
        var reading = draft; reading.title = "每日阅读"; reading.start = 600; reading.end = 630
        try repo.add(reading, now: now)
        try check(WorkAction.grouped([]).isEmpty, "空清单分组不创建行动")
        let two = WorkAction.grouped(try repo.tasks())
        try check(two.count == 2 && two.allSatisfy { $0.tasks.count == 14 }, "两组28次每日安排只显示两项行动")
        let practice = two.first { $0.title == draft.title }!, read = two.first { $0.title == reading.title }!
        try check(practice.isRecurring && practice.dateLabel == "2026-09-07 至 2026-09-20", "持续行动显示完整日期范围")
        try check(practice.matches("2026-09-15") && practice.matches(" 学习 ") && !practice.matches("不匹配"), "名称分类日期搜索匹配整组")
        try check(WorkAction.grouped(try repo.tasks()).filter { $0.matches("2026-09-15") }.allSatisfy { $0.tasks.count == 14 }, "搜索某一天不把整组缩成一天")
        try repo.add(draft, now: now)
        try repo.add(PlanDraft(title: draft.title, day: draft.day, start: 480, end: 540), now: now)
        try check(WorkAction.grouped(try repo.tasks()).count == 4, "同名但不同重复安排及单次工作不误合并")
        let reversed = Array(try repo.tasks().reversed())
        try check(WorkAction.grouped(reversed) == WorkAction.grouped(try repo.tasks()), "分组与成员顺序稳定，不依赖读取顺序")
        let single = WorkAction.grouped(try repo.tasks()).first { !$0.isRecurring }!
        try check(single.tasks.count == 1 && single.dateLabel == draft.day, "单次工作仍独立显示")
        try check(practice.destinationDay(relativeTo: "2026-09-10") == "2026-09-10" && practice.destinationDay(relativeTo: "2026-10-01") == "2026-09-20", "行动跳转今日或最近已安排日期")
        var varied = practice.tasks
        varied[varied.count - 1].title = "新的练习名称"; varied[varied.count - 1].start = 510
        let variedAction = WorkAction.grouped(varied)[0]
        try check(variedAction.title == "新的练习名称" && variedAction.matches("每日练习") && variedAction.hasTitleChanges, "同一组改名仍一项且可按旧名称搜索")
        try check(variedAction.timeLabel == "时段按日期安排", "同一组时段变化不冒称每天同一时间")
        var progress = practice.tasks
        progress[0].percent = 100; progress[1].percent = 50; progress[2].percent = 100
        let action = WorkAction.grouped(progress)[0], accumulation = action.progress(through: "2026-09-08")
        try check(accumulation.scheduledDays == 2 && accumulation.recordedDays == 2 && accumulation.completedDays == 1, "行动积累按天统计，部分进度不是完成且排除未来")
        let blank = read.progress(through: "2026-09-08")
        try check(blank.recordedDays == 0 && blank.completedDays == 0 && blank.scheduledDays == 2, "未记录不当完成，不凭空产生记录")
        try check(practice.progress(through: "2026-09-06").scheduledDays == 0, "尚未开始行动不把未来当漏记")
        var duplicate = progress[0]; duplicate.id = UUID().uuidString; duplicate.percent = nil
        let sameDay = WorkAction.grouped([progress[0], duplicate])[0].progress(through: "2026-09-08")
        try check(sameDay.scheduledDays == 1 && sameDay.recordedDays == 1 && sameDay.completedDays == 0, "同日多个成员按天去重且全部完成才算一天完成")
        try repo.record(taskID: practice.tasks[0].id, percent: 100, note: "历史备注", now: now)
        try repo.record(taskID: practice.tasks[1].id, percent: 50, note: "今天进度", now: now)
        var current = WorkAction.grouped(try repo.tasks()).first { $0.id == practice.id }!
        try repo.setGoal(taskID: current.tasks[0].id, goalID: other.id, expected: current.tasks[0])
        current = WorkAction.grouped(try repo.tasks()).first { $0.id == practice.id }!
        let before = try repo.tasks(), backup = try repo.backup()
        let histories = try before.map { try repo.entries(taskID: $0.id) }
        try check(current.tasks.contains { $0.goalID == other.id } && current.tasks.contains { $0.goalID == nil }, "已有零散归属可作为整组预览，读取不自动改归属")
        try repo.setGoal(action: current, goalID: goal.id)
        let linked = try repo.tasks()
        let wanted = before.map { task -> WorkItem in var changed = task; if changed.seriesID == current.tasks[0].seriesID { changed.goalID = goal.id }; return changed }
        try check(linked == wanted, "整组过去今日未来一起加入，只改goalID且不影响同名其他组")
        try check(try linked.map { try repo.entries(taskID: $0.id) } == histories, "整组归属不改每日进度备注及历史")
        try check(try Statistics.summary(linked).completionPercent == Statistics.summary(before).completionPercent, "整组关联前后加权统计不变")
        let linkedAction = WorkAction.grouped(linked).first { $0.id == current.id }!
        try check(WorkAction.grouped(linked.filter { $0.goalID == goal.id }).count == 1, "目标内部14天只显示一项持续行动")
        let linkedBackup = try repo.backup()
        try repo.setGoal(action: linkedAction, goalID: goal.id)
        try check(try repo.backup() == linkedBackup, "重复加入整组不增加工作或记录")
        try check(try Repository(path: repo.path).backup() == linkedBackup, "整组归属数据库重开保留")
        let restore = try Repository(path: root.appendingPathComponent("actions-restored.sqlite").path)
        try restore.importBackup(linkedBackup)
        try check(try restore.backup() == linkedBackup, "整组归属仍能用版本1备份完整往返")
        try rejects("旧备份归属冲突拒绝覆盖整组") { try repo.importBackup(backup) }
        try check(try repo.backup() == linkedBackup, "旧备份冲突后保留完整整组归属")
        try rejects("整组拒绝不存在目标") { try repo.setGoal(action: linkedAction, goalID: UUID().uuidString) }
        try check(try repo.backup() == linkedBackup, "无效目标不留下部分关联")
        try rejects("任何旧归属快照不能覆盖整组") { try repo.setGoal(action: current, goalID: nil) }
        try check(try repo.backup() == linkedBackup, "过时整组操作完全不写入")
        try repo.setGoal(action: linkedAction, goalID: other.id)
        let moved = WorkAction.grouped(try repo.tasks()).first { $0.id == current.id }!
        try check(moved.tasks.allSatisfy { $0.goalID == other.id } && repo.tasks().count == before.count, "换目标整组移动不复制")
        try repo.setGoal(action: moved, goalID: nil)
        let detached = WorkAction.grouped(try repo.tasks()).first { $0.id == current.id }!
        try check(detached.tasks.allSatisfy { $0.goalID == nil } && repo.entries(taskID: detached.tasks[0].id) == histories[before.firstIndex { $0.id == detached.tasks[0].id }!], "移出整组保留每日安排与历史")
        try rejects("整组关联后历史时段保护仍生效") { try repo.edit(taskID: detached.tasks[0].id, draft: PlanDraft(task: detached.tasks[0]), series: false, now: now) }
        try repo.record(taskID: detached.tasks[1].id, percent: 75, note: "选择期间有新记录", now: now)
        let newer = try repo.backup()
        try rejects("非首成员进度变化拒绝整组旧快照") { try repo.setGoal(action: detached, goalID: goal.id) }
        try check(try repo.backup() == newer, "过时整组不覆盖新进度")
        let fresh = WorkAction.grouped(try repo.tasks()).first { $0.id == detached.id }!
        try repo.setGoal(action: fresh, goalID: goal.id)
        try check(try repo.tasks().first { $0.id == detached.tasks[1].id }?.percent == 75, "重新选择整组后保留最新进度")
        let connection = try DatabaseQueue(path: repo.path)
        let readSnapshot = WorkAction.grouped(try repo.tasks()).first { $0.id == read.id }!
        var extra = readSnapshot.tasks.last!; extra.id = UUID().uuidString; extra.day = "2026-09-21"
        try connection.write { try extra.insert($0) }
        let added = try repo.backup()
        try rejects("整组期间新增成员必须重新预览") { try repo.setGoal(action: readSnapshot, goalID: goal.id) }
        try check(try repo.backup() == added, "新增成员冲突不留下半组关联")
        let more = WorkAction.grouped(try repo.tasks()).first { $0.id == read.id }!
        try connection.write { try $0.execute(sql: "DELETE FROM work WHERE id = ?", arguments: [extra.id]) }
        let removed = try repo.backup()
        try rejects("整组期间移除成员必须重新预览") { try repo.setGoal(action: more, goalID: goal.id) }
        try check(try repo.backup() == removed, "成员移除冲突不留下部分写入")
        try repo.setGoal(action: single, goalID: goal.id)
        try check(try repo.tasks().first { $0.id == single.tasks[0].id }?.goalID == goal.id, "同一接口也可关联单次工作")
        let rollbackAction = WorkAction.grouped(try repo.tasks()).first { $0.id == read.id }!
        let beforeFailure = try repo.backup()
        try connection.write { db in
            try db.execute(sql: """
                CREATE TRIGGER interrupt_action BEFORE UPDATE OF goalID ON work
                WHEN OLD.id = '\(rollbackAction.tasks[1].id)'
                BEGIN
                    SELECT CASE WHEN (SELECT goalID FROM work WHERE id = '\(rollbackAction.tasks[0].id)') = '\(goal.id)'
                        THEN RAISE(ABORT, '故意在首成员写入后中断') END;
                END
                """)
        }
        try rejects("首成员实际写入后数据库故障中断整组") { try repo.setGoal(action: rollbackAction, goalID: goal.id) }
        try check(try repo.backup() == beforeFailure, "整组中途故障回滚全部归属与记录")
        try connection.write { try $0.execute(sql: "DROP TRIGGER interrupt_action") }
        try repo.setGoal(action: rollbackAction, goalID: goal.id)
        try check(try repo.tasks().filter { $0.seriesID == rollbackAction.tasks[0].seriesID }.allSatisfy { $0.goalID == goal.id }, "故障移除后原快照可完整保存")
    }
}
