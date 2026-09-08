import SwiftUI
import Charts

struct GoalsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("长期目标").font(.system(size: 25, weight: .semibold))
                    Text("目标由你拆分，时间由你安排。").foregroundStyle(.secondary)
                }
                Spacer()
                Button { state.showGoal = true } label: { Label("新增目标", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).disabled(state.repository == nil)
            }
            if state.goals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "flag").font(.system(size: 38, weight: .light)).foregroundStyle(Style.accent)
                    Text("给长期想做的事，留一个位置").font(.title3)
                    Text("先写目标，再把它拆成每日工作。软件不会自动排期。").foregroundStyle(.secondary)
                    Button("写下第一个目标") { state.showGoal = true }.disabled(state.repository == nil)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(state.goals) { goal in
                            let tasks = state.tasks.filter { $0.goalID == goal.id }
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text(goal.title).font(.title3.bold()); Spacer()
                                    Button("安排工作") { state.newWork(goalID: goal.id) }
                                }
                                Text("已安排 \(tasks.count) 项 · 已记录 \(tasks.filter { $0.percent != nil }.count) 项")
                                    .font(.callout).foregroundStyle(.secondary)
                                ForEach(tasks.prefix(12)) { task in
                                    Button {
                                        state.selectedDate = (try? Day.date(task.day, time: 720)) ?? Date(); state.page = .today
                                    } label: {
                                        HStack {
                                            Text(task.day).monospacedDigit()
                                            Text(task.title).lineLimit(1); Spacer()
                                            Text(task.rangeLabel).monospacedDigit()
                                        }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain)
                                }
                                if tasks.count > 12 { Text("其余 \(tasks.count - 12) 项可在每日清单按日期查看。").font(.caption).foregroundStyle(.secondary) }
                                if tasks.isEmpty { Text("还没有拆分工作。点“安排工作”开始。").foregroundStyle(.secondary) }
                            }.padding(20).background(Style.panel, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                Text("已安排工作的进度，不直接当作整个目标的完成率。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(28)
    }
}

struct GoalEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var title = ""
    @State private var problem: String?
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("新增长期目标").font(.title2.bold())
            TextField("例如：完成一本书的初稿", text: $title).textFieldStyle(.roundedBorder).focused($focused)
            Text("先记下目标，然后手动安排每日工作；不会自动生成计划。").foregroundStyle(.secondary)
            if let problem { Text(problem).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                Button("保存目标") {
                    do {
                        _ = try state.requireRepository().addGoal(title: title)
                        state.didSave("目标已保存"); dismiss()
                    } catch { problem = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 440).onAppear { focused = true }
    }
}

