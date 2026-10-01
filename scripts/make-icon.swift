#!/usr/bin/env swift
// Vẽ biểu tượng app → Support/AppIcon.icns.  Dùng: swift scripts/make-icon.swift
import AppKit

func draw(_ px: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = px / 1024   // đơn vị theo khung 1024

    // Khung biểu tượng macOS: 824 trong canvas 1024, bo góc ~22%.
    let body = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185 * u, yRadius: 185 * u)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24 * u
    shadow.shadowOffset = NSSize(width: 0, height: -10 * u)
    shadow.set()
    NSColor.black.setFill()
    shape.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    shape.addClip()
    NSGradient(colors: [
        NSColor(red: 0.98, green: 0.42, blue: 0.55, alpha: 1),   // hồng
        NSColor(red: 0.52, green: 0.33, blue: 0.95, alpha: 1),   // tím
        NSColor(red: 0.14, green: 0.30, blue: 0.85, alpha: 1),   // xanh
    ])!.draw(in: body, angle: -60)

    // Notch treo từ mép trên, nở thành "đảo": viên thuốc đen.
    let pill = NSRect(x: 232 * u, y: 624 * u, width: 560 * u, height: 300 * u)
    let island = NSBezierPath()
    island.appendRoundedRect(pill, xRadius: 110 * u, yRadius: 110 * u)
    // phần trên phẳng, dính mép: che bo góc trên bằng hình chữ nhật.
    island.appendRect(NSRect(x: pill.minX, y: pill.maxY - 120 * u, width: pill.width, height: 120 * u + 1))
    NSColor(white: 0.04, alpha: 1).setFill()
    island.fill()

    // Camera (trái) và thanh âm thanh (phải) trong đảo.
    NSColor(white: 0.16, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 312 * u, y: 704 * u, width: 56 * u, height: 56 * u)).fill()
    NSColor(red: 0.45, green: 0.55, blue: 1, alpha: 0.9).setFill()
    NSBezierPath(ovalIn: NSRect(x: 330 * u, y: 722 * u, width: 20 * u, height: 20 * u)).fill()

    NSColor.white.setFill()
    for (i, h) in [48.0, 96.0, 64.0, 120.0, 56.0].enumerated() {
        let bar = NSRect(x: (556 + CGFloat(i) * 42) * u, y: (732 - h / 2) * u, width: 24 * u, height: h * u)
        NSBezierPath(roundedRect: bar, xRadius: 12 * u, yRadius: 12 * u).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = "build/AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = draw(CGFloat(size * scale))
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "Support/AppIcon.icns"]
try task.run(); task.waitUntilExit()
try draw(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/AppIcon-preview.png"))
print("✅ Support/AppIcon.icns")
