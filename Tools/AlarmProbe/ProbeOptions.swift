import Foundation

struct ProbeOptions: Codable {
    let delay: Double
    let tolerance: Double
    let maximumDuration: Double
    let volume: Double

    static let help = """
    时间便签独立提醒验证工具（不是正式提醒）
    无参数或缺少明确许可：拒绝运行，不打开窗口或音频设备。
    --help：仅查看说明。
    实际试验必须在另行批准后同时提供：
      --approve-audio       确认本次允许音频试验
      --delay 秒            点击窗口开始后5–300秒到点
      --tolerance 秒        本次允许回调偏差0–5秒，不是产品标准
      --max-duration 秒     从点击开始计的安全时限，最多900秒
      --volume 数值         仅播放器相对音量，大于0且不超过0.25
    参数齐全仍须在窗口点击开始；不会启动正式应用或注册后台。
    关闭／Esc／Command-Q／中止退出会停止；终端Ctrl-C可终止本次进程。
    记录在可执行文件同目录的唯一trial子目录，不收集正式任务。
    音频接口返回成功不代表人耳听到；测试安全中止不计通过。
    """

    init(arguments: [String]) throws {
        let names: Set<String> = ["--delay", "--tolerance", "--max-duration", "--volume"]
        var values: [String: Double] = [:]
        var approved = false
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            if key == "--approve-audio" {
                guard !approved else { throw ProbeError(message: "音频许可参数重复。") }
                approved = true
                index += 1
                continue
            }
            guard names.contains(key), values[key] == nil, index + 1 < arguments.count,
                  let number = Double(arguments[index + 1]), number.isFinite else {
                throw ProbeError(message: "未知、重复或无效的试验参数：\(key)")
            }
            values[key] = number
            index += 2
        }
        guard approved, let delay = values["--delay"], let tolerance = values["--tolerance"],
              let maximum = values["--max-duration"], let volume = values["--volume"],
              volume > 0, volume <= 0.25 else {
            throw ProbeError(message: "需要明确音频许可和全部四项参数；播放器音量必须大于0且不超过0.25。")
        }
        _ = try ProbeSession(now: Date(timeIntervalSince1970: 0), elapsed: 0, delay: delay,
                             tolerance: tolerance, maximumDuration: maximum)
        self.delay = delay
        self.tolerance = tolerance
        self.maximumDuration = maximum
        self.volume = volume
    }
}
