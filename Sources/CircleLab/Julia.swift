import SwiftUI
import AppKit

enum EscapeKind: String, CaseIterable, Identifiable {
    case mandelbrot = "Mandelbrot", julia = "Julia", ship = "Burning Ship", tricorn = "Tricorn"
    var id: String { rawValue }
}

struct EscapeParams {
    var kind: EscapeKind
    var power: Double
    var maxIter: Int
    var center: CGPoint
    var span: Double          // height of the view in complex-plane units
    var c: CGPoint            // Julia constant
    var cycles: Double
    var shift: Double
    var palette: Palette
    var interior: UInt32
}

func renderEscape(_ p: EscapeParams, W: Int, H: Int) -> CGImage? {
    guard W > 4, H > 4 else { return nil }
    let lut = p.palette.lut(size: 1024)
    let buf = UnsafeMutablePointer<UInt32>.allocate(capacity: W * H)
    defer { buf.deallocate() }
    let scale = p.span / Double(min(W, H))
    let kind = p.kind
    let power = p.power
    let intPower = power == power.rounded() && power >= 2 && power <= 8
    let ip = Int(power.rounded())
    let maxIter = p.maxIter
    let bailout = 256.0
    let logBail = log(bailout)
    let logP = log(power)
    let cx0 = p.center.x, cy0 = p.center.y
    let jr = p.c.x, ji = p.c.y
    let cycles = p.cycles, shift = p.shift
    let interior = p.interior

    DispatchQueue.concurrentPerform(iterations: H) { row in
        let py = cy0 - (Double(row) - Double(H) / 2) * scale
        for col in 0..<W {
            let px = cx0 + (Double(col) - Double(W) / 2) * scale
            var zr: Double, zi: Double, cr: Double, ci: Double
            switch kind {
            case .julia: zr = px; zi = py; cr = jr; ci = ji
            case .ship: zr = 0; zi = 0; cr = px; ci = -py
            default: zr = 0; zi = 0; cr = px; ci = py
            }
            var n = 0
            var mag2 = zr * zr + zi * zi
            // Closed-form interior tests for the plain Mandelbrot set.
            if kind == .mandelbrot && power == 2 {
                let q = (px - 0.25) * (px - 0.25) + py * py
                if q * (q + (px - 0.25)) < 0.25 * py * py || (px + 1) * (px + 1) + py * py < 0.0625 {
                    buf[row * W + col] = interior
                    continue
                }
            }
            while n < maxIter && mag2 < bailout * bailout {
                if kind == .ship { zr = abs(zr); zi = abs(zi) }
                if kind == .tricorn { zi = -zi }
                var nr: Double, ni: Double
                if power == 2 {
                    nr = zr * zr - zi * zi; ni = 2 * zr * zi
                } else if intPower {
                    nr = zr; ni = zi
                    for _ in 1..<ip {
                        let t = nr * zr - ni * zi
                        ni = nr * zi + ni * zr
                        nr = t
                    }
                } else {
                    let r = pow(zr * zr + zi * zi, power / 2)
                    let th = atan2(zi, zr) * power
                    nr = r * cos(th); ni = r * sin(th)
                }
                zr = nr + cr; zi = ni + ci
                mag2 = zr * zr + zi * zi
                n += 1
            }
            if n >= maxIter {
                buf[row * W + col] = interior
            } else {
                let nu = log(0.5 * log(mag2) / logBail) / logP
                let mu = Double(n) + 1 - nu
                var t = mu * 0.04 * cycles + shift
                t -= floor(t)
                if !t.isFinite { t = 0 }
                buf[row * W + col] = lut[Int(t * 1023)]
            }
        }
    }
    let pixels = Array(UnsafeBufferPointer(start: buf, count: W * H))
    return makeImage(pixels: pixels, width: W, height: H)
}

