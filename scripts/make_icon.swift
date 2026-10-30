import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let rect = CGRect(x: 40, y: 40, width: 944, height: 944)
let clip = CGPath(roundedRect: rect, cornerWidth: 215, cornerHeight: 215, transform: nil)
ctx.addPath(clip); ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let bg = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.13, green: 0.10, blue: 0.30, alpha: 1), CGColor(red: 0.02, green: 0.02, blue: 0.07, alpha: 1)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])

let c = CGPoint(x: 512, y: 512)
// Guide circles
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
ctx.setLineWidth(6)
ctx.strokeEllipse(in: CGRect(x: c.x - 380, y: c.y - 380, width: 760, height: 760))

// Hypotrochoid
let R = 380.0, r = 228.0, d = 300.0
let k = (R - r) / r
let pts: [CGPoint] = (0...1200).map { i in
    let t = Double(i) / 1200 * 2 * Double.pi * 3
    return CGPoint(x: c.x + (R - r) * cos(t) + d * cos(k * t) * 0.62, y: c.y + (R - r) * sin(t) - d * sin(k * t) * 0.62)
}
let stops: [(CGFloat, CGFloat, CGFloat)] = [(0.1, 0.92, 0.72), (0.2, 0.62, 1.0), (0.72, 0.32, 1.0), (1.0, 0.36, 0.7)]
for pass in 0..<2 {
    for i in 1..<pts.count {
        let u = Double(i) / Double(pts.count - 1) * 3
        let f = u - floor(u)
        let s = min(Int(f * 3), 2)
        let ff = CGFloat(f * 3 - Double(s))
        let a = stops[s], b = stops[s + 1]
        let col = CGColor(red: a.0 + (b.0 - a.0) * ff, green: a.1 + (b.1 - a.1) * ff, blue: a.2 + (b.2 - a.2) * ff, alpha: pass == 0 ? 0.18 : 1)
        ctx.setStrokeColor(col)
        ctx.setLineWidth(pass == 0 ? 26 : 8)
        ctx.setLineCap(.round)
        ctx.move(to: pts[i - 1]); ctx.addLine(to: pts[i]); ctx.strokePath()
    }
}
// Rolling wheel
let wc = CGPoint(x: c.x + (R - r) * cos(0.9), y: c.y + (R - r) * sin(0.9))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
ctx.setLineWidth(7)
ctx.strokeEllipse(in: CGRect(x: wc.x - r, y: wc.y - r, width: 2 * r, height: 2 * r))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fillEllipse(in: CGRect(x: wc.x - 12, y: wc.y - 12, width: 24, height: 24))
NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments[1]
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
