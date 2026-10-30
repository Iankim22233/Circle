import SwiftUI

// MARK: - Types

enum FractalMode: String, CaseIterable, Identifiable {
    case generator = "Edge Generator", ifs = "Copy Machine"
    var id: String { rawValue }
}

enum BaseShape: String, CaseIterable, Identifiable {
    case line = "Line", triangle = "Triangle", square = "Square", pentagon = "Pentagon", hexagon = "Hexagon"
    var id: String { rawValue }

    var sides: Int {
        switch self {
        case .line: return 1
        case .triangle: return 3
        case .square: return 4
        case .pentagon: return 5
        case .hexagon: return 6
        }
    }
    var closed: Bool { self != .line }

    /// Clockwise polygon with unit sides, so a generator on the left of each edge points outwards.
    func vertices() -> [Cx] {
        if self == .line { return [Cx(0, 0), Cx(1, 0)] }
        var v: [Cx] = []
        var p = Cx(0, 0)
        var heading = 0.0
        for _ in 0..<sides {
            v.append(p)
            p = p + Cx.polar(1, heading)
            heading -= 2 * .pi / Double(sides)
        }
        return v
    }
}

struct GenPreset {
    var name: String
    var pts: [Cx]
    var alternate = false
    var base: BaseShape = .triangle
    var depth = 4
}

let genPresets: [GenPreset] = [
    GenPreset(name: "Koch", pts: [Cx(0, 0), Cx(1.0 / 3, 0), Cx(0.5, 0.288675), Cx(2.0 / 3, 0), Cx(1, 0)]),
    GenPreset(name: "Minkowski", pts: [Cx(0, 0), Cx(0.25, 0), Cx(0.25, 0.25), Cx(0.5, 0.25), Cx(0.5, 0), Cx(0.5, -0.25), Cx(0.75, -0.25), Cx(0.75, 0), Cx(1, 0)], base: .square, depth: 3),
    GenPreset(name: "Dragon", pts: [Cx(0, 0), Cx(0.5, 0.5), Cx(1, 0)], alternate: true, base: .line, depth: 13),
    GenPreset(name: "Lévy C", pts: [Cx(0, 0), Cx(0.5, 0.5), Cx(1, 0)], base: .line, depth: 13),
    GenPreset(name: "Spike", pts: [Cx(0, 0), Cx(0.33, 0), Cx(0.5, 0.55), Cx(0.67, 0), Cx(1, 0)], base: .triangle, depth: 4),
    GenPreset(name: "Squares", pts: [Cx(0, 0), Cx(1.0 / 3, 0), Cx(1.0 / 3, 1.0 / 3), Cx(2.0 / 3, 1.0 / 3), Cx(2.0 / 3, 0), Cx(1, 0)], base: .square, depth: 4),
    GenPreset(name: "Wave", pts: [Cx(0, 0), Cx(0.25, 0.3), Cx(0.5, 0), Cx(0.75, -0.3), Cx(1, 0)], alternate: false, base: .square, depth: 4),
    GenPreset(name: "Fern-ish", pts: [Cx(0, 0), Cx(0.3, 0), Cx(0.45, 0.35), Cx(0.6, 0), Cx(1, 0)], alternate: true, base: .line, depth: 5)
]

struct IFSMap: Identifiable, Equatable {
    var id = UUID()
    var o: CGPoint   // image of (0,0)
    var x: CGPoint   // image of (1,0)
    var y: CGPoint   // image of (0,1)
    var hue: Double

    var a: Double { x.x - o.x }
    var c: Double { x.y - o.y }
    var b: Double { y.x - o.x }
    var d: Double { y.y - o.y }
    var det: Double { a * d - b * c }
    var affine: CGAffineTransform { CGAffineTransform(a: a, b: c, c: b, d: d, tx: o.x, ty: o.y) }

    func apply(_ p: CGPoint) -> CGPoint { CGPoint(x: a * p.x + b * p.y + o.x, y: c * p.x + d * p.y + o.y) }

    /// Inverse of the linear part applied to (p - o); in the unit frame when 0...1 in both.
    func local(_ p: CGPoint) -> CGPoint? {
        let dt = det
        guard abs(dt) > 1e-12 else { return nil }
        let px = p.x - o.x, py = p.y - o.y
        return CGPoint(x: (d * px - b * py) / dt, y: (-c * px + a * py) / dt)
    }

    static func similarity(scale s: Double, degrees: Double, tx: Double, ty: Double, mirror: Bool = false, hue: Double) -> IFSMap {
        let th = degrees * .pi / 180
        let o = CGPoint(x: tx, y: ty)
        let x = CGPoint(x: tx + s * cos(th), y: ty + s * sin(th))
        let y = mirror ? CGPoint(x: tx + s * sin(th), y: ty - s * cos(th))
                       : CGPoint(x: tx - s * sin(th), y: ty + s * cos(th))
        return IFSMap(o: o, x: x, y: y, hue: hue)
    }

    static func fromAffine(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ e: Double, _ f: Double, scale s: Double, shift t: CGPoint, hue: Double) -> IFSMap {
        // p' = A p + e in raw space; the unit space is p_u = s p + t.
        let tx = s * e + (1 - a) * t.x - b * t.y
        let ty = s * f - c * t.x + (1 - d) * t.y
        let o = CGPoint(x: tx, y: ty)
        return IFSMap(o: o, x: CGPoint(x: tx + a, y: ty + c), y: CGPoint(x: tx + b, y: ty + d), hue: hue)
    }
}

