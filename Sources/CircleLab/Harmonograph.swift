import SwiftUI

struct Pendulum: Equatable {
    var amp: Double
    var freq: Double
    var phase: Double
    var damp: Double
}

struct HarmonoPreset {
    var name: String
    var p: [Pendulum]
}

let harmonoPresets: [HarmonoPreset] = [
    HarmonoPreset(name: "Classic", p: [
        Pendulum(amp: 1.0, freq: 3.0, phase: 0, damp: 0.05), Pendulum(amp: 0.6, freq: 2.0, phase: 1.0, damp: 0.05),
        Pendulum(amp: 1.0, freq: 3.01, phase: 1.57, damp: 0.05), Pendulum(amp: 0.6, freq: 2.0, phase: 0, damp: 0.05)]),
    HarmonoPreset(name: "Octave", p: [
        Pendulum(amp: 1.0, freq: 2.0, phase: 0, damp: 0.04), Pendulum(amp: 0.35, freq: 4.0, phase: 0.5, damp: 0.04),
        Pendulum(amp: 1.0, freq: 1.0, phase: 1.57, damp: 0.04), Pendulum(amp: 0.35, freq: 2.0, phase: 0, damp: 0.04)]),
    HarmonoPreset(name: "Fifth", p: [
        Pendulum(amp: 1.0, freq: 3.0, phase: 0, damp: 0.035), Pendulum(amp: 0.45, freq: 6.0, phase: 0.8, damp: 0.035),
        Pendulum(amp: 1.0, freq: 2.0, phase: 1.57, damp: 0.035), Pendulum(amp: 0.45, freq: 4.0, phase: 0, damp: 0.035)]),
    HarmonoPreset(name: "Rosette", p: [
        Pendulum(amp: 1.0, freq: 5.0, phase: 0, damp: 0.06), Pendulum(amp: 0.2, freq: 1.0, phase: 0, damp: 0.06),
        Pendulum(amp: 1.0, freq: 5.02, phase: 1.57, damp: 0.06), Pendulum(amp: 0.2, freq: 1.0, phase: 1.57, damp: 0.06)]),
    HarmonoPreset(name: "Whirl", p: [
        Pendulum(amp: 1.0, freq: 2.0, phase: 0, damp: 0.02), Pendulum(amp: 0.8, freq: 2.03, phase: 0, damp: 0.02),
        Pendulum(amp: 1.0, freq: 2.0, phase: 1.57, damp: 0.02), Pendulum(amp: 0.8, freq: 2.03, phase: 1.57, damp: 0.02)])
]

final class HarmonoModel: ObservableObject {
    @Published var pend: [Pendulum] = harmonoPresets[0].p { didSet { dirty = true } }
    @Published var swingTime = 40.0 { didSet { dirty = true } }
    @Published var lineWidth = 0.9
    @Published var glow = 3.0
    @Published var palette: Palette = .ocean
    @Published var duration = 16.0
    @Published var loop = true
    @Published var playing = true
    @Published var background = Color(red: 0.03, green: 0.035, blue: 0.05)

    let clock = Clock()
    private var dirty = true
    private var unit: [CGPoint] = []
    private var viewPts: [CGPoint] = []
    private var viewSize = CGSize.zero

    func randomize() {
        let ratios: [Double] = [1, 2, 3, 4, 5, 1.5, 2.5, 4.0 / 3, 5.0 / 3, 6]
        func pick() -> Double { ratios.randomElement()! + Double.random(in: -0.015...0.015) }
        pend = (0..<4).map { i in
            Pendulum(amp: i % 2 == 0 ? Double.random(in: 0.7...1) : Double.random(in: 0.2...0.8),
                     freq: pick(), phase: Double.random(in: 0...(2 * .pi)), damp: Double.random(in: 0.02...0.07))
        }
    }

