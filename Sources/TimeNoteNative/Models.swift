import Foundation
import GRDB

struct UserError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct TimeRange: Equatable, Sendable {
    let start: Int
    let end: Int
    let nextDay: Bool
    var minutes: Int { end - start + (nextDay ? 1440 : 0) }
    init(start: Int, end: Int, nextDay: Bool) throws {
        guard (0..<1440).contains(start), (0..<1440).contains(end),
              (1...1440).contains(end - start + (nextDay ? 1440 : 0)) else {
            throw UserError("结束必须晚于开始，时段不能超过24小时；跨午夜请勾选次日。")
        }
        self.start = start; self.end = end; self.nextDay = nextDay
    }
    var label: String { Day.clock(start) + " – " + (nextDay ? "次日 " : "") + Day.clock(end) }
}

struct TimeInput {
    private(set) var startText: String
    private(set) var endText: String
    var nextDay: Bool
    private var preservedMinutes: Int?
    init(start: Int, end: Int, nextDay: Bool) {
        startText = Day.clock(start); endText = Day.clock(end); self.nextDay = nextDay
        preservedMinutes = (try? TimeRange(start: start, end: end, nextDay: nextDay))?.minutes
    }
    var range: TimeRange? {
        guard let start = try? Day.parseClock(startText), let end = try? Day.parseClock(endText) else { return nil }
        return try? TimeRange(start: start, end: end, nextDay: nextDay)
    }
    mutating func setStart(_ text: String) {
        if let range { preservedMinutes = range.minutes }
        startText = text
        guard let start = try? Day.parseClock(text), !endText.isEmpty, let minutes = preservedMinutes else { return }
        endText = Day.clock((start + minutes) % 1440)
        nextDay = start + minutes >= 1440
    }
    mutating func setEnd(_ text: String) {
        endText = text
        preservedMinutes = range?.minutes
    }
}

enum Day {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }
    static func string(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func date(_ value: String, time: Int = 0, zone: String = TimeZone.current.identifier) throws -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (2000...2100).contains(parts[0]), (0..<1440).contains(time),
              let tz = TimeZone(identifier: zone) else { throw UserError("日期或时间无效，首版支持2000至2100年。") }
        var cal = calendar; cal.timeZone = tz
        let c = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: time / 60, minute: time % 60)
        guard let date = cal.date(from: c) else { throw UserError("日期无效。") }
        let actual = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard actual.year == c.year, actual.month == c.month, actual.day == c.day,
              actual.hour == c.hour, actual.minute == c.minute,
              value == String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2]) else {
            throw UserError("日期无效，或该时刻受夏令时影响而不存在。请换一个时间。")
        }
        return date
    }
    static func shifted(_ day: String, by days: Int) throws -> String {
        let date = try date(day, time: 720)
        guard let next = calendar.date(byAdding: .day, value: days, to: date) else { throw UserError("无法计算日期。") }
        return string(next)
    }
    static func clock(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60, minutes % 60) }
    static func parseClock(_ value: String) throws -> Int {
        let p = value.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0...23).contains(h), (0...59).contains(m) else {
            throw UserError("请填写24小时制时间，例如09:30。")
        }
        return h * 60 + m
    }
}

enum RepeatKind: String, CaseIterable, Identifiable {
    case once = "只做一次", daily = "每天", weekdays = "工作日", custom = "自选周几"
    var id: String { rawValue }
}

struct PlanDraft {
    var title: String
    var category: String
    var day: String
    var start: Int
    var end: Int
    var nextDay = false
    var goalID: String?
    var repeatKind: RepeatKind = .once
    var until: String
    var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    var zone: String = TimeZone.current.identifier