struct IFSPreset {
    var name: String
    var maps: [IFSMap]
}

func makeIFSPresets() -> [IFSPreset] {
    let h = { (i: Int, n: Int) in n > 1 ? Double(i) / Double(n - 1) : 0 }
    var out: [IFSPreset] = []

    out.append(IFSPreset(name: "Sierpinski", maps: [
        .similarity(scale: 0.5, degrees: 0, tx: 0, ty: 0, hue: 0),
        .similarity(scale: 0.5, degrees: 0, tx: 0.5, ty: 0, hue: 0.5),
        .similarity(scale: 0.5, degrees: 0, tx: 0.25, ty: 0.5, hue: 1)
    ]))

    var carpet: [IFSMap] = []
    var idx = 0
    for i in 0..<3 { for j in 0..<3 where !(i == 1 && j == 1) {
        carpet.append(.similarity(scale: 1.0 / 3, degrees: 0, tx: Double(i) / 3, ty: Double(j) / 3, hue: h(idx, 8))); idx += 1
    } }
    out.append(IFSPreset(name: "Carpet", maps: carpet))

    out.append(IFSPreset(name: "Koch", maps: [
        .similarity(scale: 1.0 / 3, degrees: 0, tx: 0, ty: 0, hue: 0),
        .similarity(scale: 1.0 / 3, degrees: 60, tx: 1.0 / 3, ty: 0, hue: 0.33),
        .similarity(scale: 1.0 / 3, degrees: -60, tx: 0.5, ty: 0.288675, hue: 0.66),
        .similarity(scale: 1.0 / 3, degrees: 0, tx: 2.0 / 3, ty: 0, hue: 1)
    ]))

    let r2 = 1 / 2.0.squareRoot()
    out.append(IFSPreset(name: "Dragon", maps: [
        .similarity(scale: r2, degrees: 45, tx: 0, ty: 0, hue: 0.15),
        .similarity(scale: r2, degrees: 135, tx: 1, ty: 0, hue: 0.85)
    ]))
    out.append(IFSPreset(name: "Lévy C", maps: [
        .similarity(scale: r2, degrees: 45, tx: 0, ty: 0, hue: 0.15),
        .similarity(scale: r2, degrees: -45, tx: 0.5, ty: 0.5, hue: 0.85)
    ]))

    var vicsek: [IFSMap] = []
    let spots: [(Double, Double)] = [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)]
    for (i, p) in spots.enumerated() {
        vicsek.append(.similarity(scale: 1.0 / 3, degrees: 0, tx: p.0 / 3, ty: p.1 / 3, hue: h(i, 5)))
    }
    out.append(IFSPreset(name: "Vicsek", maps: vicsek))

    let rr = (3 - 5.0.squareRoot()) / 2
    var penta: [IFSMap] = []
    for i in 0..<5 {
        let ang = Double.pi / 2 + Double(i) * 2 * .pi / 5
        let vx = 0.5 + 0.5 * cos(ang), vy = 0.5 + 0.5 * sin(ang)
        penta.append(.similarity(scale: rr, degrees: 0, tx: (1 - rr) * vx, ty: (1 - rr) * vy, hue: h(i, 5)))
    }
    out.append(IFSPreset(name: "Pentaflake", maps: penta))

    let t = CGPoint(x: 0.5, y: 0.0)
    let s = 0.1
    out.append(IFSPreset(name: "Fern", maps: [
        .fromAffine(0, 0, 0, 0.16, 0, 0, scale: s, shift: t, hue: 0.9),
        .fromAffine(0.85, 0.04, -0.04, 0.85, 0, 1.6, scale: s, shift: t, hue: 0.1),
        .fromAffine(0.2, -0.26, 0.23, 0.22, 0, 1.6, scale: s, shift: t, hue: 0.45),
        .fromAffine(-0.15, 0.28, 0.26, 0.24, 0, 0.44, scale: s, shift: t, hue: 0.7)
    ]))
    return out
}

enum IFSRender: String, CaseIterable, Identifiable {
    case chaos = "Chaos game", copies = "Stacked copies"
    var id: String { rawValue }
}

enum CopyShape: String, CaseIterable, Identifiable {
    case square = "Square", triangle = "Triangle", letterF = "Letter F", circle = "Circle", heart = "Heart", line = "Line"
    var id: String { rawValue }
    var closed: Bool { self != .line }
    var points: [CGPoint] {
        switch self {
        case .square: return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        case .triangle: return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0.5, y: 1)]
        case .letterF:
            let raw: [(Double, Double)] = [(0.12, 0), (0.38, 0), (0.38, 0.4), (0.72, 0.4), (0.72, 0.6), (0.38, 0.6), (0.38, 0.78), (0.92, 0.78), (0.92, 1), (0.12, 1)]
            return raw.map { CGPoint(x: $0.0, y: $0.1) }
        case .circle:
            return (0..<40).map { i in
                let a = Double(i) / 40 * 2 * .pi
                return CGPoint(x: 0.5 + 0.5 * cos(a), y: 0.5 + 0.5 * sin(a))
            }
        case .heart:
            return Outlines.preset("Heart").map { CGPoint(x: ($0.re + 1) / 2, y: ($0.im + 1) / 2) }
        case .line: return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0)]
        }
    }
}

