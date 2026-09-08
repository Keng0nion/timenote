#if LOCAL_UI_TEST
import AppKit

@MainActor extension AppDelegate {
    func exerciseUI(_ step: Int = 0) {
        do {
            guard let state, let window else { throw UserError("测试窗口已关闭") }
            let repo = try state.requireRepository()
            func require(_ condition: Bool, _ label: String) throws {
                guard condition else { throw UserError("界面操作：" + label) }
                print("界面通过：" + label)
            }
            switch step {
            case 0:
                try key("\r", code: 36)
            case 1:
                try require(state.editor != nil && repo.tasks().count == 8, "空名称不保存，表单保留")
                try type("控件验收 · 实际新增")
                try key("\r", code: 36)
            case 2:
                try require(state.editor == nil && repo.tasks().count == 9, "原生输入和回车保存新增工作")
                newWork()
            case 3:
                try type("控件验收 · 取消不保存")
                try key("\u{1b}", code: 53)
            case 4:
                try require(state.editor == nil && repo.tasks().count == 9, "Escape取消不写入")
                guard let task = try repo.tasks().first(where: { $0.title == "控件验收 · 实际新增" }) else { throw UserError("新增项未找到") }
                state.recordTask = task
            case 5:
                try type("50")
                try key("\r", code: 36)
            case 6:
                let task = try repo.tasks().first { $0.title == "控件验收 · 实际新增" }!
                try require(state.recordTask == nil && task.percent == 50 && repo.entries(taskID: task.id).count == 1, "原生输入保存进展及历史")
                state.selectedDate = try Day.date(Day.shifted(Day.string(Date()), by: 1), time: 720)
                newWork()
            case 7:
                try type("控件验收 · 未来安排")
                try key("\r", code: 36)
            case 8:
                guard let task = try repo.tasks().first(where: { $0.title == "控件验收 · 未来安排" }) else { throw UserError("未来项保存失败") }
                state.editWork(task)
            case 9:
                try type("控件验收 · 修改后")
                try key("\r", code: 36)
            case 10:
                try require(state.editor != nil && repo.tasks().contains { $0.title == "控件验收 · 未来安排" }, "修改对比出现前不写入")
                if let sheet = window.attachedSheet, let view = sheet.contentView {
                    try saveView(view, to: state.dataFolder.appendingPathComponent("native-comparison.png"))
                }
                try key("\r", code: 36)
            case 11:
                try require(state.editor == nil && repo.tasks().contains { $0.title == "控件验收 · 修改后" }, "再次确认才修改未来安排")
                state.page = .review
            case 12:
                try scrollToBottomAndCapture("native-review-bottom.png")
                state.page = .settings
            case 13:
                try scrollToBottomAndCapture("native-settings-bottom.png")
                state.page = .today; state.selectedDate = Date()
                state.goalTask = try repo.tasks().first { $0.title == "控件验收 · 实际新增" }!
            case 14:
                try key("\r", code: 36)
                try require(state.goalTask != nil, "未选择目标不能直接保存")
                try clickChoice()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    do { try self?.key("\u{1b}", code: 53) } catch { print("取消按键失败：\(error)"); exit(1) }
                }
            case 15:
                let task = try repo.tasks().first { $0.title == "控件验收 · 实际新增" }!
                try require(state.goalTask == nil && task.goalID == nil, "选目标后Escape取消不保存")
                state.goalTask = task
            case 16:
                try clickChoice()
            case 17:
                try captureSheet("native-goal-assignment.png")
                try key("\r", code: 36)
            case 18:
                let task = try repo.tasks().first { $0.title == "控件验收 · 实际新增" }!
                try require(state.goalTask == nil && task.goalID == state.goals[0].id && task.percent == 50 && repo.tasks().count == 10 && repo.entries(taskID: task.id).count == 1,
                            "每日任务选目标保存，同一任务和原进度历史保留")
                state.page = .goals
            case 19:
                if let view = window.contentView { try saveView(view, to: state.dataFolder.appendingPathComponent("native-goal-linked.png")) }
                try pressButton("加入已有工作")
            case 20:
                try type("不会匹配的筛选词")
            case 21:
                try key("\r", code: 36)
                try require(state.existingWorkGoal != nil && repo.tasks().filter { $0.goalID == nil }.count == 2, "无匹配项不能保存")
                try type("试用检查 · 写作")
            case 22:
                try clickChoice()
            case 23:
                try captureSheet("native-existing-work.png")
                try key("\r", code: 36)
            case 24:
                let task = try repo.tasks().first { $0.title == "试用检查 · 写作" }!
                try require(state.existingWorkGoal == nil && task.goalID == state.goals[0].id && task.percent == 50 && repo.tasks().count == 10, "目标页筛选并加入已有工作，不重复新增")
                state.goalTask = task
            case 25:
                try clickChoice(offset: 90)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    do { try self?.key("\r", code: 36) } catch { print("保存按键失败：\(error)"); exit(1) }
                }
            case 26:
                let task = try repo.tasks().first { $0.title == "试用检查 · 写作" }!
                try require(state.goalTask == nil && task.goalID == nil && task.percent == 50, "移出目标仍保留每日工作与进度")
                let other = try repo.addGoal(title: "控件验收 · 另一个目标")
                try state.reload(); state.existingWorkGoal = other
            case 27:
                try type("控件验收 · 实际新增")
            case 28:
                try clickChoice()
            case 29:
                try captureSheet("native-goal-move.png")
                try key("\r", code: 36)
            case 30:
                let task = try repo.tasks().first { $0.title == "控件验收 · 实际新增" }!
                try require(state.existingWorkGoal == nil && task.goalID == state.goals[1].id && task.percent == 50 && repo.tasks().count == 10, "已属其他目标的工作确认后只更换归属")
                var practice = PlanDraft(title: "行动检查 · 每日练习", day: Day.string(Date()), start: 480, end: 540)
                practice.repeatKind = .daily; practice.until = try Day.shifted(practice.day, by: 29)
                try repo.add(practice, now: Date())
                var reading = practice; reading.title = "行动检查 · 每日阅读"; reading.start = 600; reading.end = 630
                try repo.add(reading, now: Date())
                let first = try repo.tasks().first { $0.title == practice.title }!
                try repo.record(taskID: first.id, percent: 100, note: "今日完成", now: Date())
                try state.reload(); state.existingWorkGoal = state.goals[0]
            case 31:
                try type("行动检查")
            case 32:
                try require(ExistingWorkSheet(goal: state.goals[0]).groupedCandidates(state.tasks).filter { $0.matches("行动检查") }.count == 2,
                            "选择窗口60次每日安排归为两项行动")
                let chooser = ExistingWorkSheet(goal: state.goals[0])
                let sample = WorkAction.grouped(state.tasks).first { $0.title == "行动检查 · 每日练习" }!
                var partial = sample.tasks
                partial[0].goalID = state.goals[0].id
                try require(chooser.groupedCandidates(partial).first?.tasks.count == 30, "部分日期已有归属仍保留完整组供选择")
                let allLinked = partial.map { task -> WorkItem in var value = task; value.goalID = state.goals[0].id; return value }
                try require(chooser.groupedCandidates(allLinked).isEmpty, "整组全部已在目标时不重复列出")
                var separate = PlanDraft(title: sample.title, day: sample.tasks[0].day, start: 480, end: 540)
                separate.repeatKind = .daily; separate.until = sample.tasks.last!.day
                try require(chooser.groupedCandidates(partial + separate.makeTasks()).count == 2, "同名独立重复安排在选择器仍分两组")
                try captureSheet("native-action-choices.png")
                try clickChoice()
            case 33:
                try captureSheet("native-action-preview.png")
                try key("\u{1b}", code: 53)
            case 34:
                try require(state.existingWorkGoal == nil && repo.tasks().filter { $0.title.hasPrefix("行动检查") }.allSatisfy { $0.goalID == nil }, "整组选择取消不保存任何一天")
                state.existingWorkGoal = state.goals[0]
            case 35:
                try type("行动检查 · 每日练习")
            case 36:
                try clickChoice()
            case 37:
                try key("\r", code: 36)
            case 38:
                let tasks = try repo.tasks().filter { $0.title == "行动检查 · 每日练习" }
                try require(state.existingWorkGoal == nil && tasks.count == 30 && tasks.allSatisfy { $0.goalID == state.goals[0].id } && tasks.first?.percent == 100,
                            "已有工作窗口整组30天加入目标，今日进度保留")
                state.page = .goals
            case 39:
                if let view = window.contentView { try saveView(view, to: state.dataFolder.appendingPathComponent("native-action-goal.png")) }
                let task = try repo.tasks().first { $0.title == "行动检查 · 每日练习" }!
                state.goalTask = task
            case 40:
                try clickChoice(offset: 90)
            case 41:
                try captureSheet("native-action-move.png")
                try key("\r", code: 36)
            case 42:
                let tasks = try repo.tasks().filter { $0.title == "行动检查 · 每日练习" }
                try require(state.goalTask == nil && tasks.allSatisfy { $0.goalID == state.goals[1].id } && repo.tasks().count == 70,
                            "每日入口更换整组目标，不留其余日期在旧目标")
                let action = WorkAction.grouped(tasks)[0]
                try require(action.progress(through: Day.string(Date())).completedDays == 1 && action.progress(through: Day.string(Date())).scheduledDays == 1,
                            "目标行动显示今日完成一天，不把未来29天算漏记")
                let reading = try repo.tasks().filter { $0.title == "行动检查 · 每日阅读" }
                for index in 0..<5 {
                    let goal = try repo.addGoal(title: "长名称目标\(index + 1) · 持续阅读并整理每一章的核心内容与自己的理解，按周回顾并写下下一阶段准备改进的具体做法")
                    try repo.setGoal(taskID: reading[index].id, goalID: goal.id, expected: reading[index])
                }
                try state.reload(); state.existingWorkGoal = state.goals[0]
            case 43:
                try type("行动检查 · 每日阅读")
            case 44:
                try clickChoice()
            case 45:
                try scrollOwnershipAndCapture()
                let reading = try repo.tasks().first { $0.title == "行动检查 · 每日阅读" }!
                try repo.record(taskID: reading.id, percent: 50, note: "预览期间的新进度", now: Date())
                try state.reload()
                try repo.backup().write(to: state.dataFolder.appendingPathComponent("stale-preview-backup.json"), options: .atomic)
            case 46:
                try key("\r", code: 36)
            case 47:
                let saved = try Data(contentsOf: state.dataFolder.appendingPathComponent("stale-preview-backup.json"))
                try require(state.existingWorkGoal != nil && repo.backup() == saved, "预览后刷新仍保留旧快照，拒绝整组覆盖新进度并保留表单")
                try captureSheet("native-action-stale.png")
                try key("\u{1b}", code: 53)
            case 48:
                try require(state.existingWorkGoal == nil, "整组过时错误后仍可取消")
                let backup = try repo.backup()
                let reopened = try Repository(path: repo.path)
                try require(try backup == reopened.backup(), "界面操作后重开数据库无损")
                try backup.write(to: state.dataFolder.appendingPathComponent("ui-backup.json"), options: .atomic)
                print("原生控件流程全部通过；仅向本程序派发键盘和鼠标事件，未申请系统辅助功能权限，未测试全局快捷键。")
                NSApplication.shared.terminate(nil)
                return
            default: throw UserError("界面检查步骤无效")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.exerciseUI(step + 1) }
        } catch {
            if let state, let view = window?.attachedSheet?.contentView {
                try? saveView(view, to: state.dataFolder.appendingPathComponent("native-failure.png"))
                print("当前任务：\(state.tasks.map(\.title))；焦点：\(String(describing: window?.attachedSheet?.firstResponder))")
            }
            print("原生控件流程失败：\(error)"); exit(1)
        }
    }
    private func clickChoice(offset: CGFloat = 24) throws {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        guard let view = window?.attachedSheet?.contentView, let scroll = find(view) else { throw UserError("未找到选择列表") }
        let clip = scroll.contentView
        let point = NSPoint(x: clip.bounds.minX + 90, y: clip.isFlipped ? clip.bounds.minY + offset : clip.bounds.maxY - offset)
        try click(at: clip.convert(point, to: nil))
    }
    private func pressButton(_ title: String) throws {
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        func buttons(_ view: NSView) -> [NSButton] {
            if let button = view as? NSButton { return [button] }
            return view.subviews.flatMap { buttons($0) }
        }
        guard title == "加入已有工作", let view = window?.contentView, let scroll = findScroll(view),
              let button = buttons(scroll).min(by: { $0.convert(.zero, to: nil).x < $1.convert(.zero, to: nil).x }) else {
            throw UserError("未找到目标卡片的已有工作入口")
        }
        try click(at: button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil))
    }
    private func click(at point: NSPoint) throws {
        guard let target = window?.attachedSheet ?? window else { throw UserError("点击窗口不存在") }
        target.makeKeyAndOrderFront(nil)
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: eventType, location: point, modifierFlags: [],
                                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: target.windowNumber,
                                                context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { throw UserError("无法构造本窗口点击") }
            NSApplication.shared.postEvent(event, atStart: false)
        }
    }
    private func captureSheet(_ name: String) throws {
        guard let view = window?.attachedSheet?.contentView, let state else { throw UserError("目标表单没有打开") }
        let url = state.dataFolder.appendingPathComponent(name)
        try saveView(view, to: url)
        guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url)),
              let corner = bitmap.colorAt(x: 8, y: 8), corner.alphaComponent > 0.99 else {
            throw UserError("目标表单背景应完整绘制，截图存在透明区域：" + name)
        }
    }
    private func scrollOwnershipAndCapture() throws {
        func scrolls(_ view: NSView) -> [NSScrollView] {
            if let scroll = view as? NSScrollView { return [scroll] }
            return view.subviews.flatMap { scrolls($0) }
        }
        guard let view = window?.attachedSheet?.contentView else { throw UserError("多归属预览未打开") }
        let all = scrolls(view)
        guard all.count == 2, let summary = all.last, let document = summary.documentView,
              document.bounds.height > summary.contentView.bounds.height else { throw UserError("长名称多目标预览必须能滚动查看全部归属") }
        let y = document.isFlipped ? document.bounds.maxY - summary.contentView.bounds.height : document.bounds.minY
        summary.contentView.scroll(to: NSPoint(x: 0, y: y)); summary.reflectScrolledClipView(summary.contentView)
        try captureSheet("native-action-ownership.png")
        print("界面通过：长名称与六种原归属可滚动查看，保存范围不隐藏")
    }
    private func type(_ text: String) throws {
        guard let sheet = window?.attachedSheet, let field = sheet.firstResponder as? NSTextView else {
            throw UserError("当前焦点不是原生文本编辑器：\(String(describing: window?.attachedSheet?.firstResponder))")
        }
        field.setSelectedRange(NSRange(location: 0, length: (field.string as NSString).length))
        field.insertText(text, replacementRange: field.selectedRange())
    }
    private func key(_ characters: String, code: UInt16) throws {
        guard let target = window?.attachedSheet ?? window,
              let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: target.windowNumber, context: nil, characters: characters,
                                          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else {
            throw UserError("无法构造本窗口按键")
        }
        let handled = target.performKeyEquivalent(with: event)
        print("测试按键 \(code)，窗口响应：\(handled)")
        if !handled { target.sendEvent(event) }
    }
    private func scrollToBottomAndCapture(_ name: String) throws {
        guard let view = window?.contentView, let state else { throw UserError("页面不存在") }
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        guard let scroll = find(view), let document = scroll.documentView else { throw UserError("未找到可滚动区域") }
        let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentView.bounds.height) : 0
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y)); scroll.reflectScrolledClipView(scroll.contentView)
        view.layoutSubtreeIfNeeded()
        try saveView(view, to: state.dataFolder.appendingPathComponent(name))
        print("界面通过：页面底部可滚动到达 · \(name)")
    }
}
#endif
