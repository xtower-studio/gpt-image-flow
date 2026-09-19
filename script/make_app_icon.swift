import AppKit

// Render the same stacked-paper mark as the native sidebar, without image assets.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (name, pixels) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = AffineTransform(scale: CGFloat(pixels)/1024)
    (scale as NSAffineTransform).concat()
    let base = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
    NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1).setFill(); base.fill()
    NSGraphicsContext.saveGraphicsState()
    let rotation = AffineTransform(rotationByDegrees: 10)
    let move = NSAffineTransform(); move.translateX(by: 420, yBy: 555); move.concat()
    (rotation as NSAffineTransform).concat()
    let back = NSBezierPath(roundedRect: NSRect(x: -205, y: -252, width: 410, height: 504), xRadius: 53, yRadius: 53)
    NSColor(white: 1, alpha: 0.44).setStroke(); back.lineWidth = 13; back.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let front = NSBezierPath(roundedRect: NSRect(x: 361, y: 239, width: 423, height: 519), xRadius: 56, yRadius: 56)
    NSColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill(); front.fill()
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 573, y: 639))
    mark.curve(to: NSPoint(x: 704, y: 505), controlPoint1: NSPoint(x: 586, y: 537), controlPoint2: NSPoint(x: 599, y: 521))
    mark.curve(to: NSPoint(x: 573, y: 371), controlPoint1: NSPoint(x: 599, y: 489), controlPoint2: NSPoint(x: 586, y: 473))
    mark.curve(to: NSPoint(x: 442, y: 505), controlPoint1: NSPoint(x: 560, y: 473), controlPoint2: NSPoint(x: 547, y: 489))
    mark.curve(to: NSPoint(x: 573, y: 639), controlPoint1: NSPoint(x: 547, y: 521), controlPoint2: NSPoint(x: 560, y: 537)); mark.close()
    NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1).setFill(); mark.fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(name).png"))
}