// MARK: - Chaos-game renderer

struct ChaosParams {
    var maps: [IFSMap]
    var W: Int
    var H: Int
    var iterations: Int
    var center: CGPoint
    var pxPerUnit: Double
    var palette: Palette
    var gamma: Double
    var exposure: Double
    var uniform: Bool
    var bigDots: Bool
    var background: SIMD3<Double>
}

func renderChaos(_ p: ChaosParams) -> CGImage? {
    let n = p.maps.count
    let W = p.W, H = p.H
    guard n > 0, W > 8, H > 8 else { return nil }

    var ca = [Double](), cb = [Double](), cc = [Double](), cd = [Double](), ce = [Double](), cf = [Double](), hue = [Double]()
    var cum = [Double]()
    var total = 0.0
    for m in p.maps {
        ca.append(m.a); cb.append(m.b); cc.append(m.c); cd.append(m.d); ce.append(m.o.x); cf.append(m.o.y); hue.append(m.hue)
        total += p.uniform ? 1 : max(abs(m.det), 0.004)
        cum.append(total)
    }
    var lutR = [Float](), lutG = [Float](), lutB = [Float]()
    for i in 0..<256 {
        let c = p.palette.rgb(Double(i) / 255)
        lutR.append(Float(c.x)); lutG.append(Float(c.y)); lutB.append(Float(c.z))
    }

    let count = W * H
    let dens = UnsafeMutablePointer<Float>.allocate(capacity: count)
    let rr = UnsafeMutablePointer<Float>.allocate(capacity: count)
    let gg = UnsafeMutablePointer<Float>.allocate(capacity: count)
    let bb = UnsafeMutablePointer<Float>.allocate(capacity: count)
    dens.initialize(repeating: 0, count: count)
    rr.initialize(repeating: 0, count: count)
    gg.initialize(repeating: 0, count: count)
    bb.initialize(repeating: 0, count: count)
    defer { dens.deallocate(); rr.deallocate(); gg.deallocate(); bb.deallocate() }

    var rng = SplitMix64(seed: 0xC1C1E)
    var x = 0.5, y = 0.5, col = 0.5
    let s = p.pxPerUnit
    let ox = Double(W) / 2 - p.center.x * s
    let oy = Double(H) / 2 + p.center.y * s
    var maxD: Float = 1

    for it in 0..<(p.iterations + 24) {
        let r = rng.unit() * total
        var k = 0
        while k < n - 1 && cum[k] < r { k += 1 }
        let nx = ca[k] * x + cb[k] * y + ce[k]
        let ny = cc[k] * x + cd[k] * y + cf[k]
        x = nx; y = ny
        col = (col + hue[k]) * 0.5
        if !(abs(x) < 1e7 && abs(y) < 1e7) { x = 0.5; y = 0.5 }
        if it < 24 { continue }
        let px = Int(ox + x * s)
        let py = Int(oy - y * s)
        let li = Int(col * 255)
        let x1 = p.bigDots ? px + 1 : px
        let y1 = p.bigDots ? py + 1 : py
        var yy = py
        while yy <= y1 {
            var xx = px
            while xx <= x1 {
                if xx >= 0 && xx < W && yy >= 0 && yy < H {
                    let idx = yy * W + xx
                    dens[idx] += 1
                    rr[idx] += lutR[li]; gg[idx] += lutG[li]; bb[idx] += lutB[li]
                    if dens[idx] > maxD { maxD = dens[idx] }
                }
                xx += 1
            }
            yy += 1
        }
    }

    let expo = Float(p.exposure) * 4
    let denom = log(1 + maxD * expo)
    let gamma = Float(p.gamma)
    let bgR = Float(p.background.x), bgG = Float(p.background.y), bgB = Float(p.background.z)
    let pixels = [UInt32](unsafeUninitializedCapacity: count) { buf, initialized in
        for i in 0..<count {
            let d = dens[i]
            var r = bgR, g = bgG, b = bgB
            if d > 0 {
                let a = powf(log(1 + d * expo) / denom, gamma)
                let inv = 1 / d
                r = rr[i] * inv * a + bgR * (1 - a)
                g = gg[i] * inv * a + bgG * (1 - a)
                b = bb[i] * inv * a + bgB * (1 - a)
            }
            buf[i] = packRGB(Double(r), Double(g), Double(b))
        }
        initialized = count
    }
    return makeImage(pixels: pixels, width: W, height: H)
}

// MARK: - Model

final class FractalModel: ObservableObject {
    @Published var mode: FractalMode = .generator

    // Shared look
    @Published var palette: Palette = .aurora { didSet { ifsDirty = true } }
    @Published var lineWidth = 1.4
    @Published var glow = 0.0
    @Published var background = Color(red: 0.03, green: 0.035, blue: 0.06) { didSet { ifsDirty = true } }
    @Published var animate = false

    // Generator mode
    @Published var gen: [Cx] = genPresets[0].pts { didSet { genDirty = true } }
    @Published var base: BaseShape = .triangle { didSet { genDirty = true } }
    @Published var depth = 4 { didSet { genDirty = true } }
    @Published var flip = false { didSet { genDirty = true } }
    @Published var alternate = false { didSet { genDirty = true } }
    @Published var fillShape = false
    @Published var rotation = 0.0 { didSet { viewDirty = true } }

