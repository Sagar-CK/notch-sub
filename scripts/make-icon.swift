import AppKit
import Foundation

// Native rendering of the project's orange ST mark from assets/icon.svg.
// Run: swift scripts/make-icon.swift .build/AppIcon.iconset
let output = URL(
  fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let factor = CGFloat(pixels) / 64
    context.cgContext.scaleBy(x: factor, y: factor)
    NSColor(calibratedRed: 234 / 255, green: 88 / 255, blue: 12 / 255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 4, y: 4, width: 56, height: 56), xRadius: 13, yRadius: 13)
      .fill()
    let text = "ST" as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
      .foregroundColor: NSColor.white,
    ]
    let bounds = text.size(withAttributes: attributes)
    text.draw(
      at: NSPoint(x: (64 - bounds.width) / 2, y: (64 - bounds.height) / 2),
      withAttributes: attributes)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    let name = "icon_\(size)x\(size)\(suffix).png"
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: output.appendingPathComponent(name))
  }
}
