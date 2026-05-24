// Self-contained generator for the Mosaic placeholder app icon.
// Renders a flat blue rounded square with a 3×3 white dot grid.
// Run: swift /tmp/gen-mosaic-icon.swift <output-path-1024.png>
//
// Produces a 1024×1024 PNG. Caller is responsible for using `sips` to derive
// the smaller variants the asset catalog requires.

import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: gen-mosaic-icon.swift <output.png>\n".data(using: .utf8)!)
    exit(2)
}
let outPath = CommandLine.arguments[1]

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bgRect = NSRect(x: 0, y: 0, width: size, height: size)
let cornerRadius = size * 0.22
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
NSColor(red: 0.16, green: 0.38, blue: 0.82, alpha: 1.0).setFill()
bgPath.fill()

let dotRadius: CGFloat = size * 0.062
let spacing: CGFloat = size * 0.20
let center = size / 2
for ix in -1...1 {
    for iy in -1...1 {
        let rect = NSRect(
            x: center + CGFloat(ix) * spacing - dotRadius,
            y: center + CGFloat(iy) * spacing - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
