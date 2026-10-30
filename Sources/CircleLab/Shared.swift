import SwiftUI
import AppKit
import Vision
import UniformTypeIdentifiers

// MARK: - Math primitives

struct Cx {
    var re: Double
    var im: Double
    init(_ re: Double, _ im: Double) { self.re = re; self.im = im }
    static func + (a: Cx, b: Cx) -> Cx { Cx(a.re + b.re, a.im + b.im) }
    static func - (a: Cx, b: Cx) -> Cx { Cx(a.re - b.re, a.im - b.im) }
    static func * (a: Cx, b: Cx) -> Cx { Cx(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re) }
    static func * (a: Cx, s: Double) -> Cx { Cx(a.re * s, a.im * s) }
    var magnitude: Double { hypot(re, im) }
    var angle: Double { atan2(im, re) }
    var conjugate: Cx { Cx(re, -im) }
    static func polar(_ r: Double, _ theta: Double) -> Cx { Cx(r * cos(theta), r * sin(theta)) }
}

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: Double) -> CGPoint { CGPoint(x: a.x * s, y: a.y * s) }
    var length: Double { hypot(x, y) }
    func distance(to o: CGPoint) -> Double { hypot(x - o.x, y - o.y) }
}

func clamp<T: Comparable>(_ x: T, _ lo: T, _ hi: T) -> T { min(max(x, lo), hi) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }

struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }
}

// MARK: - Colour palettes

enum Palette: String, CaseIterable, Identifiable {
    case aurora = "Aurora", ember = "Ember", ocean = "Ocean", rainbow = "Rainbow"
    case candy = "Candy", ice = "Ice", mono = "Mono"
    var id: String { rawValue }

    private var stops: [SIMD3<Double>] {
        switch self {
        case .aurora: return [[0.10, 0.92, 0.72], [0.20, 0.62, 1.00], [0.72, 0.32, 1.00], [1.00, 0.36, 0.70]]
        case .ember: return [[1.00, 0.96, 0.55], [1.00, 0.58, 0.12], [0.92, 0.16, 0.12], [0.50, 0.06, 0.30]]
        case .ocean: return [[0.72, 1.00, 0.96], [0.10, 0.82, 0.92], [0.12, 0.42, 0.92], [0.28, 0.14, 0.66]]
        case .rainbow: return [[1.0, 0.25, 0.25], [1.0, 0.85, 0.2], [0.3, 0.95, 0.4], [0.2, 0.85, 1.0], [0.4, 0.4, 1.0], [0.95, 0.35, 0.9], [1.0, 0.25, 0.25]]
        case .candy: return [[1.0, 0.52, 0.80], [1.0, 0.86, 0.42], [0.52, 1.0, 0.82], [0.52, 0.72, 1.0], [0.82, 0.58, 1.0]]
        case .ice: return [[1.0, 1.0, 1.0], [0.7, 0.9, 1.0], [0.35, 0.65, 1.0], [0.2, 0.3, 0.8]]
        case .mono: return [[1.0, 1.0, 1.0], [0.62, 0.64, 0.72]]
        }
    }

    func rgb(_ t: Double) -> SIMD3<Double> {
        let s = stops
        let u = clamp(t, 0, 1) * Double(s.count - 1)
        let i = min(Int(u), s.count - 2)
        let f = u - Double(i)
        return s[i] + (s[i + 1] - s[i]) * f
    }

    func color(_ t: Double, opacity: Double = 1) -> Color {
        let c = rgb(t)
        return Color(.sRGB, red: c.x, green: c.y, blue: c.z, opacity: opacity)
    }

    /// Colour for a value that wraps around (0...1 ping-pongs through the ramp).
    func cyclic(_ t: Double, opacity: Double = 1) -> Color {
        let u = t - floor(t)
        return color(u < 0.5 ? u * 2 : 2 - u * 2, opacity: opacity)
    }

    /// Packed RGBA lookup table (little-endian UInt32 with bytes R,G,B,A).
    func lut(size: Int, cyclic: Bool = true) -> [UInt32] {
        (0..<size).map { i in
            let u = Double(i) / Double(size)
            let c = rgb(cyclic ? (u < 0.5 ? u * 2 : 2 - u * 2) : u)
            return packRGB(c.x, c.y, c.z)
        }
    }
}

