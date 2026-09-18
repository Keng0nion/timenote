import AppKit
import AVFoundation
import Foundation

struct ProbeObservation: Codable {
    let at: Date
    let elapsed: Double
    let note: String
}

struct ProbeReport: Encodable {
    let format = "timenote-alarm-probe-v2"
    let trialID: String
    let processID: Int32
    let systemVersion: String
    let options: ProbeOptions
    let state: String
    let verdict: String
    let events: [ProbeEvent]
    let observations: [ProbeObservation]
    let timings: [ProbeTiming]
}

@MainActor
final class ProbeWindow: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let options: ProbeOptions
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "尚未开始，不发声。请先检查输出设备和系统音量。")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var startButton: NSButton!
    private var closeButton: NSButton!
    private var snoozeButton: NSButton!
    private var heardButton: NSButton!
    private var stoppedButton: NSButton!
    private var session: ProbeSession?
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?
    private var origin: ContinuousClock.Instant?
    private var reportURL: URL?
    private var observations: [ProbeObservation] = []
    private let trace = ProbeTrace()
    private let trialID = UUID().uuidString
    private var recordFailure: String?

    init(options: ProbeOptions) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let item = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "中止并退出验证", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = applicationMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "时间便签 · 独立提醒验证（不是正式软件）"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: "只验证一条虚构提醒")
        heading.font = .boldSystemFont(ofSize: 21)
        let boundary = NSTextField(wrappingLabelWithString: "不会打开正式应用、读写任务、注册后台、改变音量或安排唤醒。请勿佩戴耳机测试。音频接口成功不代表人耳听到；所有结果仍需人工核对。")
        detail.stringValue = "点击开始后 \(options.delay) 秒到点；允许回调偏差 \(options.tolerance) 秒。\n安全时限 \(options.maximumDuration) 秒；播放器相对音量 \(options.volume)。\n声音约每1.2秒一声，直到关闭、稍后或中止。Esc／⌘Q／关窗口可停止退出。"
        startButton = button("开始本次已批准试验", #selector(startTrial))
        closeButton = button("关闭本次提醒", #selector(closeAlarm))
        snoozeButton = button("稍后5分钟", #selector(snoozeAlarm))
        heardButton = button("记录：我已听到声音", #selector(markHeard))
        stoppedButton = button("记录：我确认声音已停止", #selector(markStopped))
        let exit = button("中止并退出", #selector(exitTrial))
        exit.keyEquivalent = "\u{1b}"
        let views: [NSView] = [heading, boundary, detail, status, startButton,
                               NSStackView(views: [closeButton, snoozeButton]),
                               NSStackView(views: [heardButton, stoppedButton]), exit]
        for view in views {
            stack.addArrangedSubview(view)
        }
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
                stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
            ])
        }
        refresh()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }

    private func elapsed() -> Double {
        guard let origin else { return 0 }
        let parts = origin.duration(to: ContinuousClock().now).components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    private func stamp() -> ProbeStamp {
        ProbeStamp(at: Date(), elapsed: elapsed())
    }

    @objc private func startTrial() {
        guard session == nil else { return }
        do {
            let directory = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
                .deletingLastPathComponent().appendingPathComponent("trial-" + trialID, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            reportURL = directory.appendingPathComponent("events.json")
            origin = ContinuousClock().now
            session = try ProbeSession(now: Date(), elapsed: elapsed(), delay: options.delay,
                                       tolerance: options.tolerance, maximumDuration: options.maximumDuration)
            observe("用户在窗口点击开始；输出设备及实际系统音量由用户核对，程序不读取或修改")
            guard persist() else { refresh(); return }
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.tick()
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
                }
            }
        } catch {
            stopForError("无法准备试验：" + error.localizedDescription)
        }
        refresh()
    }

    private func tick() {
        guard session != nil, session?.state.finished == false else { ticker?.cancel(); return }
        let before = session?.events.count
        let effect = session!.advance(now: Date(), elapsed: elapsed())
        // 先保存到点事件，再碰音频设备；记录不能写入时不继续发声。
        if effect == .startSound && !persist() { refresh(); return }
        apply(effect)
        if session?.state == .ringing, player?.isPlaying != true {
            stopForError("音频播放器未持续播放")
        }
        if before != session?.events.count { _ = persist() }
        if session?.state.finished == true { ticker?.cancel() }
        refresh()
    }

    private func apply(_ effect: ProbeEffect) {
        switch effect {
        case .none: break
        case .stopSound: stopAudio()
        case .startSound:
            do {
                let data = trace.measure("waveData", stamp: stamp) { ProbeTone.waveData() }
                let audio = try trace.measure("playerInit", stamp: stamp) {
                    try AVAudioPlayer(data: data, fileTypeHint: "wav")
                }
                audio.volume = Float(options.volume)
                audio.numberOfLoops = -1
                player = audio
                let played = trace.measure("playCall", stamp: stamp) { audio.play() }
                guard played else { throw ProbeError(message: "播放接口返回失败") }
                observe("播放接口返回成功；仅为软件事件，不代表扬声器第一声或用户听到")
            } catch { stopForError("音频失败：" + error.localizedDescription) }
        }
    }

    private func stopAudio() {
        guard let audio = player else { return }
        trace.measure("stopCall", stamp: stamp) { audio.stop() }
        player = nil
        observe("停止接口已返回；实际声音停止仍由人工确认")
    }

    @objc private func closeAlarm() {
        guard session != nil else { return }
        observe("窗口收到关闭提醒请求；不是声音已经停止的证明")
        let effect = session!.close(now: Date(), elapsed: elapsed())
        apply(effect)
        ticker?.cancel()
        _ = persist()
        refresh()
    }

    @objc private func snoozeAlarm() {
        guard session != nil else { return }
        observe("窗口收到稍后请求；不是声音已经停止的证明")
        do {
            let effect = try session!.snooze(now: Date(), elapsed: elapsed())
            apply(effect)
            _ = persist()
        } catch {
            observe(error.localizedDescription)
            _ = persist()
        }
        refresh()
    }

    @objc private func markHeard() {
        guard session?.state == .ringing else { return }
        observe("用户点击：已听到声音（点击时间含人的反应时间，不等于第一声精确时间）")
        _ = persist()
        refresh()
    }

    @objc private func markStopped() {
        guard let session, session.state == .snoozed || session.state.finished else { return }
        observe("用户点击：确认声音已停止")
        _ = persist()
        refresh()
    }

    @objc private func exitTrial() {
        observe("窗口收到中止并退出请求")
        NSApp.terminate(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        observe("窗口收到关闭窗口请求")
        NSApp.terminate(nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        observe("应用收到终止请求；不代表进程已退出")
        ticker?.cancel()
        stopAudio()
        if session != nil {
            if session?.state.finished == false {
                _ = session!.abort(reason: "用户退出验证程序", now: Date(), elapsed: elapsed())
            }
            observe("终止回调即将返回；进程退出需启动器核对，未注册后台或安排唤醒")
            _ = persist()
        }
        return .terminateNow
    }

    private func observe(_ text: String) {
        observations.append(ProbeObservation(at: Date(), elapsed: elapsed(), note: text))
    }

    private func stopForError(_ message: String) {
        stopAudio()
        ticker?.cancel()
        if session != nil { _ = session!.abort(reason: message, now: Date(), elapsed: elapsed()) }
        observe(message)
        recordFailure = message
    }

    private func persist() -> Bool {
        guard let session, let reportURL else { return false }
        do {
            // 本次写入的结束时间只能进入后续快照，避免为测量再递归写盘。
            try trace.measure("persist", stamp: stamp) {
                let report = ProbeReport(trialID: trialID, processID: ProcessInfo.processInfo.processIdentifier,
                                         systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                                         options: options, state: session.state.rawValue,
                                         verdict: "未自动判定；需要人工声音、时刻、场景及恢复证据",
                                         events: session.events, observations: observations, timings: trace.timings)
                try ProbeLog.encode(report).write(to: reportURL, options: .atomic)
            }
            return true
        } catch {
            stopForError("记录保存失败，已停止试验：" + error.localizedDescription)
            return false
        }
    }

    private func refresh() {
        startButton?.isEnabled = session == nil && recordFailure == nil
        closeButton?.isEnabled = session?.state == .ringing
        snoozeButton?.isEnabled = session?.state == .ringing && elapsed() + 300 + options.tolerance < (session?.safetyDeadline ?? 0)
        heardButton?.isEnabled = session?.state == .ringing
        stoppedButton?.isEnabled = session != nil && (session?.state == .snoozed || session?.state.finished == true)
        guard let session else {
            if let recordFailure { status.stringValue = recordFailure }
            return
        }
        let deviation = session.lastLateness.map { String(format: "；请求偏差 %.3f 秒", $0) } ?? ""
        let safety = max(0, session.safetyDeadline - elapsed())
        status.stringValue = "\(session.state.rawValue)\(deviation)\n安全时限剩余 \(Int(safety)) 秒；人工／软件观察 \(observations.count) 条。\n\(recordFailure ?? observations.last?.note ?? "")"
    }
}

@main
struct AlarmProbeMain {
    @MainActor static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] { print(ProbeOptions.help); return }
        let options: ProbeOptions
        do { options = try ProbeOptions(arguments: arguments) } catch {
            FileHandle.standardError.write(Data(("拒绝启动：" + error.localizedDescription + "\n使用 --help 查看说明。\n").utf8))
            exit(2)
        }
        let app = NSApplication.shared
        let delegate = ProbeWindow(options: options)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}
