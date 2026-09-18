import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class AppState: ObservableObject {
    enum Page: String, CaseIterable, Identifiable {
        case today = "每日清单", goals = "长期目标", review = "积累与回顾", settings = "设置与备份"
        var id: String { rawValue }
        var symbol: String {
            switch self { case .today: "checklist"; case .goals: "flag"; case .review: "calendar"; case .settings: "slider.horizontal.3" }
        }
    }
    @Published var page: Page = .today
    @Published var selectedDate = Date()
    @Published var tasks: [WorkItem] = []
    @Published var goals: [Goal] = []
    @Published var error: String?
    @Published var status = "只保存在这台 Mac"
    @Published var editor: EditorContext?
    @Published var recordTask: WorkItem?
    @Published var historyTask: WorkItem?
    @Published var goalTask: WorkItem?
    @Published var existingWorkGoal: Goal?
    @Published var showGoal = false
    @Published var importData: Data?
    @Published var importPreview: ImportPreview?
    @Published var now = Date()
    let repository: Repository?
    let dataFolder: URL

    init(folder: URL) {
        dataFolder = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let loaded = try Repository(path: folder.appendingPathComponent("timenote.sqlite").path)
            let initialTasks = try loaded.tasks(), initialGoals = try loaded.goals()
            repository = loaded
            tasks = initialTasks; goals = initialGoals
        } catch {
            repository = nil
            self.error = "本地数据暂时无法打开。没有清空或替换文件。\n" + error.localizedDescription
            status = "保存不可用，请先处理错误"
        }
    }
    func requireRepository() throws -> Repository {
        guard let repository else { throw UserError("数据未能打开，不能保存。请在设置中查看数据位置，并保留原文件。") }
        return repository
    }
    func reload() throws {
        let repository = try requireRepository()
        let newTasks = try repository.tasks(), newGoals = try repository.goals()
        tasks = newTasks; goals = newGoals; now = Date()
    }
    func didSave(_ message: String) {
        status = message
        do { try reload() }
        catch {
            status = message + "；列表刷新失败，请重新打开软件，勿重复提交"
            self.error = status + "\n" + error.localizedDescription
        }
    }
    @discardableResult func perform(_ message: String, _ action: () throws -> Void) -> Bool {
        do { try action() }
        catch { self.error = error.localizedDescription; return false }
        didSave(message)
        return true
    }
    var day: String { Day.string(selectedDate) }
    var dayTasks: [WorkItem] { tasks.filter { $0.day == day } }
    var isViewingToday: Bool { day == Day.string(now) }
    /// 驾驶舱候选：查看今天时含昨日跨午夜溢出安排；查看其他日期时与 dayTasks 相同。
    var cockpitCandidates: [WorkItem] {
        isViewingToday ? Cockpit.candidates(tasks: tasks, today: day) : dayTasks
    }
    var cockpitSections: [(phase: WorkPhase, items: [WorkItem])] {
        Cockpit.sections(of: cockpitCandidates, now: now)
    }
    var ongoingTasks: [WorkItem] {
        cockpitSections.first { $0.phase == .ongoing }?.items ?? []
    }
    var categories: [String] { Array(Set(tasks.map(\.category).filter { !$0.isEmpty })).sorted() }
    func newWork(goalID: String? = nil) {
        guard repository != nil else { error = "数据未能打开，暂时不能新增。"; return }
        let components = Day.calendar.dateComponents([.hour, .minute], from: Date())
        let start = min(1380, ((components.hour! * 60 + components.minute!) / 30 + 1) * 30)
        editor = EditorContext(task: nil, draft: PlanDraft(day: day, start: start, end: start + 30, goalID: goalID))
    }
    func editWork(_ task: WorkItem) {
        editor = EditorContext(task: task, draft: PlanDraft(task: task))
    }
    func stepDay(_ value: Int) {
        if let date = Day.calendar.date(byAdding: .day, value: value, to: selectedDate) { selectedDate = date }
    }
    func exportBackup() {
        do {
            let data = try requireRepository().backup()
            let panel = NSSavePanel()
            panel.title = "导出时间便签备份"
            panel.nameFieldStringValue = "时间便签备份-\(Day.string(Date())).json"
            panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            status = "备份已导出：\(url.lastPathComponent)"
        } catch { self.error = error.localizedDescription }
    }
    func chooseBackup() {
        let panel = NSOpenPanel()
        panel.title = "选择时间便签原生备份"
        panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 20 * 1024 * 1024 else { throw UserError("文件超过首版20MB上限，未读取或修改数据。") }
            let data = try Data(contentsOf: url)
            importPreview = try requireRepository().previewImport(data)
            importData = data
        } catch { self.error = error.localizedDescription }
    }
    func confirmImport() {
        guard let data = importData else { return }
        if perform("备份已合并，原有内容保留", { try requireRepository().importBackup(data) }) {
            importData = nil; importPreview = nil
        }
    }
}

struct EditorContext: Identifiable {
    let id = UUID()
    let task: WorkItem?
    let draft: PlanDraft
}

enum Style {
    static let accent = Color(red: 0.27, green: 0.50, blue: 0.42)
    static let soft = accent.opacity(0.10)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
}

struct SummaryBar: View {
    let tasks: [WorkItem]
    var body: some View {
        let summary = try? Statistics.summary(tasks)
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("已记录部分的完成率").font(.caption).foregroundStyle(.secondary)
                Text(tasks.isEmpty ? "无计划" : Statistics.percentLabel(summary?.completionPercent))
                    .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
            }
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: summary?.completionPercent ?? 0, total: 100).tint(Style.accent)
                    Text("\(summary?.recordedCount ?? 0) 项已记录 · \(summary?.missingCount ?? 0) 项未记录")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: 260)
                Spacer()
                Text("计划 \(tasks.reduce(0) { $0 + $1.minutes }) 分钟\n不是实际计时")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            } else { Spacer() }
        }.padding(20).background(Style.soft, in: RoundedRectangle(cornerRadius: 12))
    }
}