@inline(__always)
func packRGB(_ r: Double, _ g: Double, _ b: Double) -> UInt32 {
    let R = UInt32(clamp(r, 0, 1) * 255)
    let G = UInt32(clamp(g, 0, 1) * 255)
    let B = UInt32(clamp(b, 0, 1) * 255)
    return (255 << 24) | (B << 16) | (G << 8) | R
}

func rgbComponents(_ color: Color) -> SIMD3<Double> {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
    return SIMD3(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
}

func makeImage(pixels: [UInt32], width: Int, height: Int) -> CGImage? {
    var px = pixels
    return px.withUnsafeMutableBytes { raw -> CGImage? in
        guard let ctx = CGContext(
            data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }
}

// MARK: - Animation clock

final class Clock {
    var t: Double = 0
    var playing = true
    private var last: Date?

    @discardableResult
    func advance(_ now: Date, speed: Double = 1) -> Double {
        if let l = last, playing {
            t += min(now.timeIntervalSince(l), 0.1) * speed
        }
        last = now
        return t
    }

    func reset() { t = 0 }
}

// MARK: - Progressive gradient stroking

/// Strokes points[from..<to] as a number of chunks, each coloured from the palette.
func strokeGradient(
    _ ctx: inout GraphicsContext, points: [CGPoint], from: Int = 0, to: Int? = nil,
    palette: Palette, width: Double, chunks: Int = 64, opacity: Double = 1,
    phase: Double = 0, cyclic: Bool = false, glow: Double = 0
) {
    let end = min(to ?? points.count, points.count)
    guard end - from >= 2 else { return }
    let total = end - from
    let n = min(chunks, max(1, total - 1))
    let style = { (w: Double) in StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round) }
    for pass in 0..<(glow > 0 ? 2 : 1) {
        for c in 0..<n {
            let a = from + c * (total - 1) / n
            let b = from + (c + 1) * (total - 1) / n
            guard b > a else { continue }
            var path = Path()
            path.move(to: points[a])
            for i in (a + 1)...b { path.addLine(to: points[i]) }
            let u = phase + (Double(c) + 0.5) / Double(n)
            let col = cyclic ? palette.cyclic(u, opacity: opacity) : palette.color(u, opacity: opacity)
            if pass == 0 && glow > 0 {
                ctx.stroke(path, with: .color(palette.color(cyclic ? (u - floor(u)) : u, opacity: opacity * 0.16)), style: style(width + glow))
            } else {
                ctx.stroke(path, with: .color(col), style: style(width))
            }
        }
    }
}

// MARK: - Curve utilities

func resampleClosed(_ pts: [Cx], count n: Int) -> [Cx] {
    guard pts.count > 2 else { return pts }
    var closed = pts
    closed.append(pts[0])
    var cum = [0.0]
    for i in 1..<closed.count { cum.append(cum[i - 1] + (closed[i] - closed[i - 1]).magnitude) }
    let total = cum.last!
    guard total > 1e-12 else { return pts }
    var out: [Cx] = []
    out.reserveCapacity(n)
    var seg = 1
    for k in 0..<n {
        let target = total * Double(k) / Double(n)
        while seg < cum.count - 1 && cum[seg] < target { seg += 1 }
        let span = cum[seg] - cum[seg - 1]
        let f = span > 1e-12 ? (target - cum[seg - 1]) / span : 0
        let a = closed[seg - 1], b = closed[seg]
        out.append(Cx(lerp(a.re, b.re, f), lerp(a.im, b.im, f)))
    }
    return out
}

/// Centres on the bounding box and scales so the largest half-extent is 1.
func normalized(_ pts: [Cx]) -> [Cx] {
    guard let f = pts.first else { return pts }
    var minX = f.re, maxX = f.re, minY = f.im, maxY = f.im
    for p in pts {
        minX = min(minX, p.re); maxX = max(maxX, p.re)
        minY = min(minY, p.im); maxY = max(maxY, p.im)
    }
    let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
    let s = max(maxX - minX, maxY - minY) / 2
    guard s > 1e-12 else { return pts }
    return pts.map { Cx(($0.re - cx) / s, ($0.im - cy) / s) }
}

/// Joins separate sub-paths into one chain, always hopping to the nearest unused one.
func chainSubpaths(_ subs: [[CGPoint]]) -> [Cx] {
    var remaining = subs.filter { $0.count > 1 }
    guard !remaining.isEmpty else { return [] }
    var out: [Cx] = []
    var current = remaining.removeFirst()
    while true {
        out.append(contentsOf: current.map { Cx($0.x, $0.y) })
        out.append(Cx(current[0].x, current[0].y))
        guard !remaining.isEmpty else { break }
        let tail = current[0]
        var best = 0
        var bestD = Double.infinity
        for (i, s) in remaining.enumerated() {
            let d = s[0].distance(to: tail)
            if d < bestD { bestD = d; best = i }
        }
        current = remaining.remove(at: best)
    }
    return out
}

func flatten(_ path: CGPath) -> [[CGPoint]] {
    var subs: [[CGPoint]] = []
    var cur: [CGPoint] = []
    var last = CGPoint.zero
    path.applyWithBlock { el in
        let e = el.pointee
        switch e.type {
        case .moveToPoint:
            if cur.count > 1 { subs.append(cur) }
            last = e.points[0]; cur = [last]
        case .addLineToPoint:
            last = e.points[0]; cur.append(last)
        case .addQuadCurveToPoint:
            let c = e.points[0], p = e.points[1]
            for i in 1...8 {
                let t = Double(i) / 8, u = 1 - t
                cur.append(CGPoint(x: u * u * last.x + 2 * u * t * c.x + t * t * p.x,
                                   y: u * u * last.y + 2 * u * t * c.y + t * t * p.y))
            }
            last = p
        case .addCurveToPoint:
            let c1 = e.points[0], c2 = e.points[1], p = e.points[2]
            for i in 1...12 {
                let t = Double(i) / 12, u = 1 - t
                let x = u * u * u * last.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p.x
                let y = u * u * u * last.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p.y
                cur.append(CGPoint(x: x, y: y))
            }
            last = p
        case .closeSubpath:
            if cur.count > 1 { subs.append(cur) }
            cur = []
        @unknown default: break
        }
    }
    if cur.count > 1 { subs.append(cur) }
    return subs
}

enum Outlines {
    static let presetNames = ["Heart", "Star", "Butterfly", "Trefoil", "Infinity", "Gear", "Fish", "Cardioid"]
    static let fonts = ["HelveticaNeue-Bold", "Didot", "SnellRoundhand-Bold", "Futura-Bold", "Chalkduster", "MarkerFelt-Wide", "Zapfino", "Courier-Bold"]

    static func preset(_ name: String) -> [Cx] {
        var raw: [Cx] = []
        let steps = 2000
        func each(_ t0: Double, _ t1: Double, _ f: (Double) -> Cx) {
            for i in 0..<steps { raw.append(f(t0 + (t1 - t0) * Double(i) / Double(steps))) }
        }
        switch name {
        case "Heart":
            each(0, 2 * .pi) { t in Cx(16 * pow(sin(t), 3), 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)) }
        case "Star":
            var v: [Cx] = []
            for i in 0..<10 {
                let r = i % 2 == 0 ? 1.0 : 0.42
                v.append(Cx.polar(r, .pi / 2 + Double(i) * .pi / 5))
            }
            return normalized(resampleClosed(v, count: 1024))
        case "Butterfly":
            each(0, 12 * .pi) { t in
                let r = exp(sin(t)) - 2 * cos(4 * t) + pow(sin((2 * t - .pi) / 24), 5)
                return Cx(sin(t) * r, cos(t) * r)
            }
        case "Trefoil":
            each(0, 2 * .pi) { t in Cx(sin(t) + 2 * sin(2 * t), cos(t) - 2 * cos(2 * t)) }
        case "Infinity":
            each(0, 2 * .pi) { t in
                let d = 1 + sin(t) * sin(t)
                return Cx(cos(t) / d, sin(t) * cos(t) / d)
            }
        case "Gear":
            each(0, 2 * .pi) { t in Cx.polar(1 + 0.12 * tanh(4 * sin(14 * t)), t) }
        case "Fish":
            each(0, 2 * .pi) { t in Cx(cos(t) - pow(sin(t), 2) / 2.0.squareRoot(), sin(t) * cos(t)) }
        default: // Cardioid
            each(0, 2 * .pi) { t in Cx.polar(1 - cos(t), t) }
        }
        return normalized(resampleClosed(raw, count: 1024))
    }

    static func text(_ string: String, fontName: String) -> [Cx] {
        let font = NSFont(name: fontName, size: 200) ?? NSFont.systemFont(ofSize: 200, weight: .heavy)
        let attr = NSAttributedString(string: string.isEmpty ? " " : string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
        let path = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            guard let f = attrs[kCTFontAttributeName] else { continue }
            let ctFont = f as! CTFont
            let n = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var positions = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for i in 0..<n {
                if let gp = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) {
                    path.addPath(gp, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
                }
            }
        }
        var subs = flatten(path)
        subs.sort { ($0.map(\.x).min() ?? 0) < ($1.map(\.x).min() ?? 0) }
        let chain = chainSubpaths(subs)
        guard chain.count > 3 else { return preset("Heart") }
        return normalized(resampleClosed(chain, count: 2048))
    }

    static func image(at url: URL, lightOnDark: Bool) -> [Cx]? {
        guard let img = NSImage(contentsOf: url),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let req = VNDetectContoursRequest()
        req.contrastAdjustment = 1.5
        req.detectsDarkOnLight = !lightOnDark
        req.maximumImageDimension = 512
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([req])
        guard let obs = req.results?.first else { return nil }
        var subs: [[CGPoint]] = obs.topLevelContours.map { c in
            c.normalizedPoints.map { CGPoint(x: Double($0.x), y: Double($0.y)) }
        }
        subs = subs.filter { $0.count > 12 }.sorted { $0.count > $1.count }
        subs = Array(subs.prefix(5))
        let chain = chainSubpaths(subs)
        guard chain.count > 8 else { return nil }
        return normalized(resampleClosed(chain, count: 2048))
    }
}