final class JuliaModel: ObservableObject {
    @Published var kind: EscapeKind = .mandelbrot { didSet { resetView(); request() } }
    @Published var power = 2.0 { didSet { request() } }
    @Published var maxIter = 300 { didSet { request() } }
    @Published var center = CGPoint(x: -0.5, y: 0) { didSet { request(fast: interacting) } }
    @Published var span = 3.2 { didSet { request(fast: interacting) } }
    @Published var cRe = -0.8 { didSet { request() } }
    @Published var cIm = 0.156 { didSet { request() } }
    @Published var orbitC = false { didSet { updateLoop() } }
    @Published var orbitSpeed = 0.25
    @Published var cycles = 1.0 { didSet { request() } }
    @Published var shift = 0.0 { didSet { request() } }
    @Published var cycleColors = false { didSet { updateLoop() } }
    @Published var palette: Palette = .rainbow { didSet { request() } }
    @Published var quality = 0.85 { didSet { request() } }
    @Published var image: CGImage?

    var viewSize = CGSize(width: 800, height: 600)
    var interacting = false { didSet { if !interacting { request() } } }
    var hover: CGPoint?
    private var phase = 0.0
    private var rendering = false
    private var pending = false
    private var pendingFast = false
    private var loop: Task<Void, Never>?
    private var monitor: Any?

    init() {}

    func resetView() {
        switch kind {
        case .mandelbrot: center = CGPoint(x: -0.5, y: 0); span = 3.2
        case .ship: center = CGPoint(x: -0.4, y: -0.5); span = 3.6
        default: center = .zero; span = 3.2
        }
    }

    var cEffective: CGPoint {
        guard orbitC else { return CGPoint(x: cRe, y: cIm) }
        let r = hypot(cRe, cIm)
        let a = atan2(cIm, cRe) + phase
        return CGPoint(x: r * cos(a), y: r * sin(a))
    }

    private func params() -> EscapeParams {
        EscapeParams(kind: kind, power: power, maxIter: maxIter, center: center, span: span, c: cEffective,
                     cycles: cycles, shift: shift, palette: palette, interior: packRGB(0.015, 0.015, 0.03))
    }

    func request(fast: Bool = false) {
        if rendering { pending = true; pendingFast = fast; return }
        rendering = true
        let p = params()
        let k = (fast ? 0.4 : quality) * 2
        let W = max(8, Int(viewSize.width * k)), H = max(8, Int(viewSize.height * k))
        Task { [weak self] in
            let img = await Task.detached(priority: .userInitiated) { renderEscape(p, W: W, H: H) }.value
            await self?.finishRender(img)
        }
    }

    @MainActor
    private func finishRender(_ img: CGImage?) {
        image = img
        rendering = false
        if pending {
            let f = pendingFast
            pending = false; pendingFast = false
            request(fast: f)
        }
    }

    private func updateLoop() {
        if orbitC || cycleColors { startLoop() } else { loop?.cancel(); loop = nil }
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if self.orbitC { self.phase += self.orbitSpeed * 0.04 }
                if self.cycleColors { self.shift = (self.shift + 0.006).truncatingRemainder(dividingBy: 1) } else if self.orbitC { self.request() }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
        }
    }

    // Zoom keeping the complex point under `anchor` (view coordinates) fixed.
    func zoom(by factor: Double, at anchor: CGPoint?) {
        let newSpan = clamp(span * factor, 1e-12, 12)
        let a = anchor ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let s = min(viewSize.width, viewSize.height)
        let before = CGPoint(x: center.x + (a.x - viewSize.width / 2) * span / s, y: center.y - (a.y - viewSize.height / 2) * span / s)
        let after = CGPoint(x: center.x + (a.x - viewSize.width / 2) * newSpan / s, y: center.y - (a.y - viewSize.height / 2) * newSpan / s)
        interacting = true
        span = newSpan
        center = CGPoint(x: center.x + before.x - after.x, y: center.y + before.y - after.y)
        interacting = false
    }

    func installScroll() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, let h = self.hover else { return e }
            let dy = e.scrollingDeltaY * (e.hasPreciseScrollingDeltas ? 0.01 : 0.08)
            self.zoom(by: exp(-dy), at: h)
            return nil
        }
    }

    func removeScroll() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func exportHighRes() {
        let p = params()
        if let img = renderEscape(p, W: 2400, H: Int(2400 * viewSize.height / max(viewSize.width, 1))) {
            exportCGImage(img, name: "\(kind.rawValue.lowercased())")
        }
    }
}