struct ReviewView: View {
    @EnvironmentObject var state: AppState
    @State private var month = Date()
    @State private var category = ""
    @AppStorage("weeklyReviewEnabled") private var weekly = true
    @AppStorage("monthlyReviewEnabled") private var monthly = true
    private var monthStart: Date {
        Day.calendar.date(from: Day.calendar.dateComponents([.year, .month], from: month)) ?? month
    }
    private var monthDays: [Date] {
        guard let range = Day.calendar.range(of: .day, in: .month, for: monthStart) else { return [] }
        return range.compactMap { Day.calendar.date(byAdding: .day, value: $0 - 1, to: monthStart) }
    }
    private var filtered: [WorkItem] { state.tasks.filter { category.isEmpty || $0.category == category } }
    private func on(_ day: String) -> [WorkItem] { filtered.filter { $0.day == day } }
    private var historical: [WorkItem] {
        let prefix = String(Day.string(monthStart).prefix(7))
        return filtered.filter { $0.day.hasPrefix(prefix) && $0.day <= Day.string(state.now) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("把积累看见").font(.system(size: 25, weight: .semibold))
                        Text("看计划是否合适，不给你的努力打分。").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("分类", selection: $category) {
                        Text("全部分类").tag("")
                        ForEach(state.categories, id: \.self) { Text($0).tag($0) }
                    }.frame(width: 190)
                }
                HStack {
                    Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                    Text(monthStart.formatted(.dateTime.year().month(.wide))).font(.title3).frame(width: 155)
                    Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                    Button("本月") { month = Date() }
                    Spacer()
                }
                SummaryBar(tasks: historical)
                calendar
                HStack(spacing: 18) {
                    Label("有记录，颜色随完成率变化", systemImage: "square.fill").foregroundStyle(Style.accent)
                    Label("未记录", systemImage: "circle.dashed")
                    Text("— 无计划 · 未来不计成绩")
                }.font(.caption).foregroundStyle(.secondary)
                trend
                if weekly { weeklyReview }
                if monthly { monthlyReview }
                Text("统计按计划分钟加权，未记录单列；跨午夜归开始日。回顾由本机规则计算，不是 AI。").font(.caption).foregroundStyle(.secondary)
            }.padding(28)
        }
    }
    private var calendar: some View {
        let offset = (Day.calendar.component(.weekday, from: monthStart) + 5) % 7
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 60) }
            ForEach(monthDays, id: \.self) { date in
                let day = Day.string(date), tasks = on(day)
                let future = day > Day.string(state.now)
                let percent = future ? nil : (try? Statistics.summary(tasks))?.completionPercent
                Button {
                    state.selectedDate = date; state.page = .today
                } label: {
                    VStack(spacing: 5) {
                        Text("\(Day.calendar.component(.day, from: date))").font(.system(size: 14, weight: .medium))
                        Text(tasks.isEmpty ? "—" : future ? "\(tasks.count)项计划" : percent == nil ? "未记录" : Statistics.percentLabel(percent))
                            .font(.system(size: 10)).lineLimit(1)
                    }.frame(maxWidth: .infinity).frame(height: 60)
                        .background(percent.map { Style.accent.opacity(0.10 + $0 / 100 * 0.25) } ?? Style.panel, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(day == Day.string(state.now) ? Style.accent : .clear, lineWidth: 1.5))
                }.buttonStyle(.plain).help("查看 \(day) 的工作")
            }
        }
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本月完成率趋势").font(.headline)
            let knownDays = monthDays.filter { date in
                Day.string(date) <= Day.string(state.now) && (try? Statistics.summary(on(Day.string(date))))?.completionPercent != nil
            }
            if knownDays.isEmpty {
                Text("有进度记录后，这里会出现趋势。未记录的日子不会画成0%。")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 90)
            } else {
                Chart(knownDays, id: \.self) { date in
                    if let summary = try? Statistics.summary(on(Day.string(date))), let percent = summary.completionPercent {
                        PointMark(x: .value("日期", Day.calendar.component(.day, from: date)), y: .value("完成率", percent)).foregroundStyle(Style.accent)
                    }
                }.chartYScale(domain: 0...100).chartXScale(domain: 1...monthDays.count)
                    .chartXAxis {
                        AxisMarks(values: [1, 7, 14, 21, 28]) { value in
                            AxisGridLine(); AxisTick()
                            AxisValueLabel { if let day = value.as(Int.self) { Text("\(day)日") } }
                        }
                    }.frame(height: 155)
                Text("每个点是一日的已知完成率；缺失日期留空，不跨缺口假画连续成绩。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var weeklyReview: some View {
        let start = Day.calendar.dateInterval(of: .weekOfYear, for: state.now)?.start ?? state.now
        let previous = Day.calendar.date(byAdding: .day, value: -7, to: start) ?? start
        let tasks = filtered.filter { $0.day >= Day.string(previous) && $0.day < Day.string(start) }
        let groups = Dictionary(grouping: tasks) { $0.category.isEmpty ? "未分类" : $0.category }
        return VStack(alignment: .leading, spacing: 12) {
            Text("上周 · 按分类回顾").font(.headline)
            Text("\(Day.string(previous)) 至 \((try? Day.shifted(Day.string(start), by: -1)) ?? "")")
                .font(.caption).foregroundStyle(.secondary)
            if groups.isEmpty { Text("上周没有符合当前分类的计划。无计划不作0%评价。").foregroundStyle(.secondary) }
            ForEach(groups.keys.sorted(), id: \.self) { name in
                let summary = try? Statistics.summary(groups[name] ?? [])
                HStack {
                    Text(name); Spacer()
                    Text(Statistics.percentLabel(summary?.completionPercent)).monospacedDigit()
                    Text("\(summary?.missingCount ?? 0) 项未记录").foregroundStyle(.secondary)
                }
            }
            if tasks.contains(where: { $0.percent == nil }) {
                Text("先回看漏记的工作，再判断是否需要调整计划；漏记不代表未完成。").font(.callout).foregroundStyle(.secondary)
            }
        }.padding(18).background(Style.panel, in: RoundedRectangle(cornerRadius: 10))
    }
    private var monthlyReview: some View {
        let current = Day.calendar.date(from: Day.calendar.dateComponents([.year, .month], from: state.now)) ?? state.now
        let previous = Day.calendar.date(byAdding: .month, value: -1, to: current) ?? current
        let tasks = filtered.filter { $0.day >= Day.string(previous) && $0.day < Day.string(current) }
        let summary = try? Statistics.summary(tasks)
        return VStack(alignment: .leading, spacing: 10) {
            Text("上月 · 整体回顾").font(.headline)
            Text("\(previous.formatted(.dateTime.year().month(.wide))) · \(tasks.count) 项安排")
            if tasks.isEmpty { Text("上月没有计划，暂不作评价。").foregroundStyle(.secondary) }
            else {
                Text("已知完成率 \(Statistics.percentLabel(summary?.completionPercent)) · \(summary?.missingCount ?? 0) 项未记录")
                Text("汇总整月每项工作的计划时长，不把每天百分比简单平均。若想调整工作量，请在每日清单修改选中的未来安排，先看对比再确认。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.padding(18).background(Style.panel, in: RoundedRectangle(cornerRadius: 10))
    }
    private func shiftMonth(_ by: Int) {
        if let date = Day.calendar.date(byAdding: .month, value: by, to: monthStart) { month = date }
    }
}