    private(set) var genPoints: [Cx] = []
    private(set) var viewPoints: [CGPoint] = []
    private(set) var effectiveDepth = 0
    private var genDirty = true
    private var viewDirty = true
    private var viewSize = CGSize.zero

    // IFS mode
    @Published var maps: [IFSMap] = [] { didSet { ifsDirty = true } }
    @Published var selected = 0
    @Published var ifsRender: IFSRender = .chaos { didSet { ifsDirty = true } }
    @Published var detail = 1.0 { didSet { ifsDirty = true } }
    @Published var gamma = 0.6 { didSet { ifsDirty = true } }
    @Published var exposure = 1.0 { didSet { ifsDirty = true } }
    @Published var uniformWeights = false { didSet { ifsDirty = true } }
    @Published var bigDots = false { didSet { ifsDirty = true } }
    @Published var showFrames = true
    @Published var center = CGPoint(x: 0.5, y: 0.5) { didSet { ifsDirty = true } }
    @Published var zoom = 1.0 { didSet { ifsDirty = true } }
    @Published var copyShape: CopyShape = .letterF
    @Published var copyDepth = 5
    @Published var copyFill = true

    var ifsDirty = true
    var fast = false
    private var cachedImage: CGImage?
    private var cachedSize = CGSize.zero
    private var cachedFast = false

    let clock = Clock()
    let ifsPresets = makeIFSPresets()

    init() {
        loadGenPreset(genPresets[0])
        loadIFS(ifsPresets[0])
    }

    // MARK: Generator

    func loadGenPreset(_ p: GenPreset) {
        gen = p.pts; alternate = p.alternate; base = p.base; depth = p.depth; flip = false
        clock.reset()
    }

    func randomGenerator() {
        let n = Int.random(in: 2...5)
        var pts = [Cx(0, 0)]
        for i in 1...n {
            let x = Double(i) / Double(n + 1) + Double.random(in: -0.06...0.06)
            pts.append(Cx(x, Double.random(in: -0.5...0.5)))
        }
        pts.append(Cx(1, 0))
        gen = pts
        alternate = Bool.random()
        depth = 3
    }

    func ensureGenerator() {
        guard genDirty else { return }
        genDirty = false
        viewDirty = true
        var pts = base.vertices()
        if base.closed { pts.append(pts[0]) }
        let g = gen
        let perSeg = max(1, g.count - 1)
        var d = 0
        var segs = pts.count - 1
        while d < depth {
            let next = segs * perSeg
            if perSeg > 1 && next > 450_000 { break }
            segs = next
            d += 1
            if perSeg == 1 { break }
        }
        effectiveDepth = d
        for _ in 0..<d {
            var out: [Cx] = []
            out.reserveCapacity((pts.count - 1) * perSeg + 1)
            out.append(pts[0])
            for i in 0..<(pts.count - 1) {
                let a = pts[i]
                let delta = pts[i + 1] - a
                let flipped = flip != (alternate && i % 2 == 1)
                for j in 1..<g.count {
                    let gj = flipped ? g[j].conjugate : g[j]
                    out.append(a + delta * gj)
                }
            }
            pts = out
        }
        genPoints = pts
    }

    var generatorSummary: String {
        ensureGenerator()
        return "\(max(genPoints.count - 1, 0)) segments · depth \(effectiveDepth)\(effectiveDepth < depth ? " (limited)" : "")"
    }

    func ensureView(_ size: CGSize) {
        ensureGenerator()
        guard viewDirty || size != viewSize else { return }
        viewDirty = false
        viewSize = size
        let cr = cos(rotation * .pi / 180), sr = sin(rotation * .pi / 180)
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        var rot: [CGPoint] = []
        rot.reserveCapacity(genPoints.count)
        for p in genPoints {
            let x = p.re * cr - p.im * sr, y = p.re * sr + p.im * cr
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            rot.append(CGPoint(x: x, y: y))
        }
        let margin = 48.0
        let bw = max(maxX - minX, 1e-9), bh = max(maxY - minY, 1e-9)
        let s = min((size.width - 2 * margin) / bw, (size.height - 2 * margin) / bh)
        let mx = (minX + maxX) / 2, my = (minY + maxY) / 2
        viewPoints = rot.map { CGPoint(x: size.width / 2 + ($0.x - mx) * s, y: size.height / 2 - ($0.y - my) * s) }
    }

    func drawGenerator(_ ctx: inout GraphicsContext, _ size: CGSize, progress: Double) {
        ensureView(size)
        guard viewPoints.count > 1 else { return }
        let n = max(2, Int(Double(viewPoints.count) * clamp(progress, 0, 1)))
        if fillShape && base.closed && progress >= 1 {
            var p = Path()
            p.addLines(viewPoints)
            p.closeSubpath()
            ctx.fill(p, with: .color(palette.color(0.5, opacity: 0.18)))
        }
        strokeGradient(&ctx, points: viewPoints, to: n, palette: palette, width: lineWidth, chunks: 96, glow: glow)
    }

    // MARK: IFS

    func loadIFS(_ preset: IFSPreset) {
        maps = preset.maps
        selected = 0
        fitView()
    }

