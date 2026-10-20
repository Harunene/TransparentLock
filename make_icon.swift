// AppIcon.iconset 생성: 하늘색 배경 위 유리창(2×2) + 앞에 겹친 금색 자물쇠
// 사용: swift make_icon.swift && iconutil -c icns AppIcon.iconset

import Cocoa

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS 아이콘 격자: 1024 캔버스에 824 크기 둥근 사각형
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    NSColor.black.setFill()
    bodyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 하늘색 → 남색 배경
    NSGradient(colors: [NSColor(srgbRed: 0.55, green: 0.78, blue: 1.0, alpha: 1),
                        NSColor(srgbRed: 0.20, green: 0.25, blue: 0.70, alpha: 1)])!
        .draw(in: bodyPath, angle: -90)

    // 유리창: 2×2 유리판
    let frame = NSRect(x: 200 * s, y: 210 * s, width: 624 * s, height: 604 * s)
    let bar: CGFloat = 26 * s
    let paneW = (frame.width - bar) / 2, paneH = (frame.height - bar) / 2
    let panes = [(0, 0), (1, 0), (0, 1), (1, 1)].map { c, r in
        NSRect(x: frame.minX + CGFloat(c) * (paneW + bar), y: frame.minY + CGFloat(r) * (paneH + bar),
               width: paneW, height: paneH)
    }
    let glass = NSBezierPath()
    panes.forEach { glass.append(NSBezierPath(roundedRect: $0, xRadius: 18 * s, yRadius: 18 * s)) }

    NSGraphicsContext.saveGraphicsState()
    glass.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.42), NSColor.white.withAlphaComponent(0.12)])!
        .draw(in: frame, angle: -60)
    // 유리에 비친 빛줄기(대각선 두 줄)
    for (offset, width, alpha) in [(-120.0, 70.0, 0.45), (20.0, 26.0, 0.35)] {
        let streak = NSBezierPath()
        let x0 = frame.minX + CGFloat(offset) * s
        streak.move(to: NSPoint(x: x0, y: frame.minY))
        streak.line(to: NSPoint(x: x0 + CGFloat(width) * s, y: frame.minY))
        streak.line(to: NSPoint(x: x0 + CGFloat(width) * s + frame.height, y: frame.maxY))
        streak.line(to: NSPoint(x: x0 + frame.height, y: frame.maxY))
        streak.close()
        NSColor.white.withAlphaComponent(CGFloat(alpha)).setFill()
        streak.fill()
    }
    NSGraphicsContext.restoreGraphicsState()

    // 창틀
    let outer = NSBezierPath(roundedRect: frame.insetBy(dx: -bar, dy: -bar), xRadius: 40 * s, yRadius: 40 * s)
    outer.append(glass.reversed)
    NSColor.white.withAlphaComponent(0.92).setFill()
    outer.fill()

    // 자물쇠(창 앞 오른쪽 아래에 겹침)
    let config = NSImage.SymbolConfiguration(pointSize: 300 * s, weight: .bold)
        .applying(.init(paletteColors: [NSColor(srgbRed: 1.0, green: 0.76, blue: 0.18, alpha: 1)]))
    if let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = lock.size
        let rect = NSRect(x: 830 * s - size.width, y: 150 * s, width: size.width, height: size.height)
        NSGraphicsContext.saveGraphicsState()
        let ls = NSShadow()
        ls.shadowColor = NSColor.black.withAlphaComponent(0.4)
        ls.shadowOffset = NSSize(width: 0, height: -10 * s)
        ls.shadowBlurRadius = 22 * s
        ls.set()
        lock.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: dir)
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("AppIcon.iconset 생성 완료")
