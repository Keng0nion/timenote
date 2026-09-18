import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var state: AppState?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    var popover: NSPopover?
    let panelMonitor = PanelCloseMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let folder: URL
        #if LOCAL_UI_TEST
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1),
              arguments[index + 1].hasPrefix("/"), arguments.contains("--smoke-test") else {
            print("测试构建必须指定独立数据目录和 --smoke-test"); exit(1)
        }
        folder = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        #else
        folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeNoteNative-v1", isDirectory: true)
        #endif
        let state = AppState(folder: folder)
        self.state = state
        createMenus()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "时间便签 · 0.1.3 公开预览版"
        window.minSize = NSSize(width: 940, height: 690)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView().environmentObject(state))
        window.center(); self.window = window
        showWindow()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "时间便签")
        let menu = NSMenu()
        menu.addItem(actionItem("打开时间便签", #selector(showWindow)))
        menu.addItem(actionItem("新增工作…", #selector(newWork)))
        menu.addItem(.separator())
        let reminder = NSMenuItem(title: "严格提醒尚未启用", action: nil, keyEquivalent: "")
        reminder.isEnabled = false; menu.addItem(reminder)
        menu.addItem(.separator())
        menu.addItem(actionItem("退出时间便签", #selector(quit)))
        statusMenu = menu
        let button = item.button
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button?.target = self
        button?.action = #selector(statusItemClicked(_:))
        statusItem = item
        #if LOCAL_UI_TEST
        if arguments.contains("--dark") { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
        if arguments.contains("--small") { window.setContentSize(NSSize(width: 940, height: 690)) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.smokeTest() }
        #else
        KeyboardShortcuts.onKeyUp(for: .showTimeNote) { [weak self] in self?.showWindow() }
        KeyboardShortcuts.onKeyUp(for: .addTimeNoteWork) { [weak self] in self?.newWork() }
        #endif
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    @objc func statusItemClicked(_ sender: Any?) {
        guard let event = NSApplication.shared.currentEvent, event.type == .rightMouseUp,
              let item = statusItem, let menu = statusMenu else { togglePanel(); return }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }
    func togglePanel() {
        if let panel = popover, panel.isShown {
            panel.performClose(nil)
            return
        }
        // 面板打开时点击图标：瞬态面板先自行关闭，短暂间隔内的再次触发不再重开，形成切换。
        guard Date().timeIntervalSince(panelMonitor.lastClose) > 0.25,
              let button = statusItem?.button else { return }
        let panel = popover ?? makePanel()
        popover = panel
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    private func makePanel() -> NSPopover {
        let panel = NSPopover()
        panel.behavior = .transient
        panel.delegate = panelMonitor
        if let state { panel.contentViewController = NSHostingController(rootView: StatusPanelView().environmentObject(state)) }
        return panel
    }
    @objc func showWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc func newWork() { showWindow(); state?.page = .today; state?.newWork() }
    @objc func settings() { showWindow(); state?.page = .settings }
    @objc func exportBackup() { showWindow(); state?.exportBackup() }
    @objc func quit() {
        if window?.attachedSheet != nil { state?.error = "请先保存或取消正在填写的表单，再退出软件。"; return }
        NSApplication.shared.terminate(nil)
    }
    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; return item
    }
    private func createMenus() {
        let bar = NSMenu()
        let app = NSMenuItem(); let appMenu = NSMenu(title: "时间便签")
        appMenu.addItem(actionItem("设置与备份…", #selector(settings), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "隐藏时间便签", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(actionItem("退出时间便签", #selector(quit), key: "q"))
        app.submenu = appMenu; bar.addItem(app)
        let file = NSMenuItem(); let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(actionItem("新增工作…", #selector(newWork), key: "n"))
        fileMenu.addItem(actionItem("导出备份…", #selector(exportBackup)))
        fileMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        file.submenu = fileMenu; bar.addItem(file)
        let edit = NSMenuItem(); let editMenu = NSMenu(title: "编辑")
        for (name, selector, key) in [("撤销输入", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(NSMenuItem(title: name, action: NSSelectorFromString(selector), keyEquivalent: key))
        }
        edit.submenu = editMenu; bar.addItem(edit)
        let window = NSMenuItem(); let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(actionItem("显示清单", #selector(showWindow)))
        window.submenu = windowMenu; bar.addItem(window)
        NSApplication.shared.mainMenu = bar
    }
    #if LOCAL_UI_TEST
    private func smokeTest() {
        do {
            guard let state, state.repository != nil, let view = window?.contentView else { throw UserError("原生窗口或数据库未打开") }
            guard state.tasks.isEmpty else { throw UserError("界面检查仅能在空的隔离目录运行") }
            let folder = state.dataFolder
            try saveView(view, to: folder.appendingPathComponent("native-empty.png"))
            let repo = try state.requireRepository()
            let goal = try repo.addGoal(title: "试用检查 · 手动目标")
            var draft = PlanDraft(title: "试用检查 · 每日阅读", category: "学习", day: Day.string(Date()), start: 480, end: 510, goalID: goal.id)
            draft.repeatKind = .daily; draft.until = try Day.shifted(draft.day, by: 6)
            try repo.add(draft, now: Date())
            try repo.add(PlanDraft(title: "试用检查 · 写作", category: "创作", day: draft.day, start: 510, end: 600), now: Date())
            let first = try repo.tasks().first { $0.day == draft.day && $0.start == 480 }!
            let second = try repo.tasks().first { $0.title.contains("写作") }!
            try repo.record(taskID: first.id, percent: 100, note: "仅测试数据", now: Date())
            try repo.record(taskID: second.id, percent: 50, note: "仅测试数据", now: Date())
            try state.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.captureSmokePage(0) }
        } catch { print("原生窗口检查失败：\(error)"); exit(1) }
    }
    private func captureSmokePage(_ index: Int) {
        do {
            guard let state, let view = window?.contentView else { throw UserError("窗口已关闭") }
            let pages = AppState.Page.allCases
            if index > 0 { try saveView(view, to: state.dataFolder.appendingPathComponent("native-\(index - 1).png")) }
            if index == pages.count {
                state.newWork()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.finishSmoke() }
                return
            }
            state.page = pages[index]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.captureSmokePage(index + 1) }
        } catch { print("原生截图检查失败：\(error)"); exit(1) }
    }
    private func finishSmoke() {
        do {
            guard let state, let window, let sheet = window.attachedSheet, let view = sheet.contentView else { throw UserError("新增工作原生表单没有打开") }
            try saveView(view, to: state.dataFolder.appendingPathComponent("native-editor.png"))
            let data = try state.requireRepository().backup()
            try data.write(to: state.dataFolder.appendingPathComponent("smoke-backup.json"), options: .atomic)
            print("原生页面检查通过，继续检查本窗口实际输入与保存。")
            exerciseUI()
        } catch { print("原生表单检查失败：\(error)"); exit(1) }
    }
    func saveView(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw UserError("无法截取本软件窗口") }
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        guard let data = rep.representation(using: .png, properties: [:]) else { throw UserError("无法保存截图") }
        try data.write(to: url, options: .atomic)
    }
    #endif
}

@MainActor final class PanelCloseMonitor: NSObject, NSPopoverDelegate {
    var lastClose = Date.distantPast
    func popoverDidClose(_ notification: Notification) { lastClose = Date() }
}

@main struct TimeNoteMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