    private func rebuild() {
        dirty = false
        viewSize = .zero
        let maxF = pend.map(\.freq).max() ?? 1
        let steps = clamp(Int(swingTime * maxF * 70), 4000, 90_000)
        var pts: [CGPoint] = []
        pts.reserveCapacity(steps + 1)
        for i in 0...steps {
            let t = swingTime * Double(i) / Double(steps)
            func osc(_ p: Pendulum) -> Double { p.amp * sin(2 * .pi * p.freq * t + p.phase) * exp(-p.damp * t) }
            pts.append(CGPoint(x: osc(pend[0]) + osc(pend[1]), y: osc(pend[2]) + osc(pend[3])))
        }
        let reach = max(pend[0].amp + pend[1].amp, pend[2].amp + pend[3].amp, 1e-6)
        unit = pts.map { CGPoint(x: $0.x / reach, y: $0.y / reach) }
    }

    private func ensureView(_ size: CGSize) {
        if dirty { rebuild() }
        guard size != viewSize else { return }
        viewSize = size
        let s = min(size.width, size.height) * 0.46
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        viewPts = unit.map { CGPoint(x: c.x + $0.x * s, y: c.y - $0.y * s) }
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, progress: Double) {
        ensureView(size)
        guard viewPts.count > 2 else { return }
        let n = max(2, Int(Double(viewPts.count) * progress))
        strokeGradient(&ctx, points: viewPts, to: n, palette: palette, width: lineWidth, chunks: 120, opacity: 0.95, glow: glow)
        if progress < 1 {
            let p = viewPts[min(n - 1, viewPts.count - 1)]
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(.white))
        }
    }
}

struct HarmonoView: View {
    @ObservedObject var m: HarmonoModel

    var body: some View {
        LabScaffold(title: "Harmonograph",
                    subtitle: "Four swinging pendulums, two moving the paper and two moving the pen, slowly lose energy. Their combined swing draws elegant decaying spirals.") {
            ZStack {
                m.background
                TimelineView(.animation) { tl in
                    let t = m.clock.advance(tl.date)
                    let p = revealProgress(t: t, duration: m.duration, loop: m.loop)
                    Canvas { ctx, size in m.draw(&ctx, size, progress: p) }
                }
            }
        } inspector: {
            Card("Presets") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 5)], spacing: 5) {
                    ForEach(harmonoPresets, id: \.name) { p in
                        Button(p.name) { m.pend = p.p; m.clock.reset() }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Button { m.randomize(); m.clock.reset() } label: { Label("Random", systemImage: "dice") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            ForEach(0..<4, id: \.self) { i in
                Card(["Paper pendulum 1 (x)", "Paper pendulum 2 (x)", "Pen pendulum 1 (y)", "Pen pendulum 2 (y)"][i]) {
                    SliderRow(title: "Size", value: Binding(get: { m.pend[i].amp }, set: { m.pend[i].amp = $0 }), range: 0...1.5)
                    SliderRow(title: "Swings per second", value: Binding(get: { m.pend[i].freq }, set: { m.pend[i].freq = $0 }), range: 0.5...8, format: "%.3f")
                    SliderRow(title: "Starting phase", value: Binding(get: { m.pend[i].phase }, set: { m.pend[i].phase = $0 }), range: 0...(2 * .pi))
                    SliderRow(title: "Friction", value: Binding(get: { m.pend[i].damp }, set: { m.pend[i].damp = $0 }), range: 0...0.2, format: "%.3f")
                }
            }
            Card("Drawing") {
                SliderRow(title: "Swing time", value: $m.swingTime, range: 5...200, format: "%.0f s", step: 1)
                SliderRow(title: "Seconds to draw", value: $m.duration, range: 2...60, format: "%.0f s", step: 1)
                ToggleRow("Loop", $m.loop)
                PlayControls(clock: m.clock, playing: $m.playing)
            }
            Card("Look") {
                SliderRow(title: "Line width", value: $m.lineWidth, range: 0.3...5)
                SliderRow(title: "Glow", value: $m.glow, range: 0...20, format: "%.0f")
                PaletteChips(selection: $m.palette)
                ColorPicker("Background", selection: $m.background).font(.callout)
            }
            ExportButton(name: "harmonograph", background: m.background) { ctx, size in
                m.draw(&ctx, size, progress: 1)
            }
        }
    }
}