// MARK: - PNG export

@MainActor
func exportPNG<V: View>(_ view: V, size: CGSize, name: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = name + ".png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = 2
    guard let cg = renderer.cgImage else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

func exportCGImage(_ cg: CGImage, name: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = name + ".png"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

struct ExportButton: View {
    let name: String
    let background: Color
    let draw: (inout GraphicsContext, CGSize) -> Void

    var body: some View {
        Button {
            let size = CGSize(width: 1600, height: 1000)
            let view = ZStack {
                background
                Canvas { ctx, sz in draw(&ctx, sz) }
            }
            exportPNG(view, size: size, name: name)
        } label: {
            Label("Export PNG…", systemImage: "square.and.arrow.up")
        }
        .controlSize(.small)
    }
}

// MARK: - Reusable controls

struct LabScaffold<Content: View, Inspector: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    let inspector: Inspector

    init(title: String, subtitle: String,
         @ViewBuilder content: () -> Content, @ViewBuilder inspector: () -> Inspector) {
        self.title = title; self.subtitle = subtitle
        self.content = content(); self.inspector = inspector()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title3.bold())
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    inspector
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 320)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.055)))
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format = "%.2f"
    var step: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text(String(format: format, value))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: $value, in: range, step: step).controlSize(.small)
            } else {
                Slider(value: $value, in: range).controlSize(.small)
            }
        }
    }
}

