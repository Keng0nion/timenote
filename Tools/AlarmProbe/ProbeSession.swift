import Foundation

struct ProbeError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ProbeState: String, Codable {
    case waiting = "等待到点"
    case ringing = "已请求持续声音，听觉待确认"
    case snoozed = "稍后等待"
    case closed = "用户已关闭，结果待人工判定"
    case aborted = "试验中止，不计通过"

    var finished: Bool { self == .closed || self == .aborted }
}

enum ProbeEffect { case none, startSound, stopSound }

struct ProbeEvent: Codable, Equatable {
    enum Kind: String, Codable { case created, soundRequested, snoozed, closed, aborted }
    let kind: Kind
    let at: Date
    let elapsed: Double
    let due: Date
    let lateness: Double?
    let detail: String
}

struct ProbeSession {
    private(set) var state: ProbeState = .waiting
    private(set) var due: Date
    private(set) var events: [ProbeEvent] = []
    private(set) var lastLateness: Double?
    let tolerance: Double
    let safetyDeadline: Double
    private let origin: Date
    private let originElapsed: Double
    private var lastTime: Date
    private var lastElapsed: Double

    init(now: Date, elapsed: Double, delay: Double, tolerance: Double, maximumDuration: Double) throws {
        guard now.timeIntervalSince1970.isFinite, elapsed.isFinite, elapsed >= 0,
              delay.isFinite, (5...300).contains(delay), tolerance.isFinite, (0...5).contains(tolerance),
              maximumDuration.isFinite, maximumDuration > delay + tolerance, maximumDuration <= 900,
              (elapsed + maximumDuration).isFinite,
              now.addingTimeInterval(maximumDuration).timeIntervalSince1970.isFinite else {
            throw ProbeError(message: "无效试验参数：延迟5–300秒、容差0–5秒、安全时限需晚于到点且不超过900秒。")
        }
        self.due = now.addingTimeInterval(delay)
        self.tolerance = tolerance
        self.safetyDeadline = elapsed + maximumDuration
        self.origin = now
        self.originElapsed = elapsed
        self.lastTime = now
        self.lastElapsed = elapsed
        record(.created, now: now, elapsed: elapsed, detail: "虚构试验；不关联正式任务，不自动判定通过")
    }

    mutating func advance(now: Date, elapsed: Double) -> ProbeEffect {
        guard !state.finished else { return .none }
        if let reason = clockFailure(now: now, elapsed: elapsed) {
            return abort(reason: reason, now: lastTime, elapsed: lastElapsed)
        }
        lastTime = now
        lastElapsed = elapsed
        guard elapsed < safetyDeadline else {
            return abort(reason: "到达试验安全时限", now: now, elapsed: elapsed)
        }
        guard state == .waiting || state == .snoozed, now >= due else { return .none }
        let lateness = now.timeIntervalSince(due)
        lastLateness = lateness
        guard lateness <= tolerance else {
            return abort(reason: "回调超出本次允许偏差，未请求补响", now: now, elapsed: elapsed)
        }
        state = .ringing
        record(.soundRequested, now: now, elapsed: elapsed, detail: "仅请求音频播放；不证明扬声器发声或用户听到")
        return .startSound
    }

    mutating func close(now: Date, elapsed: Double) -> ProbeEffect {
        guard !state.finished else { return .none }
        if let reason = clockFailure(now: now, elapsed: elapsed) {
            return abort(reason: reason, now: lastTime, elapsed: lastElapsed)
        }
        guard elapsed < safetyDeadline else { return abort(reason: "关闭时已达安全时限", now: now, elapsed: elapsed) }
        guard state == .ringing else { return abort(reason: "未响铃时结束试验", now: now, elapsed: elapsed) }
        state = .closed
        record(.closed, now: now, elapsed: elapsed, detail: "用户关闭；不写入任务进度，是否听到及停止由人工确认")
        return .stopSound
    }

    mutating func snooze(now: Date, elapsed: Double, seconds: Double = 300) throws -> ProbeEffect {
        guard !state.finished else { throw ProbeError(message: "试验已结束，不能稍后。") }
        if let reason = clockFailure(now: now, elapsed: elapsed) {
            return abort(reason: reason, now: lastTime, elapsed: lastElapsed)
        }
        guard elapsed < safetyDeadline else { return abort(reason: "稍后时已达安全时限", now: now, elapsed: elapsed) }
        guard state == .ringing else { throw ProbeError(message: "只有正在提醒时才能稍后。") }
        guard seconds.isFinite, seconds >= 1, elapsed + seconds + tolerance < safetyDeadline else {
            throw ProbeError(message: "安全时限内放不下此次稍后；原提醒继续，请关闭或中止后重做较长试验。")
        }
        lastTime = now
        lastElapsed = elapsed
        due = now.addingTimeInterval(seconds)
        state = .snoozed
        lastLateness = nil
        record(.snoozed, now: now, elapsed: elapsed, detail: "用户选择稍后\(seconds)秒；停止当前声音")
        return .stopSound
    }

    mutating func abort(reason: String, now: Date, elapsed: Double) -> ProbeEffect {
        guard !state.finished else { return .stopSound }
        state = .aborted
        record(.aborted,
               now: now.timeIntervalSince1970.isFinite ? now : lastTime,
               elapsed: elapsed.isFinite ? elapsed : lastElapsed, detail: reason)
        return .stopSound
    }

    private func clockFailure(now: Date, elapsed: Double) -> String? {
        guard now.timeIntervalSince1970.isFinite, elapsed.isFinite else { return "无效时钟读数" }
        guard now >= lastTime, elapsed >= lastElapsed else { return "时钟倒退" }
        // 连续时钟跨睡眠继续计数；系统时刻明显跳变时不能据此证明准时。
        let drift = now.timeIntervalSince(origin) - (elapsed - originElapsed)
        guard abs(drift) <= max(1, tolerance) else { return "系统时刻与连续时钟不一致" }
        return nil
    }

    private mutating func record(_ kind: ProbeEvent.Kind, now: Date, elapsed: Double, detail: String) {
        events.append(ProbeEvent(kind: kind, at: now, elapsed: elapsed, due: due,
                                 lateness: lastLateness, detail: detail))
    }
}
