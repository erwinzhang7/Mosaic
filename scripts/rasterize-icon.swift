// Rasterize an SVG into a set of PNG sizes for the macOS asset catalog.
//
// Usage:
//   swift scripts/rasterize-icon.swift <input.svg> <output-dir> <prefix> <size1> [size2] ...
//
// Writes <prefix>-<size>.png into <output-dir> for each requested size,
// overwriting any existing files. The matching Contents.json must already
// reference those filenames — this script only produces the bitmaps.
//
// Examples:
//   App icon:
//     swift scripts/rasterize-icon.swift scripts/mosaic-icon-dark.svg \
//       Sources/Resources/Assets.xcassets/AppIcon.appiconset \
//       icon 16 32 64 128 256 512 1024
//
//   Menu-bar template image:
//     swift scripts/rasterize-icon.swift scripts/mosaic-menubar-template.svg \
//       Sources/Resources/Assets.xcassets/MenuBarIcon.imageset \
//       menubar 18 36
//
// NSImage parses SVG natively on modern macOS via CoreSVG. A non-fatal
// "CoreSVG has logged an error" warning is sometimes printed for SVGs that
// use features CoreSVG silently ignores; the render still succeeds.

import AppKit
import Foundation

guard CommandLine.arguments.count >= 5 else {
    FileHandle.standardError.write("usage: rasterize-icon.swift <input.svg> <output-dir> <prefix> <size1> [size2] ...\n".data(using: .utf8)!)
    exit(2)
}
let svgPath = CommandLine.arguments[1]
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
let prefix = CommandLine.arguments[3]
let sizes: [Int] = CommandLine.arguments.dropFirst(4).compactMap(Int.init)

guard !sizes.isEmpty else {
    FileHandle.standardError.write("no valid sizes provided\n".data(using: .utf8)!)
    exit(2)
}

guard let source = NSImage(contentsOfFile: svgPath) else {
    FileHandle.standardError.write("NSImage couldn't load \(svgPath)\n".data(using: .utf8)!)
    exit(1)
}

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
    let url = outDir.appending(path: "\(prefix)-\(size).png")
    try png.write(to: url)
    print("wrote \(url.path)")
}
