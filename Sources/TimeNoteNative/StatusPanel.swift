import SwiftUI

/// 菜单栏状态面板：当前进行中的工作、倒计时、快速记录，以及接下来与待补记录的摘要。
/// 倒计时展示的是计划时长，不是实际计时；"进行中"判定跟随 state.now（约 30 秒刷新一次）。
struct StatusPanelView: View {
    @EnvironmentObject var state: AppState
    @State private var clock = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(state.isViewingToday ? "今天" : state.day).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if state.repository == nil {
                    Label("数据不可用", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary)
                }
            }
            ongoingSection
            Divider()
            upcomingSection
            pendingSection
            Spacer(minLength: 0)
            Divider()
            HStack {
                Button { (NSApp.delegate as? AppDelegate)?.showWindow() } label: { Label("打开主窗口", systemImage: "macwindow") }
                Spacer()
                Button { (NSApp.delegate as? AppDelegate)?.newWork() } label: { Label("新增工作", systemImage: "plus") }
            }.controlSize(.small)
        }
        .padding(14)
        .frame(width: 350)
        .accessibilityIdentifier("status-panel")
        .tint(Style.accent)
        .onReceive(tick) { date in clock = date }
    }

    @ViewBuilder private var ongoingSection: some View {
        let ongoing = state.ongoingTasks
        if ongoing.isEmpty {
            Label("当前没有进行中的工作", systemImage: "pause.circle")
                .font(.callout).foregroundStyle(.secondary).padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ongoing) { task in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                        HStack(spacing: 10) {
                            Text(task.rangeLabel).monospacedDigit()
                            Text(task.remainingMinutes(at: clock).map { $0 > 0 ? "剩余 \($0) 分钟" : "即将结束" } ?? "")
                                .foregroundStyle(Style.accent).monospacedDigit()
                            Spacer()
                            Text("已记录 " + Statistics.percentLabel(task.percent)).foregroundStyle(.secondary)
                        }.font(.caption)
                        HStack(spacing: 8) {
                            ForEach([0.0, 25.0, 50.0, 75.0], id: \.self) { value in
                                Button("\(Int(value))%") { record(task, value) }
                            }
                            Button { record(task, 100) } label: { Label("完成", systemImage: "checkmark.circle.fill") }
                                .buttonStyle(.borderedProminent)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(state.repository == nil)
                        .accessibilityIdentifier("panel-quick-record")
                    }
                }
            }
        }
    }

    @ViewBuilder private var upcomingSection: some View {
        let upcoming = cockpitItems(.upcoming)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(WorkPhase.upcoming.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(upcoming.prefix(3)) { task in
                    HStack(spacing: 8) {
                        Image(systemName: "circle").font(.caption).foregroundStyle(.tertiary)
                        Text(task.title).font(.callout).lineLimit(1)
                        Spacer()
                        Text(startLabel(task)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                if upcoming.count > 3 {
                    Text("还有 \(upcoming.count - 3) 项今天稍后").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder private var pendingSection: some View {
        let pending = cockpitItems(.finishedUnrecorded)
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(WorkPhase.finishedUnrecorded.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(pending.prefix(3)) { task in
                    Button {
                        (NSApp.delegate as? AppDelegate)?.showWindow()
                        state.recordTask = task
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.dotted").font(.caption).foregroundStyle(.orange)
                            Text(task.title).font(.callout).lineLimit(1).foregroundStyle(.primary)
                            Spacer()
                            Text(task.rangeLabel).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }.buttonStyle(.plain)
                }
                if pending.count > 3 {
                    Text("还有 \(pending.count - 3) 项待补记录").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func cockpitItems(_ phase: WorkPhase) -> [WorkItem] {
        state.cockpitSections.first { $0.phase == phase }?.items ?? []
    }

    private func startLabel(_ task: WorkItem) -> String {
        let clockText = "今天 " + Day.clock(task.start)
        guard let minutes = task.minutesUntilStart(at: clock) else { return clockText }
        return minutes > 0 ? clockText + " · 还有 \(minutes) 分钟" : clockText
    }

    private func record(_ task: WorkItem, _ percent: Double) {
        _ = state.perform("已记录 \(Int(percent))%，保留历史") {
            try state.requireRepository().record(taskID: task.id, percent: percent, note: "", now: Date())
        }
    }
}
