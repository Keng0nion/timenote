import Foundation

struct CheckFailure: Error { let message: String }

@main
struct AlarmProbeChecks {
    static func main() {
        do { try run() } catch {
            let message = (error as? CheckFailure)?.message ?? error.localizedDescription
            FileHandle.standardError.write(Data(("检查失败：" + message + "\n").utf8))
            exit(1)
        }
    }

    static func run() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw CheckFailure(message: message) }
            count += 1
            print("通过：\(message)")
        }
        func rejects(_ message: String, _ body: () throws -> Void) throws {
            do { try body() } catch { try check(true, message); return }
            throw CheckFailure(message: "未拒绝：" + message)
        }
        func session(limit: Double = 600) throws -> ProbeSession {
            try ProbeSession(now: start, elapsed: 0, delay: 10, tolerance: 1, maximumDuration: limit)
        }

        var alarm = try session()
        try check(alarm.state == .waiting && alarm.events.count == 1, "创建只等待并记录虚构试验，不请求声音")
        try check(alarm.advance(now: start.addingTimeInterval(9), elapsed: 9) == .none, "未到点不发声")
        try check(alarm.advance(now: start.addingTimeInterval(10.25), elapsed: 10.25) == .startSound, "容差内首次轮询请求发声")
        try check(alarm.state == .ringing && alarm.lastLateness == 0.25, "保留真实回调偏差，不记为零")
        try check(alarm.advance(now: start.addingTimeInterval(30), elapsed: 30) == .none && alarm.state == .ringing, "时间经过不自动关闭，也不重复请求声音")
        try check(alarm.close(now: start.addingTimeInterval(31), elapsed: 31) == .stopSound && alarm.state == .closed, "用户关闭停止本次提醒")
        try check(alarm.advance(now: start.addingTimeInterval(700), elapsed: 700) == .none && alarm.state == .closed, "已关闭不会再次触发或被安全时限重写")
        try check(alarm.events.filter { $0.kind == .soundRequested }.count == 1, "一次提醒只记录一次发声请求，不冒充听觉证据")

        var exact = try session()
        try check(exact.advance(now: start.addingTimeInterval(10), elapsed: 10) == .startSound, "恰好到点请求发声")
        var edge = try session()
        try check(edge.advance(now: start.addingTimeInterval(11), elapsed: 11) == .startSound && edge.lastLateness == 1, "允许偏差上界仍记录实际偏差")
        var late = try session()
        try check(late.advance(now: start.addingTimeInterval(11.01), elapsed: 11.01) == .stopSound && late.state == .aborted, "超差中止，不以迟到补响冒充准时")
        try check(late.events.allSatisfy { $0.kind != .soundRequested }, "超差没有声音请求记录")

        var snooze = try session()
        _ = snooze.advance(now: start.addingTimeInterval(10), elapsed: 10)
        let snoozeEffect = try snooze.snooze(now: start.addingTimeInterval(12), elapsed: 12)
        try check(snoozeEffect == .stopSound, "稍后立即停止声音")
        try check(snooze.due == start.addingTimeInterval(312) && snooze.state == .snoozed, "默认稍后300秒，以点击时刻为准")
        try check(snooze.advance(now: start.addingTimeInterval(311), elapsed: 311) == .none, "稍后未到时不重新发声")
        try check(snooze.advance(now: start.addingTimeInterval(312.5), elapsed: 312.5) == .startSound, "稍后到点重新请求持续发声")
        try check(snooze.events.filter { $0.kind == .soundRequested }.count == 2, "初次与稍后各自保留发声请求证据")
        try check(snooze.advance(now: start.addingTimeInterval(600), elapsed: 600) == .stopSound && snooze.state == .aborted, "到安全上限中止，不计为产品自动关闭或通过")

        var short = try session(limit: 60)
        _ = short.advance(now: start.addingTimeInterval(10), elapsed: 10)
        let oldDue = short.due
        try rejects("安全时限不足不能安排稍后") { _ = try short.snooze(now: start.addingTimeInterval(12), elapsed: 12) }
        try check(short.state == .ringing && short.due == oldDue, "无效稍后保留本次提醒，仍可手动关闭")
        var waiting = try session()
        try rejects("未响铃不能稍后") { _ = try waiting.snooze(now: start, elapsed: 0) }
        try check(waiting.close(now: start, elapsed: 0) == .stopSound && waiting.state == .aborted, "到点前关闭记为中止而非成功")

        var backwards = try session()
        _ = backwards.advance(now: start.addingTimeInterval(5), elapsed: 5)
        try check(backwards.advance(now: start.addingTimeInterval(4), elapsed: 6) == .stopSound && backwards.state == .aborted, "墙上时钟倒退中止")
        var monotonic = try session()
        _ = monotonic.advance(now: start.addingTimeInterval(5), elapsed: 5)
        try check(monotonic.advance(now: start.addingTimeInterval(6), elapsed: 4) == .stopSound && monotonic.state == .aborted, "连续时钟倒退中止")
        var jump = try session()
        try check(jump.advance(now: start.addingTimeInterval(10), elapsed: 1) == .stopSound && jump.state == .aborted, "系统时间跳变不能伪造准时")
        var invalid = try session()
        try check(invalid.advance(now: start, elapsed: .nan) == .stopSound && invalid.state == .aborted, "非有限时钟输入安全中止")
        var aborted = try session()
        try check(aborted.abort(reason: "人工中止", now: start, elapsed: 0) == .stopSound && aborted.state == .aborted, "人工中止始终停止声音")
        try check(aborted.advance(now: start.addingTimeInterval(10), elapsed: 10) == .none, "中止后不重启")
        try rejects("非有限计划时刻拒绝") { _ = try ProbeSession(now: Date(timeIntervalSince1970: .nan), elapsed: 0, delay: 10, tolerance: 1, maximumDuration: 60) }
        try rejects("负容差拒绝") { _ = try ProbeSession(now: start, elapsed: 0, delay: 10, tolerance: -1, maximumDuration: 60) }
        try rejects("到点不在安全时限内拒绝") { _ = try ProbeSession(now: start, elapsed: 0, delay: 60, tolerance: 1, maximumDuration: 60) }

        let arguments = ["--approve-audio", "--delay", "10", "--tolerance", "1", "--max-duration", "60", "--volume", "0.15"]
        let options = try ProbeOptions(arguments: arguments)
        try check(options.delay == 10 && options.tolerance == 1 && options.maximumDuration == 60 && options.volume == 0.15, "运行必须明确提供所有试验参数")
        try rejects("无参数默认拒绝，不打开音频") { _ = try ProbeOptions(arguments: []) }
        try rejects("缺少显式音频许可拒绝") { _ = try ProbeOptions(arguments: Array(arguments.dropFirst())) }
        try rejects("缺少音量拒绝") { _ = try ProbeOptions(arguments: Array(arguments.dropLast(2))) }
        try rejects("重复选项拒绝") { _ = try ProbeOptions(arguments: arguments + ["--delay", "20"]) }
        try rejects("未知选项拒绝") { _ = try ProbeOptions(arguments: arguments + ["--run-now"]) }
        try rejects("非有限参数拒绝") { _ = try ProbeOptions(arguments: arguments.dropLast(1) + ["nan"]) }
        try rejects("过大音量拒绝") { _ = try ProbeOptions(arguments: arguments.dropLast(1) + ["0.9"]) }
        try rejects("安全时限不可无限延长") { _ = try ProbeOptions(arguments: ["--approve-audio", "--delay", "10", "--tolerance", "1", "--max-duration", "3600", "--volume", "0.15"]) }

        let data = ProbeTone.waveData()
        try check(String(data: data.prefix(4), encoding: .ascii) == "RIFF" && String(data: data[8..<12], encoding: .ascii) == "WAVE", "测试音仅生成内存WAV，不调用音频设备")
        try check(data.count == 44 + 52_920 * 2, "测试音为1.2秒单声道16位PCM")
        let record = try ProbeLog.encode(snooze.events)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let restored = try decoder.decode([ProbeEvent].self, from: record)
        try check(restored == snooze.events, "虚构事件可完整保存重读")
        let rows = try JSONSerialization.jsonObject(with: record) as! [[String: Any]]
        let requestedTime = rows.first { $0["kind"] as? String == "soundRequested" }?["at"] as? Double
        try check(requestedTime == start.addingTimeInterval(10).timeIntervalSince1970, "日志时刻明确采用Unix秒")
        try check(restored.contains { $0.at == start.addingTimeInterval(312.5) }, "日志保留亚秒精度，不用整秒时间掩盖偏差")
        var custom = try session()
        _ = custom.advance(now: start.addingTimeInterval(10), elapsed: 10)
        let customEffect = try custom.snooze(now: start.addingTimeInterval(12), elapsed: 12, seconds: 60)
        try check(customEffect == .stopSound && custom.due == start.addingTimeInterval(72), "无声逻辑支持合法自定义稍后")
        var nanSnooze = try session()
        _ = nanSnooze.advance(now: start.addingTimeInterval(10), elapsed: 10)
        try rejects("非法稍后间隔拒绝") { _ = try nanSnooze.snooze(now: start.addingTimeInterval(12), elapsed: 12, seconds: .nan) }
        try check(nanSnooze.state == .ringing, "非法稍后不修改响铃状态")
        var earlySafety = try session(limit: 60)
        try check(earlySafety.advance(now: start.addingTimeInterval(60), elapsed: 60) == .stopSound && earlySafety.state == .aborted, "安全时限先于迟到发声处理")
        let trace = ProbeTrace()
        var fakeElapsed = 10.125
        func stamp() -> ProbeStamp {
            ProbeStamp(at: start.addingTimeInterval(fakeElapsed), elapsed: fakeElapsed)
        }
        var operations = 0
        let value = trace.measure("虚构成功", stamp: stamp) {
            operations += 1
            fakeElapsed = 10.375
            return 42
        }
        try check(value == 42 && operations == 1, "分段测量只调用一次操作并保留返回值")
        try check(trace.timings.count == 1 && trace.timings[0].step == "虚构成功", "每个操作保留独立步骤名")
        try check(trace.timings[0].began.elapsed == 10.125 && trace.timings[0].ended?.elapsed == 10.375, "分段测量保留连续时钟亚秒起止，不改成整秒")
        try check(trace.timings[0].began.at == start.addingTimeInterval(10.125) && trace.timings[0].outcome == .returned, "墙上时刻与返回结果分开保留")
        let oldSnapshot = trace.timings
        enum ExpectedError: Error { case rejected }
        var sameError = false
        do {
            try trace.measure("虚构失败", stamp: stamp) {
                fakeElapsed = 11.5
                throw ExpectedError.rejected
            }
        } catch ExpectedError.rejected { sameError = true }
        try check(sameError && trace.timings[1].outcome == .threw, "操作抛错仍记录结束并传播原错误，不吞错")
        try check(trace.timings[1].ended?.elapsed == 11.5, "失败耗时同样保留，不伪造成正常返回")
        try check(oldSnapshot.count == 1, "旧测量快照不被后续操作改写")
        var during: [ProbeTiming] = []
        let falseResult = trace.measure("虚构false", stamp: stamp) {
            during = trace.timings
            fakeElapsed = 12
            return false
        }
        try check(!falseResult && trace.timings[2].outcome == .returned, "接口返回false保持false；返回不冒称业务成功")
        try check(during.last?.ended == nil && during.last?.outcome == nil, "执行中只有开始证据，不伪造完成或结果")
        try check(during.last?.ended == nil && trace.timings.last?.ended?.elapsed == 12, "执行中快照不会被后补完成时间静默改写")
        trace.measure("外层", stamp: stamp) {
            fakeElapsed = 12.25
            trace.measure("内层", stamp: stamp) { fakeElapsed = 12.75 }
            fakeElapsed = 13
        }
        try check(trace.timings[3].step == "外层" && trace.timings[4].step == "内层", "嵌套测量按开始顺序保留各自步骤")
        try check(trace.timings[3].ended?.elapsed == 13 && trace.timings[4].ended?.elapsed == 12.75, "嵌套操作结束时间写回自身条目")
        let timingData = try ProbeLog.encode(trace.timings)
        let timingRestored = try decoder.decode([ProbeTiming].self, from: timingData)
        try check(timingRestored == trace.timings, "分段证据编码重读不丢步骤、结果与小数秒")
        let incompleteData = try ProbeLog.encode(during)
        let incompleteRestored = try decoder.decode([ProbeTiming].self, from: incompleteData)
        try check(incompleteRestored.last?.ended == nil && incompleteRestored.last?.outcome == nil, "未完成证据保存重读仍为未完成，不补造退出")
        print("提醒工具无声检查：\(count)项通过；未运行真实声音、睡眠或后台。")
    }
}
