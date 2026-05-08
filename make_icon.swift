#!/usr/bin/env swift
import Cocoa

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let gc = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = gc

    // Background
    NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s)).fill()

    // Segmented ring — same geometry as the in-app RingView
    let center  = CGPoint(x: s / 2, y: s / 2)
    let radius  = s * 0.38
    let lw      = s * 0.085
    let segments   = 36
    let gapDeg: CGFloat = 7.0
    let segDeg  = 360.0 / CGFloat(segments)
    let drawDeg = segDeg - gapDeg
    let filled  = 27   // 75 % — looks like a sprint well underway
    let accent  = NSColor(red: 0.85, green: 0.18, blue: 0.18, alpha: 1)
    let track   = NSColor(red: 0.20, green: 0.20, blue: 0.22, alpha: 1)

    for i in 0 ..< segments {
        // y-up context: start at 90° (12 o'clock), go clockwise
        let start = 90.0 - CGFloat(i) * segDeg - gapDeg / 2
        let end   = start - drawDeg
        let path  = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: start, endAngle: end, clockwise: true)
        path.lineWidth    = lw
        path.lineCapStyle = .butt
        if i < filled {
            let t = Double(i) / Double(max(filled - 1, 1))
            accent.withAlphaComponent(CGFloat(0.35 + 0.65 * t)).setStroke()
        } else {
            track.setStroke()
        }
        path.stroke()
    }

    return rep.representation(using: .png, properties: [:])
}

let iconset = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16,   "icon_16x16"),    (32,   "icon_16x16@2x"),
    (32,   "icon_32x32"),    (64,   "icon_32x32@2x"),
    (128,  "icon_128x128"),  (256,  "icon_128x128@2x"),
    (256,  "icon_256x256"),  (512,  "icon_256x256@2x"),
    (512,  "icon_512x512"),  (1024, "icon_512x512@2x"),
]

for (size, name) in sizes {
    guard let data = renderIcon(size: size) else { print("Failed: \(name)"); exit(1) }
    try! data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
    print("  \(name).png")
}

let proc = Process()
proc.launchPath = "/usr/bin/iconutil"
proc.arguments  = ["-c", "icns", iconset, "-o", "AppIcon.icns"]
try! proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else { print("iconutil failed"); exit(1) }
try? FileManager.default.removeItem(atPath: iconset)
print("AppIcon.icns ready")
