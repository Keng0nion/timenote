import Foundation

struct ProbeStamp: Codable, Equatable {
    let at: Date
    let elapsed: Double
}

struct ProbeTiming: Codable, Equatable {
    enum Outcome: String, Codable { case returned, threw }
    let step: String
    let began: ProbeStamp
    var ended: ProbeStamp?
    var outcome: Outcome?
}

// 同步、纯内存测量；不打开设备或写文件，时间来自调用方。
final class ProbeTrace {
    private(set) var timings: [ProbeTiming] = []

    func measure<T>(_ step: String, stamp: () -> ProbeStamp, operation: () throws -> T) rethrows -> T {
        let index = timings.count
        timings.append(ProbeTiming(step: step, began: stamp()))
        do {
            let value = try operation()
            timings[index].ended = stamp()
            timings[index].outcome = .returned
            return value
        } catch {
            timings[index].ended = stamp()
            timings[index].outcome = .threw
            throw error
        }
    }
}

enum ProbeLog {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // 数值Unix秒保留亚秒精度；默认ISO8601编码会抹去试验偏差。
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(value)
    }
}