struct IntSliderRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        SliderRow(
            title: title,
            value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
            range: Double(range.lowerBound)...Double(range.upperBound),
            format: "%.0f", step: 1
        )
    }
}

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, _ isOn: Binding<Bool>) { self.title = title; self._isOn = isOn }
    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.switch).controlSize(.small).font(.callout)
    }
}

struct PaletteChips: View {
    @Binding var selection: Palette
    var body: some View {
        HStack(spacing: 5) {
            ForEach(Palette.allCases) { p in
                Capsule()
                    .fill(LinearGradient(colors: (0...6).map { p.color(Double($0) / 6) }, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 16)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(selection == p ? 0.95 : 0), lineWidth: 2))
                    .opacity(selection == p ? 1 : 0.65)
                    .onTapGesture { selection = p }
                    .help(p.rawValue)
            }
        }
    }
}

struct PlayControls: View {
    let clock: Clock
    @Binding var playing: Bool
    var body: some View {
        HStack {
            Button {
                playing.toggle(); clock.playing = playing
            } label: {
                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill")
            }
            Button { clock.reset() } label: { Label("Restart", systemImage: "backward.end.fill") }
        }
        .controlSize(.small)
    }
}

struct HintLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.black.opacity(0.45)))
            .padding(12)
            .allowsHitTesting(false)
    }
}