    init(title: String = "", category: String = "", day: String = Day.string(Date()), start: Int = 540,
         end: Int = 600, goalID: String? = nil) {
        self.title = title; self.category = category; self.day = day
        self.start = start; self.end = end; self.goalID = goalID
        self.until = (try? Day.shifted(day, by: 29)) ?? day
    }
    init(task: WorkItem) {
        title = task.title; category = task.category; day = task.day; start = task.start
        end = (task.start + task.minutes) % 1440; nextDay = task.start + task.minutes >= 1440
        goalID = task.goalID; until = task.day; zone = task.zone
    }
    func makeTasks() throws -> [WorkItem] {
        let range = try TimeRange(start: start, end: end, nextDay: nextDay)
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 120, category.count <= 80 else {
            throw UserError("请填写工作名称（最多120字），分类最多80字。")
        }
        let first = try Day.date(day, time: 720)
        let last = try Day.date(repeatKind == .once ? day : until, time: 720)
        let distance = Day.calendar.dateComponents([.day], from: first, to: last).day ?? -1
        guard (0...365).contains(distance) else { throw UserError("结束日期不能早于开始日期；一次最多安排366天。") }
        if repeatKind == .custom && (weekdays.isEmpty || !weekdays.isSubset(of: Set(1...7))) {
            throw UserError("请至少选择一个有效的星期。")
        }
        let series = repeatKind == .once ? nil : UUID().uuidString
        var result: [WorkItem] = []
        for offset in 0...distance {
            let date = Day.calendar.date(byAdding: .day, value: offset, to: first)!
            let weekday = Day.calendar.component(.weekday, from: date)
            if repeatKind == .weekdays && !(2...6).contains(weekday) { continue }
            if repeatKind == .custom && !weekdays.contains(weekday) { continue }
            let task = WorkItem(id: UUID().uuidString, seriesID: series, title: cleaned,
                                category: category.trimmingCharacters(in: .whitespacesAndNewlines), goalID: goalID,
                                day: Day.string(date), start: start, minutes: range.minutes, zone: zone, percent: nil)
            try task.validate()
            result.append(task)
        }
        guard !result.isEmpty else { throw UserError("这个日期范围没有符合所选星期的工作日。") }
        return result
    }
}

struct WorkItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "work"
    var id: String
    var seriesID: String?
    var title: String
    var category: String
    var goalID: String?
    var day: String
    var start: Int
    var minutes: Int
    var zone: String
    var percent: Double?
    var rangeLabel: String {
        Day.clock(start) + " – " + (start + minutes >= 1440 ? "次日 " : "") + Day.clock((start + minutes) % 1440)
    }
    func validate() throws {
        guard UUID(uuidString: id) != nil, seriesID == nil || UUID(uuidString: seriesID!) != nil,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 120,
              category.count <= 80, (0..<1440).contains(start), (1...1440).contains(minutes) else {
            throw UserError("工作内容或编号无效，未保存。")
        }
        _ = try Day.date(day, time: start, zone: zone)
        if let percent { _ = try CompletionPercent(percent) }
    }
    func editable(at now: Date) -> Bool {
        guard percent == nil, let scheduled = try? Day.date(day, time: start, zone: zone) else { return false }
        return scheduled > now
    }
}

struct Goal: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "goal"
    var id: String
    var title: String
}

struct Entry: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "entry"
    var id: String
    var taskID: String
    var percent: Double?
    var note: String
    var recordedAt: Double
    var kind: String
}

struct Backup: Codable, Sendable {
    var format = "timenote-native"
    var version = 1
    var goals: [Goal]
    var tasks: [WorkItem]
    var entries: [Entry]
}
struct ImportPreview {
    let newTasks: Int
    let newGoals: Int
    let skippedTasks: Int
}

enum Statistics {
    static func summary(_ tasks: [WorkItem]) throws -> ProgressSummary {
        try ProgressSummary.summarize(tasks.map {
            try ProgressSample(minutes: PlannedMinutes(Double($0.minutes)), completion: $0.percent.map { try CompletionPercent($0) })
        })
    }
    static func percentLabel(_ percent: Double?) -> String {
        guard let percent else { return "未记录" }
        return percent.formatted(.number.precision(.fractionLength(0...2))) + "%"
    }
}
