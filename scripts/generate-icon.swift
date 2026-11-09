#!/usr/bin/env swift
import AppKit

// Legacy .icns artwork for macOS 14+; no Icon Composer runtime required.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Resources", isDirectory: true)
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
let iconset = temporary.appendingPathComponent("Dyland.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}
func render(_ size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create icon bitmap") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    let tile = rounded(NSRect(x: 100, y: 100, width: 824, height: 824), radius: 184)
    NSGradient(starting: color(0x18394D), ending: color(0x091725))!.draw(in: tile, angle: -90)

    // Two overlapping solid shapes form one floating island, not a UI screenshot.
    color(0x167DAD).setFill()
    rounded(NSRect(x: 212, y: 356, width: 600, height: 260), radius: 130).fill()
    color(0x64E4F2).setFill()
    rounded(NSRect(x: 212, y: 434, width: 600, height: 222), radius: 111).fill()

    // Detached signal keeps the silhouette recognizable in monochrome.
    color(0x64E4F2).setFill()
    NSBezierPath(ovalIn: NSRect(x: 716, y: 722, width: 70, height: 70)).fill()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon PNG") }
    return data
}

for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let suffix = factor == 2 ? "@2x" : ""
        let data = try render(size * factor)
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        if size * factor == 1024 { try data.write(to: assets.appendingPathComponent("Dyland.png")) }
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("Dyland.icns").path]
try process.run()
process.waitUntilExit()
precondition(process.terminationStatus == 0, "iconutil failed")
guard let icon = NSImage(contentsOf: assets.appendingPathComponent("Dyland.icns")) else { fatalError("Invalid icon") }
precondition(!icon.representations.isEmpty)
print("Dyland icon generated: 16-1024 px, PNG and ICNS")