struct JuliaView: View {
    @ObservedObject var m: JuliaModel
    @State private var dragStart: CGPoint?
    @State private var lastMag = 1.0

    private static let famous: [(String, Double, Double)] = [
        ("Dendrite", 0, 1), ("Rabbit", -0.123, 0.745), ("Dragon", -0.8, 0.156), ("Spiral", -0.70176, -0.3842),
        ("Galaxy", 0.285, 0.01), ("Snow", -0.4, 0.6), ("Lace", 0.355, 0.355)
    ]

    var body: some View {
        LabScaffold(title: "Escape Fractals",
                    subtitle: "Zoom forever into the boundary of the Mandelbrot set, its Julia siblings and friends. Change the exponent to bend the whole family.") {
            GeometryReader { geo in
                ZStack {
                    Color.black
                    if let img = m.image {
                        Image(decorative: img, scale: 1)
                            .resizable().interpolation(.medium)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { ph in
                            switch ph {
                            case .active(let p): m.hover = p
                            case .ended: m.hover = nil
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { v in
                                    if dragStart == nil { dragStart = m.center; m.interacting = true }
                                    let s = m.span / min(geo.size.width, geo.size.height)
                                    m.center = CGPoint(x: dragStart!.x - v.translation.width * s, y: dragStart!.y + v.translation.height * s)
                                }
                                .onEnded { _ in dragStart = nil; m.interacting = false }
                        )
                        .simultaneousGesture(
                            SpatialTapGesture(count: 2).onEnded { v in m.zoom(by: 0.4, at: v.location) }
                        )
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { v in
                                    m.zoom(by: lastMag / max(0.05, v.magnification), at: m.hover)
                                    lastMag = v.magnification
                                }
                                .onEnded { _ in lastMag = 1 }
                        )
                }
                .onAppear { m.viewSize = geo.size; m.request(); m.installScroll() }
                .onDisappear { m.removeScroll() }
                .onChange(of: geo.size) { _, new in m.viewSize = new; m.request() }
                .overlay(alignment: .bottomLeading) {
                    HintLabel(text: String(format: "Drag to pan · scroll or double-click to zoom · %.1e wide", m.span * geo.size.width / max(1, geo.size.height)))
                }
            }
        } inspector: {
            Card("Fractal") {
                Picker("Type", selection: $m.kind) {
                    ForEach(EscapeKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .controlSize(.small)
                SliderRow(title: "Exponent", value: $m.power, range: 2...8, format: "%.2f", step: 0.05)
                IntSliderRow(title: "Detail (iterations)", value: $m.maxIter, range: 30...3000)
                HStack {
                    Button { m.zoom(by: 0.5, at: nil) } label: { Label("Zoom in", systemImage: "plus.magnifyingglass") }
                    Button { m.zoom(by: 2, at: nil) } label: { Label("Zoom out", systemImage: "minus.magnifyingglass") }
                    Button("Reset") { m.resetView() }
                }
                .controlSize(.small)
            }
            if m.kind == .julia {
                Card("Julia constant c") {
                    SliderRow(title: "Real", value: $m.cRe, range: -1.5...1.5, format: "%.4f")
                    SliderRow(title: "Imaginary", value: $m.cIm, range: -1.5...1.5, format: "%.4f")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 5)], spacing: 5) {
                        ForEach(Self.famous, id: \.0) { f in
                            Button(f.0) { m.cRe = f.1; m.cIm = f.2 }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    ToggleRow("Orbit c around the origin", $m.orbitC)
                    if m.orbitC { SliderRow(title: "Orbit speed", value: $m.orbitSpeed, range: 0.02...1) }
                }
            }
            Card("Colour") {
                PaletteChips(selection: $m.palette)
                SliderRow(title: "Colour cycles", value: $m.cycles, range: 0.1...8)
                SliderRow(title: "Colour offset", value: $m.shift, range: 0...1)
                ToggleRow("Cycle colours", $m.cycleColors)
                SliderRow(title: "Render quality", value: $m.quality, range: 0.3...1.5)
            }
            Button { m.exportHighRes() } label: { Label("Export high‑res PNG…", systemImage: "square.and.arrow.up") }
                .controlSize(.small)
        }
    }
}