    func randomIFS() {
        let n = Int.random(in: 2...4)
        var out: [IFSMap] = []
        for i in 0..<n {
            let sx = Double.random(in: 0.3...0.65), sy = Double.random(in: 0.3...0.65)
            let th = Double.random(in: 0...(2 * .pi))
            let skew = Double.random(in: -0.4...0.4)
            let o = CGPoint(x: Double.random(in: 0...0.7), y: Double.random(in: 0...0.7))
            let x = CGPoint(x: o.x + sx * cos(th), y: o.y + sx * sin(th))
            let y = CGPoint(x: o.x + sy * cos(th + .pi / 2 + skew) * (Bool.random() ? 1 : -1), y: o.y + sy * sin(th + .pi / 2 + skew) * (Bool.random() ? 1 : -1))
            out.append(IFSMap(o: o, x: x, y: y, hue: n > 1 ? Double(i) / Double(n - 1) : 0))
        }
        maps = out
        selected = 0
        fitView()
    }

    func addMap() {
        let m = IFSMap.similarity(scale: 0.35, degrees: Double.random(in: 0...360), tx: Double.random(in: 0.1...0.6), ty: Double.random(in: 0.1...0.6), hue: Double.random(in: 0...1))
        maps.append(m)
        selected = maps.count - 1
    }

    func removeSelected() {
        guard maps.count > 1, maps.indices.contains(selected) else { return }
        maps.remove(at: selected)
        selected = min(selected, maps.count - 1)
    }

    func duplicateSelected() {
        guard maps.indices.contains(selected) else { return }
        var m = maps[selected]
        m.id = UUID()
        let d = CGPoint(x: 0.05, y: -0.05)
        m.o = m.o + d; m.x = m.x + d; m.y = m.y + d
        maps.append(m)
        selected = maps.count - 1
    }

    func transformSelected(_ f: (inout IFSMap) -> Void) {
        guard maps.indices.contains(selected) else { return }
        var m = maps[selected]
        f(&m)
        maps[selected] = m
    }

    func fitView() {
        guard !maps.isEmpty else { return }
        var x = 0.5, y = 0.5
        var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
        var rng = SplitMix64(seed: 7)
        var cum: [Double] = []
        var total = 0.0
        for m in maps { total += uniformWeights ? 1 : max(abs(m.det), 0.004); cum.append(total) }
        for i in 0..<30000 {
            let r = rng.unit() * total
            var k = 0
            while k < maps.count - 1 && cum[k] < r { k += 1 }
            let m = maps[k]
            let p = m.apply(CGPoint(x: x, y: y))
            x = p.x; y = p.y
            if !(abs(x) < 1e6 && abs(y) < 1e6) { x = 0.5; y = 0.5 }
            if i > 20 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        }
        guard minX.isFinite else { return }
        center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let span = max(maxX - minX, maxY - minY, 0.05)
        zoom = clamp(0.8 / (0.78 * span), 0.3, 12)
    }

    func viewPoint(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        let s = min(size.width, size.height) * 0.78 * zoom
        return CGPoint(x: size.width / 2 + (p.x - center.x) * s, y: size.height / 2 - (p.y - center.y) * s)
    }

    func mapPoint(_ v: CGPoint, _ size: CGSize) -> CGPoint {
        let s = min(size.width, size.height) * 0.78 * zoom
        return CGPoint(x: (v.x - size.width / 2) / s + center.x, y: -(v.y - size.height / 2) / s + center.y)
    }

    private func chaosImage(for size: CGSize) -> CGImage? {
        if !ifsDirty, let img = cachedImage, size == cachedSize, fast == cachedFast { return img }
        let k = min(2.0, (2_600_000.0 / max(1, size.width * size.height)).squareRoot())
        let W = Int(size.width * k), H = Int(size.height * k)
        let params = ChaosParams(
            maps: maps, W: W, H: H,
            iterations: fast ? 140_000 : Int(1_200_000 * detail),
            center: center, pxPerUnit: Double(min(W, H)) * 0.78 * zoom,
            palette: palette, gamma: gamma, exposure: exposure,
            uniform: uniformWeights, bigDots: bigDots && !fast, background: rgbComponents(background)
        )
        cachedImage = renderChaos(params)
        cachedSize = size
        cachedFast = fast
        ifsDirty = false
        return cachedImage
    }

    func currentImage() -> CGImage? { cachedImage }

