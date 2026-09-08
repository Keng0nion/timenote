import Foundation

public enum ProgressError: Error, LocalizedError, Equatable, Sendable {
    case invalidPercent
    case unsupportedPlannedMinutes
    case totalMinutesOverflow

    public var errorDescription: String? {
        switch self {
        case .invalidPercent:
            return "完成百分比必须是 0 到 100 之间的有限数值。"
        case .unsupportedPlannedMinutes:
            return "当前统计只支持有限的正预计分钟数；零用时的处理方式尚未确认。"
        case .totalMinutesOverflow:
            return "预计用时总和超出可计算范围，无法可靠汇总。"
        }
    }
}

public struct CompletionPercent: Equatable, Codable, Sendable {
    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite, (0...100).contains(value) else {
            throw ProgressError.invalidPercent
        }
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Double.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct PlannedMinutes: Equatable, Codable, Sendable {
    public let value: Double

    public init(_ value: Double) throws {
        guard value.isFinite, value > 0 else {
            throw ProgressError.unsupportedPlannedMinutes
        }
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(Double.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

public struct ProgressSample: Equatable, Sendable {
    public let minutes: PlannedMinutes
    public let completion: CompletionPercent?

    public init(minutes: PlannedMinutes, completion: CompletionPercent?) {
        self.minutes = minutes
        self.completion = completion
    }
}

public struct ProgressSummary: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case noPlan
        case unrecorded
        case recorded
    }

    public let status: Status
    public let completionPercent: Double?
    public let recordedCount: Int
    public let missingCount: Int
    public let recordedMinutes: Double
    public let missingMinutes: Double

    public static func summarize(_ samples: [ProgressSample]) throws -> ProgressSummary {
        var recordedCount = 0
        var recordedMinutes = 0.0
        var missingMinutes = 0.0
        for sample in samples {
            if sample.completion != nil {
                recordedCount += 1
                recordedMinutes += sample.minutes.value
            } else {
                missingMinutes += sample.minutes.value
            }
        }
        guard (recordedMinutes + missingMinutes).isFinite else {
            throw ProgressError.totalMinutesOverflow
        }

        var percent = 0.0
        for sample in samples {
            if let completion = sample.completion {
                // 先归一化权重，避免“巨大用时 × 百分比”溢出。
                percent += (sample.minutes.value / recordedMinutes) * completion.value
            }
        }
        return ProgressSummary(
            status: samples.isEmpty ? .noPlan : (recordedCount == 0 ? .unrecorded : .recorded),
            // 加总舍入可能略越过边界，不改变实际输入的精度。
            completionPercent: recordedCount == 0 ? nil : min(100, max(0, percent)),
            recordedCount: recordedCount,
            missingCount: samples.count - recordedCount,
            recordedMinutes: recordedMinutes,
            missingMinutes: missingMinutes
        )
    }
}
