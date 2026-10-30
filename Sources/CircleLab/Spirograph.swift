import SwiftUI

func revealProgress(t: Double, duration: Double, loop: Bool) -> Double {
    if loop {
        let cycle = duration + 2.5
        return min(1, t.truncatingRemainder(dividingBy: cycle) / duration)
    }
    return min(1, t / duration)
}

enum GearMode: String, CaseIterable, Identifiable {
    case inside = "Inside the ring", outside = "Around the ring"
    var id: String { rawValue }
}

final class SpiroModel: ObservableObject {
    @Published var ring = 96 { didSet { dirty = true; if gearMode == .inside && wheel >= ring { wheel = ring - 1 } } }
    @Published var wheel = 35 { didSet { dirty = true } }
    @Published var penOffset = 0.8 { didSet { dirty = true } }
    @Published var gearMode: GearMode = .inside { didSet { dirty = true; if gearMode == .inside && wheel >= ring { wheel = ring - 1 } } }

    @Published var layers = 3
    @Published var twist = 20.0
    @Published var lineWidth = 1.2
    @Published var glow = 4.0
    @Published var palette: Palette = .aurora
    @Published var duration = 14.0
    @Published var loop = true
    @Published var showMechanism = true
    @Published var playing = true
    @Published var background = Color(red: 0.03, green: 0.03, blue: 0.055)

    let clock = Clock()
    private var dirty = true
    private var unit: [CGPoint] = []      // curve scaled so the farthest point is at radius 1 (y up)
    private var unitMax = 1.0
    private var viewPts: [CGPoint] = []
    private var viewSize = CGSize.zero
    private(set) var turns = 1

    var maxWheel: Int { gearMode == .inside ? max(2, ring - 1) : 150 }

    private func rebuild() {
        dirty = false
        viewSize = .zero
        let R = Double(ring), r = Double(wheel)
        let g = gcd(ring, wheel)
        turns = max(1, wheel / g)
        let d = penOffset * r
        let inside = gearMode == .inside
        let steps = clamp(turns * 520, 2400, 90_000)
        let total = 2 * Double.pi * Double(turns)
        var pts: [CGPoint] = []
        pts.reserveCapacity(steps + 1)
        var far = 1e-9
        for i in 0...steps {
            let t = total * Double(i) / Double(steps)
            let x: Double, y: Double
            if inside {
                let k = (R - r) / r
                x = (R - r) * cos(t) + d * cos(k * t)
                y = (R - r) * sin(t) - d * sin(k * t)
            } else {
                let k = (R + r) / r
                x = (R + r) * cos(t) - d * cos(k * t)
                y = (R + r) * sin(t) - d * sin(k * t)
            }
            far = max(far, hypot(x, y))
            pts.append(CGPoint(x: x, y: y))
        }
        unitMax = far
        unit = pts.map { CGPoint(x: $0.x / far, y: $0.y / far) }
    }

    private func ensureView(_ size: CGSize) {
        if dirty { rebuild() }
        guard size != viewSize else { return }
        viewSize = size
        let s = min(size.width, size.height) * 0.44
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        viewPts = unit.map { CGPoint(x: c.x + $0.x * s, y: c.y - $0.y * s) }
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, progress: Double) {
        ensureView(size)
        guard viewPts.count > 2 else { return }
        let s = min(size.width, size.height) * 0.44
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let n = max(2, Int(Double(viewPts.count) * progress))
        let opacity = layers > 6 ? 0.7 : 0.95
        for k in 0..<layers {
            var lc = ctx
            lc.translateBy(x: c.x, y: c.y)
            lc.rotate(by: .degrees(twist * Double(k)))
            lc.translateBy(x: -c.x, y: -c.y)
            strokeGradient(&lc, points: viewPts, to: n, palette: palette, width: lineWidth, chunks: 72,
                           opacity: opacity, phase: Double(k) / Double(max(layers, 1)) * 0.6, cyclic: true, glow: glow)
        }

        guard showMechanism, progress < 1 else { return }
        // Mechanism for the first layer
        let R = Double(ring), r = Double(wheel)
        let inside = gearMode == .inside
        let u = s / unitMax
        let t = 2 * Double.pi * Double(turns) * progress
        let cr = inside ? (R - r) : (R + r)
        let wc = CGPoint(x: c.x + cr * cos(t) * u, y: c.y - cr * sin(t) * u)
        let pen = viewPts[min(n - 1, viewPts.count - 1)]
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - R * u, y: c.y - R * u, width: 2 * R * u, height: 2 * R * u)),
                   with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
        ctx.stroke(Path(ellipseIn: CGRect(x: wc.x - r * u, y: wc.y - r * u, width: 2 * r * u, height: 2 * r * u)),
                   with: .color(.white.opacity(0.5)), lineWidth: 1.4)
        var arm = Path(); arm.move(to: wc); arm.addLine(to: pen)
        ctx.stroke(arm, with: .color(.white.opacity(0.6)), lineWidth: 1)
        ctx.fill(Path(ellipseIn: CGRect(x: wc.x - 2.5, y: wc.y - 2.5, width: 5, height: 5)), with: .color(.white.opacity(0.7)))
        ctx.fill(Path(ellipseIn: CGRect(x: pen.x - 4, y: pen.y - 4, width: 8, height: 8)), with: .color(.white))
    }
}

struct SpiroView: View {
    @ObservedObject var m: SpiroModel

    var body: some View {
        LabScaffold(title: "Spirograph",
                    subtitle: "A toothed wheel rolls around a ring with a pen stuck through one of its holes. Change the tooth counts and the hole to get every flower, star and rosette.") {
            ZStack {
                m.background
                TimelineView(.animation) { tl in
                    let t = m.clock.advance(tl.date)
                    let p = revealProgress(t: t, duration: m.duration, loop: m.loop)
                    Canvas { ctx, size in m.draw(&ctx, size, progress: p) }
                }
            }
            .overlay(alignment: .bottomLeading) {
                HintLabel(text: "Ring \(m.ring) · wheel \(m.wheel) · closes after \(m.turns) turn\(m.turns == 1 ? "" : "s")")
            }
        } inspector: {
            Card("Gears") {
                Picker("Wheel rolls", selection: $m.gearMode) {
                    ForEach(GearMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.small)
                IntSliderRow(title: "Ring teeth", value: $m.ring, range: 20...200)
                IntSliderRow(title: "Wheel teeth", value: $m.wheel, range: 3...m.maxWheel)
                SliderRow(title: "Pen hole (distance from centre)", value: $m.penOffset, range: 0.05...2.0)
            }
            Card("Layers") {
                IntSliderRow(title: "Copies", value: $m.layers, range: 1...16)
                SliderRow(title: "Twist between copies", value: $m.twist, range: 0...180, format: "%.0f°")
            }
            Card("Drawing") {
                SliderRow(title: "Seconds to draw", value: $m.duration, range: 2...60, format: "%.0f s", step: 1)
                ToggleRow("Loop", $m.loop)
                ToggleRow("Show the gears", $m.showMechanism)
                PlayControls(clock: m.clock, playing: $m.playing)
            }
            Card("Look") {
                SliderRow(title: "Line width", value: $m.lineWidth, range: 0.4...6)
                SliderRow(title: "Glow", value: $m.glow, range: 0...20, format: "%.0f")
                PaletteChips(selection: $m.palette)
                ColorPicker("Background", selection: $m.background).font(.callout)
            }
            ExportButton(name: "spirograph", background: m.background) { ctx, size in
                m.draw(&ctx, size, progress: 1)
            }
        }
    }
}
