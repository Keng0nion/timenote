import Foundation

// 只生成数据；无声检查可验证此文件而不加载或打开音频设备。
enum ProbeTone {
    static func waveData() -> Data {
        let rate = 44_100
        let frames = 52_920
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        func u32(_ value: UInt32) {
            u16(UInt16(truncatingIfNeeded: value))
            u16(UInt16(truncatingIfNeeded: value >> 16))
        }
        text("RIFF"); u32(UInt32(36 + frames * 2)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(frames * 2))
        for index in 0..<frames {
            let time = Double(index) / Double(rate)
            let envelope = max(0, min(1, time / 0.03, (0.45 - time) / 0.03))
            let sample = Int16((sin(2 * .pi * 660 * time) * envelope * 0.3 * 32_767).rounded())
            u16(UInt16(bitPattern: sample))
        }
        return data
    }
}