    func drawIFS(_ ctx: inout GraphicsContext, _ size: CGSize, handles: Bool) {
        switch ifsRender {
        case .chaos:
            if let img = chaosImage(for: size) {
                ctx.draw(Image(decorative: img, scale: 1, orientation: .up), in: CGRect(origin: .zero, size: size))
            }
        case .copies:
            drawCopies(&ctx, size)
        }
        guard handles && showFrames else { return }
        for (i, m) in maps.enumerated() {
            let sel = i == selected
            let col = palette.color(m.hue)
            let o = viewPoint(m.o, size), px = viewPoint(m.x, size), py = viewPoint(m.y, size)
            let corner = viewPoint(CGPoint(x: m.x.x + m.y.x - m.o.x, y: m.x.y + m.y.y - m.o.y), size)
            var frame = Path()
            frame.move(to: o); frame.addLine(to: px); frame.addLine(to: corner); frame.addLine(to: py); frame.closeSubpath()
            if sel { ctx.fill(frame, with: .color(col.opacity(0.14))) }
            ctx.stroke(frame, with: .color(col.opacity(sel ? 0.95 : 0.5)), style: StrokeStyle(lineWidth: sel ? 1.8 : 1, dash: sel ? [] : [4, 4]))
            var axes = Path()
            axes.move(to: o); axes.addLine(to: px)
            ctx.stroke(axes, with: .color(.white.opacity(sel ? 0.95 : 0.55)), lineWidth: 2.2)
            var yAxis = Path()
            yAxis.move(to: o); yAxis.addLine(to: py)
            ctx.stroke(yAxis, with: .color(.white.opacity(sel ? 0.6 : 0.3)), lineWidth: 1.2)
            let hr = sel ? 6.5 : 4.5
            ctx.fill(Path(ellipseIn: CGRect(x: o.x - hr, y: o.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(col))
            ctx.stroke(Path(ellipseIn: CGRect(x: o.x - hr, y: o.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(.white), lineWidth: 1.2)
            ctx.fill(Path(CGRect(x: px.x - hr, y: px.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(col))
            ctx.stroke(Path(CGRect(x: px.x - hr, y: px.y - hr, width: 2 * hr, height: 2 * hr)), with: .color(.white), lineWidth: 1.2)
            var dia = Path()
            dia.move(to: CGPoint(x: py.x, y: py.y - hr - 1)); dia.addLine(to: CGPoint(x: py.x + hr + 1, y: py.y))
            dia.addLine(to: CGPoint(x: py.x, y: py.y + hr + 1)); dia.addLine(to: CGPoint(x: py.x - hr - 1, y: py.y)); dia.closeSubpath()
            ctx.fill(dia, with: .color(col)); ctx.stroke(dia, with: .color(.white), lineWidth: 1.2)
            let mid = CGPoint(x: (o.x + corner.x) / 2, y: (o.y + corner.y) / 2)
            ctx.draw(Text("\(i + 1)").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color.white.opacity(sel ? 1 : 0.7)), at: mid)
        }
    }

    private func drawCopies(_ ctx: inout GraphicsContext, _ size: CGSize) {
        guard !maps.isEmpty else { return }
        let n = maps.count
        var depth = copyDepth
        if n > 1 {
            while depth > 1 && pow(Double(n), Double(depth)) > 40_000 { depth -= 1 }
        }
        var level: [(CGAffineTransform, Int)] = maps.enumerated().map { ($0.element.affine, $0.offset) }
        if depth > 1 {
            for _ in 1..<depth {
                var next: [(CGAffineTransform, Int)] = []
                next.reserveCapacity(level.count * n)
                for (t, first) in level {
                    for m in maps { next.append((m.affine.concatenating(t), first)) }
                }
                level = next
            }
        }
        let pts = copyShape.points
        var shape = Path()
        shape.addLines(pts)
        if copyShape.closed { shape.closeSubpath() }
        let s = min(size.width, size.height) * 0.78 * zoom
        let toView = CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: size.width / 2 - center.x * s, ty: size.height / 2 + center.y * s)
        var buckets = [Path](repeating: Path(), count: n)
        for (t, first) in level {
            buckets[first].addPath(shape, transform: t.concatenating(toView))
        }
        for (i, path) in buckets.enumerated() {
            let col = palette.color(maps[i].hue)
            if copyShape.closed && copyFill {
                ctx.fill(path, with: .color(col.opacity(0.85)))
                ctx.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 0.4)
            } else {
                ctx.stroke(path, with: .color(col), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Generator editor widget

struct GeneratorEditor: View {
    @Binding var points: [Cx]
    @State private var dragIndex: Int?

    private func toView(_ p: Cx, _ size: CGSize) -> CGPoint {
        let pad = 18.0
        let s = (size.width - 2 * pad)
        return CGPoint(x: pad + p.re * s, y: size.height / 2 - p.im * s)
    }
    private func fromView(_ v: CGPoint, _ size: CGSize) -> Cx {
        let pad = 18.0
        let s = (size.width - 2 * pad)
        return Cx((v.x - pad) / s, (size.height / 2 - v.y) / s)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, sz in
                var axis = Path()
                axis.move(to: toView(Cx(0, 0), sz)); axis.addLine(to: toView(Cx(1, 0), sz))
                ctx.stroke(axis, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                var line = Path()
                for (i, p) in points.enumerated() {
                    let v = toView(p, sz)
                    if i == 0 { line.move(to: v) } else { line.addLine(to: v) }
                }
                ctx.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                for (i, p) in points.enumerated() {
                    let v = toView(p, sz)
                    let end = i == 0 || i == points.count - 1
                    let r = end ? 4.0 : 6.0
                    let rect = CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r)
                    ctx.fill(Path(ellipseIn: rect), with: .color(end ? .gray : .accentColor))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.2)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if dragIndex == nil {
                            var best: Int?
                            var bestD = 14.0
                            for i in 1..<max(1, points.count - 1) {
                                let d = toView(points[i], size).distance(to: v.startLocation)
                                if d < bestD { bestD = d; best = i }
                            }
                            dragIndex = best ?? -1
                        }
                        if let i = dragIndex, i > 0, i < points.count - 1 {
                            var p = fromView(v.location, size)
                            p.re = clamp(p.re, -0.4, 1.4); p.im = clamp(p.im, -0.9, 0.9)
                            points[i] = p
                        }
                    }
                    .onEnded { _ in dragIndex = nil }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { v in
                    var hit: Int?
                    for i in 1..<max(1, points.count - 1) where toView(points[i], size).distance(to: v.location) < 14 { hit = i }
                    if let hit {
                        if points.count > 2 { points.remove(at: hit) }
                    } else {
                        let p = fromView(v.location, size)
                        var bestSeg = 0
                        var bestD = Double.infinity
                        for i in 0..<(points.count - 1) {
                            let a = toView(points[i], size), b = toView(points[i + 1], size)
                            let ab = b - a
                            let t = clamp(((v.location - a).x * ab.x + (v.location - a).y * ab.y) / max(1e-9, ab.x * ab.x + ab.y * ab.y), 0, 1)
                            let d = (a + ab * t).distance(to: v.location)
                            if d < bestD { bestD = d; bestSeg = i }
                        }
                        points.insert(p, at: bestSeg + 1)
                    }
                }
            )
        }
        .frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
    }
}

// MARK: - View

struct FractalView: View {
    @ObservedObject var m: FractalModel
    @State private var drag: DragInfo?

    struct DragInfo {
        enum Kind { case move, xTip, yTip, nothing }
        var index: Int
        var kind: Kind
        var last: CGPoint
    }

    private func beginDrag(at v: CGPoint, size: CGSize) {
        // Handles first (selected map has priority), then frame interiors.
        let order = Array(m.maps.indices).sorted { a, b in a == m.selected ? true : (b == m.selected ? false : a > b) }
        var best: (Int, DragInfo.Kind, Double)?
        for i in order {
            let mp = m.maps[i]
            let cands: [(DragInfo.Kind, CGPoint)] = [(.move, mp.o), (.xTip, mp.x), (.yTip, mp.y)]
            for (k, p) in cands {
                let d = m.viewPoint(p, size).distance(to: v)
                if d < 16 && d < (best?.2 ?? .infinity) - (i == m.selected ? 4 : 0) { best = (i, k, d) }
            }
        }
        let mapP = m.mapPoint(v, size)
        if best == nil {
            for i in order {
                if let l = m.maps[i].local(mapP), l.x >= 0, l.x <= 1, l.y >= 0, l.y <= 1 { best = (i, .move, 0); break }
            }
        }
        if let b = best {
            m.selected = b.0
            drag = DragInfo(index: b.0, kind: b.1, last: mapP)
        } else {
            drag = DragInfo(index: -1, kind: .nothing, last: mapP)
        }
        m.fast = true
    }

    private func continueDrag(to v: CGPoint, size: CGSize) {
        guard var d = drag, d.index >= 0, m.maps.indices.contains(d.index) else { return }
        let p = m.mapPoint(v, size)
        let delta = p - d.last
        var mp = m.maps[d.index]
        switch d.kind {
        case .move:
            mp.o = mp.o + delta; mp.x = mp.x + delta; mp.y = mp.y + delta
        case .xTip: mp.x = mp.x + delta
        case .yTip: mp.y = mp.y + delta
        case .nothing: break
        }
        d.last = p
        drag = d
        m.maps[d.index] = mp
    }

    private func canvasArea() -> some View {
        GeometryReader { geo in
            ZStack {
                m.background
                if m.mode == .generator {
                    TimelineView(.animation(paused: !m.animate)) { tl in
                        let t = m.clock.advance(tl.date)
                        let cycle = 9.0
                        let progress = m.animate ? min(1, (t.truncatingRemainder(dividingBy: cycle)) / 6.5) : 1
                        Canvas { ctx, size in m.drawGenerator(&ctx, size, progress: progress) }
                    }
                    .overlay(alignment: .bottomLeading) {
                        HintLabel(text: m.generatorSummary)
                    }
                } else {
                    Canvas { ctx, size in m.drawIFS(&ctx, size, handles: true) }
                    Color.clear.contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { v in
                                    if drag == nil { beginDrag(at: v.startLocation, size: geo.size) }
                                    continueDrag(to: v.location, size: geo.size)
                                }
                                .onEnded { _ in
                                    drag = nil
                                    m.fast = false
                                    m.ifsDirty = true
                                    m.objectWillChange.send()
                                }
                        )
                        .overlay(alignment: .bottomLeading) {
                            HintLabel(text: "Drag ● to move a copy, ■ to stretch its x-axis, ◆ to stretch its y-axis")
                        }
                }
            }
        }
    }

    var body: some View {
        LabScaffold(title: "Fractal Maker",
                    subtitle: m.mode == .generator
                        ? "Design the zig-zag that replaces every edge. Repeat it on its own edges, over and over, and your fractal appears."
                        : "A photocopier with several reducing lenses. Position the shrunken copies and the shape they converge to is your fractal.") {
            canvasArea()
        } inspector: {
            Picker("Method", selection: $m.mode) {
                ForEach(FractalMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            if m.mode == .generator { generatorControls } else { ifsControls }

            Card("Look") {
                if m.mode == .generator || m.ifsRender == .copies {
                    SliderRow(title: "Line width", value: $m.lineWidth, range: 0.3...6)
                }
                if m.mode == .generator { SliderRow(title: "Glow", value: $m.glow, range: 0...16, format: "%.0f") }
                PaletteChips(selection: $m.palette)
                ColorPicker("Background", selection: $m.background).font(.callout)
            }
            if m.mode == .ifs, m.ifsRender == .chaos, let img = m.currentImage() {
                Button { exportCGImage(img, name: "fractal") } label: { Label("Export PNG…", systemImage: "square.and.arrow.up") }
                    .controlSize(.small)
            } else if m.mode == .generator {
                ExportButton(name: "fractal", background: m.background) { ctx, size in
                    m.drawGenerator(&ctx, size, progress: 1)
                }
            } else {
                ExportButton(name: "fractal", background: m.background) { ctx, size in
                    m.drawIFS(&ctx, size, handles: false)
                }
            }
        }
    }

    @ViewBuilder private var generatorControls: some View {
        Card("Your generator") {
            GeneratorEditor(points: $m.gen)
            Text("Drag the dots. Double-click a line to add a point, a dot to remove it.")
                .font(.caption2).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 5)], spacing: 5) {
                ForEach(genPresets, id: \.name) { p in
                    Button(p.name) { m.loadGenPreset(p) }.buttonStyle(.bordered).controlSize(.small)
                }
                Button { m.randomGenerator() } label: { Label("Surprise", systemImage: "dice") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        Card("Construction") {
            Picker("Start from", selection: $m.base) {
                ForEach(BaseShape.allCases) { Text($0.rawValue).tag($0) }
            }
            .controlSize(.small)
            IntSliderRow(title: "Iterations", value: $m.depth, range: 0...14)
            ToggleRow("Alternate sides (dragon-style)", $m.alternate)
            ToggleRow("Flip to other side", $m.flip)
            if m.base.closed { ToggleRow("Fill the shape", $m.fillShape) }
            SliderRow(title: "Rotation", value: $m.rotation, range: -180...180, format: "%.0f°")
            ToggleRow("Draw-on animation", $m.animate)
        }
    }

    @ViewBuilder private var ifsControls: some View {
        Card("Presets") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 5)], spacing: 5) {
                ForEach(m.ifsPresets, id: \.name) { p in
                    Button(p.name) { m.loadIFS(p) }.buttonStyle(.bordered).controlSize(.small)
                }
                Button { m.randomIFS() } label: { Label("Surprise", systemImage: "dice") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        Card("Copies (\(m.maps.count))") {
            ForEach(Array(m.maps.enumerated()), id: \.element.id) { i, map in
                HStack {
                    Circle().fill(m.palette.color(map.hue)).frame(width: 12, height: 12)
                    Text("Copy \(i + 1)").font(.callout)
                    Spacer()
                    Text(String(format: "scale %.2f", abs(map.det).squareRoot()))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2).padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(i == m.selected ? 0.3 : 0)))
                .contentShape(Rectangle())
                .onTapGesture { m.selected = i }
            }
            HStack {
                Button { m.addMap() } label: { Label("Add", systemImage: "plus") }
                Button { m.duplicateSelected() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button { m.removeSelected() } label: { Label("Remove", systemImage: "minus") }
            }
            .controlSize(.small)
            if m.maps.indices.contains(m.selected) {
                Divider()
                Text("Selected copy").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Flip ↔") { m.transformSelected { mp in mp.x = mp.o + (mp.o - mp.x) } }
                    Button("Flip ↕") { m.transformSelected { mp in mp.y = mp.o + (mp.o - mp.y) } }
                    Button("Rotate 90°") { m.transformSelected { mp in
                        let rx = mp.x - mp.o, ry = mp.y - mp.o
                        mp.x = mp.o + CGPoint(x: -rx.y, y: rx.x); mp.y = mp.o + CGPoint(x: -ry.y, y: ry.x)
                    } }
                }
                .controlSize(.small)
                HStack {
                    Button("Shrink") { m.transformSelected { mp in mp.x = mp.o + (mp.x - mp.o) * 0.9; mp.y = mp.o + (mp.y - mp.o) * 0.9 } }
                    Button("Grow") { m.transformSelected { mp in mp.x = mp.o + (mp.x - mp.o) * 1.1; mp.y = mp.o + (mp.y - mp.o) * 1.1 } }
                }
                .controlSize(.small)
                SliderRow(title: "Colour", value: Binding(
                    get: { m.maps.indices.contains(m.selected) ? m.maps[m.selected].hue : 0 },
                    set: { v in m.transformSelected { $0.hue = v } }), range: 0...1)
            }
        }
        Card("Rendering") {
            Picker("Style", selection: $m.ifsRender) {
                ForEach(IFSRender.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            if m.ifsRender == .chaos {
                SliderRow(title: "Detail", value: $m.detail, range: 0.1...3, format: "%.1f×")
                SliderRow(title: "Brightness curve", value: $m.gamma, range: 0.2...1.5)
                SliderRow(title: "Exposure", value: $m.exposure, range: 0.05...4)
                ToggleRow("Equal use of every copy", $m.uniformWeights)
                ToggleRow("Larger dots", $m.bigDots)
            } else {
                Picker("Starting shape", selection: $m.copyShape) {
                    ForEach(CopyShape.allCases) { Text($0.rawValue).tag($0) }
                }
                .controlSize(.small)
                IntSliderRow(title: "Generations", value: $m.copyDepth, range: 1...10)
                ToggleRow("Filled", $m.copyFill)
            }
            ToggleRow("Show copy frames", $m.showFrames)
            SliderRow(title: "Zoom", value: $m.zoom, range: 0.2...12)
            Button("Fit view to fractal") { m.fitView() }.controlSize(.small)
        }
    }
}
