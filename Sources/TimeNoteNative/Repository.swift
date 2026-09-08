import Foundation
import GRDB

final class Repository {
    private let database: DatabaseQueue
    let path: String

    init(path: String) throws {
        self.path = path
        database = try DatabaseQueue(path: path)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-local-history") { db in
            try db.create(table: "goal") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
            }
            try db.create(table: "work") { t in
                t.column("id", .text).primaryKey()
                t.column("seriesID", .text).indexed()
                t.column("title", .text).notNull()
                t.column("category", .text).notNull()
                t.column("goalID", .text).references("goal", onDelete: .restrict)
                t.column("day", .text).notNull().indexed()
                t.column("start", .integer).notNull().check { (0..<1440).contains($0) }
                t.column("minutes", .integer).notNull().check { (1...1440).contains($0) }
                t.column("zone", .text).notNull()
                t.column("percent", .double).check { (0...100).contains($0) }
            }
            try db.create(table: "entry") { t in
                t.column("id", .text).primaryKey()
                t.column("taskID", .text).notNull().indexed().references("work", onDelete: .restrict)
                t.column("percent", .double).check { (0...100).contains($0) }
                t.column("note", .text).notNull()
                t.column("recordedAt", .double).notNull()
                t.column("kind", .text).notNull()
            }
        }
        try migrator.migrate(database)
    }

    func tasks() throws -> [WorkItem] {
        try database.read { try WorkItem.fetchAll($0, sql: "SELECT * FROM work ORDER BY day, start, id") }
    }
    func goals() throws -> [Goal] {
        try database.read { try Goal.fetchAll($0, sql: "SELECT * FROM goal ORDER BY rowid") }
    }
    func entries(taskID: String) throws -> [Entry] {
        try database.read { try Self.entries($0, taskID: taskID) }
    }
    private static func entries(_ db: Database, taskID: String) throws -> [Entry] {
        try Entry.fetchAll(db, sql: "SELECT * FROM entry WHERE taskID = ? ORDER BY rowid", arguments: [taskID])
    }
    private static func task(_ db: Database, _ id: String) throws -> WorkItem {
        guard let task = try WorkItem.fetchOne(db, key: id) else { throw UserError("没有找到这项工作，请重新打开清单。") }
        return task
    }

    @discardableResult func addGoal(title: String) throws -> Goal {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120 else { throw UserError("请填写目标名称，最多120字。") }
        let goal = Goal(id: UUID().uuidString, title: name)
        try database.write { try goal.insert($0) }
        return goal
    }
    func add(_ draft: PlanDraft, now: Date) throws {
        guard now.timeIntervalSince1970.isFinite else { throw UserError("当前时刻无效。") }
        let tasks = try draft.makeTasks()
        try database.write { db in
            for task in tasks { try task.insert(db) }
        }
    }
    func record(taskID: String, percent: Double, note: String, now: Date) throws {
        _ = try CompletionPercent(percent)
        guard note.count <= 1000, now.timeIntervalSince1970.isFinite else { throw UserError("备注最多1000字，记录时刻须有效。") }
        try database.write { db in
            var task = try Self.task(db, taskID)
            guard task.day <= Day.string(now) else { throw UserError("未来的工作不能提前记录成绩。") }
            let entry = Entry(id: UUID().uuidString, taskID: taskID, percent: percent, note: note,
                              recordedAt: now.timeIntervalSince1970, kind: "记录")
            try entry.insert(db)
            task.percent = percent
            try task.update(db)
        }
    }
    func undoLast(taskID: String, now: Date) throws {
        guard now.timeIntervalSince1970.isFinite else { throw UserError("记录时刻无效。") }
        try database.write { db in
            var task = try Self.task(db, taskID)
            let entries = try Self.entries(db, taskID: taskID)
            guard let last = entries.last, last.kind != "撤销" else { throw UserError("当前没有可撤销的手动记录。") }
            let previous = entries.dropLast().last?.percent
            try Entry(id: UUID().uuidString, taskID: taskID, percent: previous, note: "恢复上次记录前的进度",
                      recordedAt: now.timeIntervalSince1970, kind: "撤销").insert(db)
            task.percent = previous
            try task.update(db)
        }
    }
    func editableTasks(taskID: String, series: Bool, now: Date) throws -> [WorkItem] {
        try database.read { try Self.editable($0, taskID: taskID, series: series, now: now) }
    }
    private static func editable(_ db: Database, taskID: String, series: Bool, now: Date) throws -> [WorkItem] {
        let selected = try Self.task(db, taskID)
        guard selected.editable(at: now), try Self.entries(db, taskID: taskID).isEmpty else {
            throw UserError("已开始或已有历史记录的工作不能改安排，原计划会保留。")
        }
        if series, let seriesID = selected.seriesID {
            let candidates = try WorkItem.fetchAll(db, sql: "SELECT * FROM work WHERE seriesID = ? AND day >= ? ORDER BY day, start, id",
                                                   arguments: [seriesID, selected.day])
            return try candidates.filter { task in
                            guard task.editable(at: now) else { return false }
                            return try Self.entries(db, taskID: task.id).isEmpty
                        }
        }
        return [selected]
    }
    func edit(taskID: String, draft: PlanDraft, series: Bool, now: Date, expected: [WorkItem]? = nil) throws {
        var single = draft; single.repeatKind = .once
        let replacement = try single.makeTasks()[0]
        try database.write { db in
            let selected = try Self.task(db, taskID)
            let targets = try Self.editable(db, taskID: taskID, series: series, now: now)
            if let expected, targets != expected {
                throw UserError("对比中的安排已经变化，请返回修改并重新查看对比；未保存任何修改。")
            }
            for old in targets {
                var new = old
                new.title = replacement.title; new.category = replacement.category; new.goalID = replacement.goalID
                new.start = replacement.start; new.minutes = replacement.minutes
                // 重复系列保留日期节奏；仅单次工作可以改日期。
                new.day = selected.seriesID == nil ? replacement.day : old.day
                try new.validate()
                guard new.editable(at: now) else { throw UserError("修改后的开始时间必须在未来；未保存任何修改。") }
                try new.update(db)
            }
        }
    }

    func setGoal(taskID: String, goalID: String?, expected: WorkItem) throws {
        try database.write { db in
            let current = try Self.task(db, taskID)
            guard current == expected else {
                throw UserError("这项工作已经变化，请取消并重新打开后再选择目标；未保存任何修改。")
            }
            if let goalID, try !Goal.exists(db, key: goalID) {
                throw UserError("没有找到这个长期目标，请取消并重新打开目标列表；未保存任何修改。")
            }
            // 归属调整不走安排编辑，不写入进度或历史，也不传播到重复系列。
            try db.execute(sql: "UPDATE work SET goalID = ? WHERE id = ?", arguments: [goalID, taskID])
        }
    }

    func setGoal(action: WorkAction, goalID: String?) throws {
        try database.write { db in
            let first = action.tasks[0]
            let members: [WorkItem]
            if let seriesID = first.seriesID {
                members = try WorkItem.fetchAll(db, sql: "SELECT * FROM work WHERE seriesID = ?", arguments: [seriesID])
            } else {
                members = try WorkItem.fetchAll(db, sql: "SELECT * FROM work WHERE id = ?", arguments: [first.id])
            }
            guard WorkAction.grouped(members) == [action] else {
                throw UserError("这组工作的安排、进度或归属已经变化，请取消并重新选择；未保存任何修改。")
            }
            if let goalID, try !Goal.exists(db, key: goalID) {
                throw UserError("没有找到这个长期目标，请取消并重新打开目标列表；未保存任何修改。")
            }
            // 同一事务先核验完整成员，再只改归属；不覆盖逐日安排与进展历史。
            for task in action.tasks {
                try db.execute(sql: "UPDATE work SET goalID = ? WHERE id = ?", arguments: [goalID, task.id])
            }
        }
    }

    func backup() throws -> Data {
        let backup = try database.read { db in
            Backup(goals: try Goal.fetchAll(db, sql: "SELECT * FROM goal ORDER BY rowid"),
                   tasks: try WorkItem.fetchAll(db, sql: "SELECT * FROM work ORDER BY day, start, id"),
                   entries: try Entry.fetchAll(db, sql: "SELECT * FROM entry ORDER BY rowid"))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }
    private static func decode(_ data: Data) throws -> Backup {
        guard data.count <= 20 * 1024 * 1024 else { throw UserError("备份超过首版20MB读取上限，原数据未改动。") }
        let backup: Backup
        do { backup = try JSONDecoder().decode(Backup.self, from: data) }
        catch { throw UserError("不是有效的时间便签原生备份；网页Demo备份暂不支持，原数据未改动。") }
        guard backup.format == "timenote-native", backup.version == 1,
              backup.tasks.count <= 20000, backup.goals.count <= 2000, backup.entries.count <= 200000 else {
            throw UserError("备份格式版本或容量不受首版支持，原数据未改动。")
        }
        let goalIDs = Set(backup.goals.map(\.id)), taskIDs = Set(backup.tasks.map(\.id))
        guard goalIDs.count == backup.goals.count, taskIDs.count == backup.tasks.count,
              Set(backup.entries.map(\.id)).count == backup.entries.count else { throw UserError("备份中有重复编号。") }
        for goal in backup.goals {
            guard UUID(uuidString: goal.id) != nil, !goal.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  goal.title.count <= 120 else { throw UserError("备份中的目标无效。") }
        }
        for entry in backup.entries {
            guard UUID(uuidString: entry.id) != nil, taskIDs.contains(entry.taskID), entry.recordedAt.isFinite,
                  entry.note.count <= 1000, ["记录", "撤销"].contains(entry.kind), entry.kind != "记录" || entry.percent != nil else {
                throw UserError("备份中的历史记录无效。")
            }
            if let percent = entry.percent { _ = try CompletionPercent(percent) }
        }
        let entries = Dictionary(grouping: backup.entries, by: \.taskID)
        for task in backup.tasks {
            try task.validate()
            guard task.goalID == nil || goalIDs.contains(task.goalID!),
                  task.percent == entries[task.id]?.last?.percent else { throw UserError("备份中的工作与目标或最后进度不一致。") }
        }
        return backup
    }
    private static func importPreview(_ backup: Backup, db: Database) throws -> ImportPreview {
        var goals = 0, tasks = 0, skipped = 0
        let histories = Dictionary(grouping: backup.entries, by: \.taskID)
        for goal in backup.goals {
            if let old = try Goal.fetchOne(db, key: goal.id) {
                guard old == goal else { throw UserError("目标编号冲突，已拒绝合并，未覆盖现有目标。") }
            } else { goals += 1 }
        }
        for task in backup.tasks {
            if let old = try WorkItem.fetchOne(db, key: task.id) {
                guard old == task, try Self.entries(db, taskID: task.id) == (histories[task.id] ?? []) else {
                    throw UserError("工作“\(task.title)”已有不同记录，已拒绝合并，未覆盖任何内容。")
                }
                skipped += 1
            } else { tasks += 1 }
        }
        for entry in backup.entries {
            if let old = try Entry.fetchOne(db, key: entry.id), old != entry { throw UserError("历史编号冲突，未导入。") }
        }
        return ImportPreview(newTasks: tasks, newGoals: goals, skippedTasks: skipped)
    }
    func previewImport(_ data: Data) throws -> ImportPreview {
        let backup = try Self.decode(data)
        return try database.read { try Self.importPreview(backup, db: $0) }
    }
    func importBackup(_ data: Data) throws {
        let backup = try Self.decode(data)
        try database.write { db in
            _ = try Self.importPreview(backup, db: db)
            for goal in backup.goals where try !goal.exists(db) { try goal.insert(db) }
            for task in backup.tasks where try !task.exists(db) { try task.insert(db) }
            for entry in backup.entries where try !entry.exists(db) { try entry.insert(db) }
        }
    }
}
