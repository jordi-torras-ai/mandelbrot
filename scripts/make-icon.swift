import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for retina in [1, 2] {
        let size = base * retina
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: size * 4, bitsPerPixel: 32)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let cg = context.cgContext; cg.scaleBy(x: Double(size) / 1024, y: Double(size) / 1024)
        let rect = NSRect(x: 48, y: 48, width: 928, height: 928)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 208, yRadius: 208)
        NSGradient(colors: [NSColor(red: 0.01, green: 0.06, blue: 0.12, alpha: 1), NSColor(red: 0.08, green: 0.24, blue: 0.40, alpha: 1)])!.draw(in: shape, angle: 65)
        NSColor(red: 0.23, green: 0.47, blue: 0.65, alpha: 0.7).setStroke(); shape.lineWidth = 2; shape.stroke()
        let scale = 373.0, origin = NSPoint(x: 687, y: 512)
        func point(_ x: Double, _ y: Double) -> NSPoint { NSPoint(x: origin.x + x * scale, y: origin.y + y * scale) }
        let cardioid = NSBezierPath()
        for i in 0...500 {
            let t = Double(i) * Double.pi * 2 / 500
            let p = point(0.5 * cos(t) - 0.25 * cos(2 * t), 0.5 * sin(t) - 0.25 * sin(2 * t))
            if i == 0 { cardioid.move(to: p) } else { cardioid.line(to: p) }
        }
        cardioid.close()
        let bulbCenter = point(-1, 0)
        cardioid.appendOval(in: NSRect(x: bulbCenter.x - scale * 0.25, y: bulbCenter.y - scale * 0.25, width: scale * 0.5, height: scale * 0.5))
        for (x, y, r) in [(-0.125, 0.744, 0.091), (-0.125, -0.744, 0.091), (-1.309, 0.0, 0.058)] {
            let p = point(x, y)
            cardioid.appendOval(in: NSRect(x: p.x - r * scale, y: p.y - r * scale, width: 2 * r * scale, height: 2 * r * scale))
        }
        let shadow = NSShadow(); shadow.shadowColor = NSColor(red: 0.32, green: 0.72, blue: 1, alpha: 0.85)
        shadow.shadowBlurRadius = 36; shadow.shadowOffset = .zero; shadow.set()
        NSColor.black.setFill(); cardioid.fill()
        NSColor(red: 0.57, green: 0.81, blue: 0.97, alpha: 0.8).setStroke(); cardioid.lineWidth = 2.5; cardioid.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(base)x\(base)\(retina == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
    }
}
