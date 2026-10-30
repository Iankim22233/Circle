import SwiftUI
import AppKit

struct Coef {
    var k: Double
    var re: Double
    var im: Double
    var amp: Double { hypot(re, im) }
}

enum CircleOrder: String, CaseIterable, Identifiable {
    case amplitude = "Biggest first", frequency = "By frequency"
    var id: String { rawValue }
}

final class EpicyclesModel: ObservableObject {
    // Outline
    @Published private(set) var source: [Cx] = []
    @Published private(set) var coefs: [Coef] = []
    @Published var outlineName = "Heart"
    @Published var text = "Circle"
    @Published var fontName = Outlines.fonts[0]
    @Published var invertImport = false

    // Drawing
    @Published var drawing = false
    @Published var drawPoints: [CGPoint] = []

    // Circles
    @Published var circleCount = 40
    @Published var order: CircleOrder = .amplitude { didSet { sortCoefs() } }
    @Published var period = 14.0
    @Published var playing = true

    // Trail
    @Published var trailLength = 0.9
    @Published var lineWidth = 3.0
    @Published var glow = 6.0
    @Published var palette: Palette = .aurora

    // Look
    @Published var showCircles = true
    @Published var showRadii = true
    @Published var circleOpacity = 0.35
    @Published var showGhost = true
    @Published var follow = false
    @Published var zoom = 4.0
    @Published var background = Color(red: 0.035, green: 0.04, blue: 0.075)

    let clock = Clock()
    private var raw: [Coef] = []

    init() { setSource(Outlines.preset("Heart")) }

    var maxCircles: Int { min(300, max(1, coefs.count - 1)) }

    func setSource(_ pts: [Cx]) {
        let samples = resampleClosed(normalized(pts), count: 1024)
        source = samples
        let n = samples.count
        var cosT = [Double](repeating: 0, count: n), sinT = cosT
        for m in 0..<n {
            let a = -2 * Double.pi * Double(m) / Double(n)
            cosT[m] = cos(a); sinT[m] = sin(a)
        }
        var out: [Coef] = []
        for k in (-(n / 2 - 1))...(n / 2) {
            var sr = 0.0, si = 0.0
            for j in 0..<n {
                let idx = (((k * j) % n) + n) % n
                let c = cosT[idx], s = sinT[idx]
                sr += samples[j].re * c - samples[j].im * s
                si += samples[j].re * s + samples[j].im * c
            }
            out.append(Coef(k: Double(k), re: sr / Double(n), im: si / Double(n)))
        }
        raw = out
        sortCoefs()
        circleCount = min(circleCount, maxCircles)
        clock.reset()
    }

    private func sortCoefs() {
        guard !raw.isEmpty else { return }
        let dc = raw.first { $0.k == 0 }!
        var rest = raw.filter { $0.k != 0 }
        switch order {
        case .amplitude:
            rest.sort { $0.amp > $1.amp }
        case .frequency:
            rest.sort { abs($0.k) != abs($1.k) ? abs($0.k) < abs($1.k) : $0.k < $1.k }
        }
        coefs = [dc] + rest
    }

    func loadPreset(_ name: String) {
        outlineName = name
        setSource(Outlines.preset(name))
    }

    func loadText() {
        outlineName = "Text"
        setSource(Outlines.text(text, fontName: fontName))
    }

