import Foundation

extension NativeChecks {
    @MainActor static func cockpitChecks(root: URL, now: Date) throws {
        let today = Day.string(now)
        let yesterday = try Day.shifted(today, by: -1)
        func item(_ title: String, day: String, start: Int, minutes: Int, percent: Double? = nil,
                  zone: String = TimeZone.current.identifier) -> WorkItem {
            WorkItem(id: UUID().uuidString, seriesID: nil, title: title, category: "", goalID: nil,
                     day: day, start: start, minutes: minutes, zone: zone, percent: percent)
        }

        try check(item("上午已结束", day: today, start: 300, minutes: 60).phase(at: now) == .finishedUnrecorded, "已结束且未记录判为待补记录")
        try check(item("已记录", day: today, start: 300, minutes: 60, percent: 50).phase(at: now) == .recorded, "已记录且不在进行中判为已记录")
        try check(item("稍后开始", day: today, start: 700, minutes: 30).phase(at: now) == .upcoming, "开始时刻在当前之后判为接下来")
        try check(item("正在做", day: today, start: 540, minutes: 90).phase(at: now) == .ongoing, "时段覆盖当前时刻判为进行中")
        try check(item("边做边记", day: today, start: 540, minutes: 90, percent: 40).phase(at: now) == .ongoing, "进行中的工作即使已有进度仍判为进行中")

        let ongoing = item("正在做", day: today, start: 540, minutes: 90)
        try check(ongoing.remainingMinutes(at: now) == 30, "进行中剩余分钟按计划结束推算")
        try check(ongoing.remainingMinutes(at: try Day.date(today, time: 600).addingTimeInterval(30)) == 30, "剩余分钟向上取整")
        try check(item("上午已结束", day: today, start: 300, minutes: 60).remainingMinutes(at: now) == nil, "不进行中的工作没有剩余分钟")
        try check(item("稍后开始", day: today, start: 700, minutes: 30).minutesUntilStart(at: now) == 100, "未开始工作可推算距开始分钟数")
        try check(ongoing.minutesUntilStart(at: now) == nil, "已开始的工作没有距开始分钟数")

        let spill = item("跨午夜", day: yesterday, start: 1430, minutes: 30)
        let midnight = try Day.date(today, time: 10)
        try check(spill.phase(at: midnight) == .ongoing, "昨日跨午夜工作在次日凌晨仍判为进行中")
        try check(spill.phase(at: now) == .finishedUnrecorded, "昨日跨午夜工作在白天已结束")
        try check(Cockpit.candidates(tasks: [spill], today: today).map(\.title) == ["跨午夜"], "昨日溢出安排进入今天候选")
        let exact = item("恰好午夜", day: yesterday, start: 1380, minutes: 60)
        try check(Cockpit.candidates(tasks: [exact], today: today).isEmpty, "恰好午夜整点结束的昨日工作不算溢出")
        let earlier = item("昨早结束", day: yesterday, start: 480, minutes: 60)
        try check(Cockpit.candidates(tasks: [earlier], today: today).isEmpty, "昨天正常结束的安排不进今天候选")

        let recorded = item("已记录", day: today, start: 300, minutes: 60, percent: 50)
        let later = item("稍后开始", day: today, start: 700, minutes: 30)
        let sections = Cockpit.sections(of: [ongoing, later, spill], now: midnight)
        try check(sections.map(\.phase) == [.ongoing, .upcoming], "分区按固定顺序输出且跳过空区")
        try check(sections[0].items.map(\.title) == ["跨午夜"], "次日凌晨进行中区只含跨午夜安排")
        try check(sections[1].items.count == 2, "接下来区保留当日全部未开始安排")
        let daytime = Cockpit.sections(of: [exact, spill, ongoing, later, recorded], now: now)
        try check(daytime.map(\.phase) == [.ongoing, .upcoming, .finishedUnrecorded, .recorded], "白天四个分区齐全且顺序稳定")
        try check(daytime[2].items.map(\.title) == ["恰好午夜", "跨午夜"], "待补记录区保持输入排序")

        let state = AppState(folder: root.appendingPathComponent("cockpit-state"))
        state.tasks = [exact, spill, ongoing, later, recorded]
        state.selectedDate = now
        state.now = midnight
        try check(state.isViewingToday, "查看今天时判定为驾驶舱视图")
        try check(state.cockpitCandidates.map(\.title) == ["跨午夜", "正在做", "稍后开始", "已记录"], "驾驶舱候选含昨日溢出并排除恰好午夜")
        try check(state.ongoingTasks.map(\.title) == ["跨午夜"], "AppState 进行中区在次日凌晨正确")
        state.now = now
        try check(state.ongoingTasks.map(\.title) == ["正在做"], "AppState 进行中区在白天切换为当天时段")
        state.selectedDate = Day.calendar.date(byAdding: .day, value: 1, to: now)!
        try check(!state.isViewingToday && state.cockpitCandidates.isEmpty, "查看其他日期时不做驾驶舱分区")

        // 正常保存路径会拒绝夏令时缺口时刻；这里直接构造以验证防御路径不崩溃。
        let gap = item("缺口", day: "2026-03-08", start: 150, minutes: 60, zone: "America/New_York")
        let gapNoon = try Day.date("2026-03-08", time: 720, zone: "America/New_York")
        try check(WorkInterval(item: gap)?.start == gapNoon.addingTimeInterval(TimeInterval(150 - 720) * 60), "夏令时缺口时刻降级为当天正午偏移推算")
        let broken = item("坏日期", day: "1999-01-01", start: 600, minutes: 30)
        try check(WorkInterval(item: broken) == nil && broken.phase(at: now) == .finishedUnrecorded, "日期无法解析时按字符串日期降级分类")
    }
}
