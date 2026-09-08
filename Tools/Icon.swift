import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sage = NSColor(srgbRed: 0.27, green: 0.50, blue: 0.42, alpha: 1)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("图标画布不可用") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        sage.setFill()
        NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 194, yRadius: 194).fill()
        NSColor(srgbRed: 0.97, green: 0.98, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 233, y: 204, width: 558, height: 640), xRadius: 58, yRadius: 58).fill()
        sage.withAlphaComponent(0.20).setStroke()
        for y in [355, 445] {
            let line = NSBezierPath(); line.lineWidth = 24; line.lineCapStyle = .round
            line.move(to: NSPoint(x: 328, y: y)); line.line(to: NSPoint(x: 624, y: y)); line.stroke()
        }
        sage.setStroke()
        let clock = NSBezierPath(ovalIn: NSRect(x: 402, y: 548, width: 220, height: 220)); clock.lineWidth = 25; clock.stroke()
        let hands = NSBezierPath(); hands.lineWidth = 26; hands.lineCapStyle = .round; hands.lineJoinStyle = .round
        hands.move(to: NSPoint(x: 512, y: 724)); hands.line(to: NSPoint(x: 512, y: 658)); hands.line(to: NSPoint(x: 563, y: 628)); hands.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("图标编码失败") }
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
    }
}
print("时间便签图标已生成；只使用本机 AppKit 绘制。")