    func loadImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let pts = Outlines.image(at: url, lightOnDark: invertImport) {
            outlineName = url.lastPathComponent
            setSource(pts)
        }
    }

    func finishDrawing(size: CGSize) {
        defer { drawing = false; drawPoints = [] }
        guard drawPoints.count > 8 else { return }
        setSource(drawPoints.map { Cx($0.x, -$0.y) })
        outlineName = "Your drawing"
    }

    // Position of the chain tip and every joint at normalised time (cycles).
    func chain(at t: Double, count: Int) -> [Cx] {
        var pts: [Cx] = []
        pts.reserveCapacity(count + 1)
        var p = Cx(coefs[0].re, coefs[0].im)
        pts.append(p)
        let n = min(count, coefs.count - 1)
        if n > 0 {
            for i in 1...n {
                let c = coefs[i]
                let a = 2 * Double.pi * c.k * t
                let ca = cos(a), sa = sin(a)
                p = Cx(p.re + c.re * ca - c.im * sa, p.im + c.re * sa + c.im * ca)
                pts.append(p)
            }
        }
        return pts
    }

    func tip(at t: Double, count: Int) -> Cx {
        var re = coefs[0].re, im = coefs[0].im
        let n = min(count, coefs.count - 1)
        if n > 0 {
            for i in 1...n {
                let c = coefs[i]
                let a = 2 * Double.pi * c.k * t
                let ca = cos(a), sa = sin(a)
                re += c.re * ca - c.im * sa
                im += c.re * sa + c.im * ca
            }
        }
        return Cx(re, im)
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, time: Double) {
        guard !coefs.isEmpty else { return }
        let base = min(size.width, size.height) * 0.42
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let t = time / period
        let count = circleCount
        let tipNow = tip(at: t, count: count)

        let scale = follow ? base * zoom : base
        let focus = follow ? tipNow : Cx(0, 0)
        func toView(_ z: Cx) -> CGPoint {
            CGPoint(x: center.x + (z.re - focus.re) * scale, y: center.y - (z.im - focus.im) * scale)
        }
        let px = 1.0 // line widths stay constant on screen
        let jointsAll = chain(at: t, count: count)

        // Ghost outline
        if showGhost {
            var g = Path()
            for (i, p) in source.enumerated() {
                let v = toView(p)
                if i == 0 { g.move(to: v) } else { g.addLine(to: v) }
            }
            g.closeSubpath()
            ctx.stroke(g, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1 * px, dash: [3, 5]))
        }

        // Circles and radii
        if showCircles || showRadii {
            for i in 1..<max(1, jointsAll.count) {
                let c = toView(jointsAll[i - 1])
                let e = toView(jointsAll[i])
                let r = coefs[i].amp * scale
                if showCircles && r > 0.6 {
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                    let f = Double(i) / Double(max(count, 1))
                    ctx.stroke(Path(ellipseIn: rect), with: .color(palette.color(f, opacity: circleOpacity * (r > 3 ? 1 : 0.6))), lineWidth: 1)
                }
                if showRadii && r > 0.6 {
                    var l = Path(); l.move(to: c); l.addLine(to: e)
                    ctx.stroke(l, with: .color(.white.opacity(min(0.8, circleOpacity + 0.25))), lineWidth: 1)
                }
            }
        }

        // Trail
        let samples = 900
        let span = trailLength
        var trail: [CGPoint] = []
        trail.reserveCapacity(samples + 1)
        for s in 0...samples {
            let tt = t - span * (1 - Double(s) / Double(samples))
            trail.append(toView(tip(at: tt, count: count)))
        }
        let phase = (t - span) - floor(t - span)
        _ = phase
        let chunks = 48
        for c in 0..<chunks {
            let a = c * samples / chunks, b = (c + 1) * samples / chunks
            var path = Path()
            path.move(to: trail[a])
            for i in (a + 1)...b { path.addLine(to: trail[i]) }
            let f = Double(c + 1) / Double(chunks)
            let tt = t - span * (1 - f)
            let col = palette.cyclic(tt, opacity: pow(f, 1.4))
            if glow > 0 {
                ctx.stroke(path, with: .color(palette.cyclic(tt, opacity: pow(f, 1.4) * 0.16)), style: StrokeStyle(lineWidth: lineWidth + glow, lineCap: .round, lineJoin: .round))
            }
            ctx.stroke(path, with: .color(col), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }

        // Pencil head
        let head = toView(tipNow)
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 5, y: head.y - 5, width: 10, height: 10)), with: .color(.white.opacity(0.25)))
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 2.6, y: head.y - 2.6, width: 5.2, height: 5.2)), with: .color(.white))

        // Live drawing
        if drawing && drawPoints.count > 1 {
            var d = Path()
            d.addLines(drawPoints)
            ctx.stroke(d, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}

struct EpicyclesView: View {
    @ObservedObject var m: EpicyclesModel

    var body: some View {
        LabScaffold(title: "Epicycles",
                    subtitle: "Any outline can be rebuilt by a chain of spinning circles (a Fourier series). Draw something, or pick a shape, and watch the circles redraw it.") {
            GeometryReader { geo in
                ZStack {
                    m.background
                    TimelineView(.animation) { tl in
                        let t = m.clock.advance(tl.date)
                        Canvas { ctx, size in m.draw(&ctx, size, time: t) }
                    }
                    if m.drawing {
                        Color.clear.contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { v in
                                        let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                        _ = c
                                        m.drawPoints.append(v.location)
                                    }
                                    .onEnded { _ in m.finishDrawing(size: geo.size) }
                            )
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    HintLabel(text: m.drawing ? "Drag to draw any outline, then let go" : "\(m.outlineName) · \(min(m.circleCount, m.maxCircles)) circles")
                }
            }
        } inspector: {
            Card("Outline") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 5)], spacing: 5) {
                    ForEach(Outlines.presetNames, id: \.self) { n in
                        Button(n) { m.loadPreset(n) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                Button {
                    m.drawing.toggle(); m.drawPoints = []
                } label: {
                    Label(m.drawing ? "Cancel drawing" : "Draw your own…", systemImage: "pencil.tip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Divider()
                TextField("Text to trace", text: $m.text).textFieldStyle(.roundedBorder).controlSize(.small)
                Picker("Font", selection: $m.fontName) {
                    ForEach(Outlines.fonts, id: \.self) { Text($0) }
                }
                .controlSize(.small)
                HStack {
                    Button("Trace text") { m.loadText() }
                    Button("Import image…") { m.loadImage() }
                }
                .controlSize(.small)
                ToggleRow("Image is light on dark", $m.invertImport)
            }
            Card("Circles") {
                IntSliderRow(title: "Number of circles", value: $m.circleCount, range: 1...m.maxCircles)
                Picker("Order", selection: $m.order) {
                    ForEach(CircleOrder.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.small)
                SliderRow(title: "Seconds per loop", value: $m.period, range: 2...60, format: "%.0f s", step: 1)
                PlayControls(clock: m.clock, playing: $m.playing)
            }
            Card("Pencil trail") {
                SliderRow(title: "Trail length", value: $m.trailLength, range: 0.05...1.5, format: "%.2f loops")
                SliderRow(title: "Line width", value: $m.lineWidth, range: 0.5...10)
                SliderRow(title: "Glow", value: $m.glow, range: 0...24, format: "%.0f")
                PaletteChips(selection: $m.palette)
            }
            Card("Look") {
                ToggleRow("Show circles", $m.showCircles)
                ToggleRow("Show radii", $m.showRadii)
                SliderRow(title: "Circle opacity", value: $m.circleOpacity, range: 0.05...1)
                ToggleRow("Faint original outline", $m.showGhost)
                ToggleRow("Camera follows the pencil", $m.follow)
                if m.follow { SliderRow(title: "Zoom", value: $m.zoom, range: 1...40, format: "%.1f×") }
                ColorPicker("Background", selection: $m.background).font(.callout)
            }
            ExportButton(name: "epicycles", background: m.background) { ctx, size in
                m.draw(&ctx, size, time: m.clock.t)
            }
        }
    }
}
