// Rasterize an SVG into all the PNG sizes the macOS AppIcon catalog needs.
//
// Usage:
//   swift scripts/rasterize-icon.swift <input.svg> <output-dir>
//
// Writes icon-{16,32,64,128,256,512,1024}.png into <output-dir>, overwriting
// any existing files. Asset catalog Contents.json already references those
// filenames, so this is a pure asset refresh — no other config to change.
//
// NSImage parses SVG natively on modern macOS via CoreSVG. A non-fatal
// "CoreSVG has logged an error" warning is sometimes printed for SVGs that
// use features CoreSVG silently ignores; the render still succeeds.

import AppKit
import Foundation

guard CommandLine.arguments.count >= 3 else {
    FileHandle.standardError.write("usage: rasterize-icon.swift <input.svg> <output-dir>\n".data(using: .utf8)!)
    exit(2)
}
let svgPath = CommandLine.arguments[1]
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOfFile: svgPath) else {
    FileHandle.standardError.write("NSImage couldn't load \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}

let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for size in sizes {
    let dim = CGFloat(size)
    source.size = NSSize(width: dim, height: dim)

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { exit(1) }
    rep.size = NSSize(width: dim, height: dim)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    source.draw(in: NSRect(x: 0, y: 0, width: dim, height: dim),
                from: .zero,
                operation: .copy,
                fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    let url = outDir.appending(path: "icon-\(size).png")
    try png.write(to: url)
    print("wrote \(url.path)")
}
