// 앱 아이콘(Resources/AppIcon.icns) 생성 스크립트
// 사용법: swift scripts/make-icon.swift
import AppKit

//#region 1024px 원본 그리기
func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let s = size / 1024
        // 배경: macOS 아이콘 규격의 둥근 사각형 + 그라데이션
        let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 100 * s, dy: 100 * s), xRadius: 185 * s, yRadius: 185 * s)
        NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.98, alpha: 1),
                   ending: NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.45, alpha: 1))!.draw(in: bg, angle: -90)

        // 메뉴바 모양의 숫자 상자 3개, 가운데가 현재 데스크탑
        let boxW = 190 * s, boxH = 170 * s, gap = 40 * s
        let totalW = boxW * 3 + gap * 2
        let y = (size - boxH) / 2
        let font = NSFont.systemFont(ofSize: 120 * s, weight: .bold)
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        for i in 0..<3 {
            let x = (size - totalW) / 2 + CGFloat(i) * (boxW + gap)
            let box = NSRect(x: x, y: y, width: boxW, height: boxH)
            let path = NSBezierPath(roundedRect: box, xRadius: 36 * s, yRadius: 36 * s)
            let isCurrent = i == 1
            if isCurrent {
                NSColor.white.setFill()
                path.fill()
            } else {
                NSColor.white.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 14 * s
                path.stroke()
            }
            let color = isCurrent ? NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.70, alpha: 1) : NSColor.white
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
            let label = "\(i + 1)" as NSString
            let h = label.size(withAttributes: attrs).height
            label.draw(in: NSRect(x: box.minX, y: box.midY - h / 2, width: boxW, height: h), withAttributes: attrs)
        }
        return true
    }
}
//#endregion

//#region iconset 생성 후 icns 변환
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawIcon(size: CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try task.run()
task.waitUntilExit()
print("Wrote Resources/AppIcon.icns")
//#endregion
