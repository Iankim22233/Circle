import SwiftUI

/// Geometry is stored in units of min(canvas width, height), origin at the canvas centre, y pointing down.
final class PantographModel: ObservableObject {
    @Published var ratio = 0.4
    @Published var pivot = CGPoint(x: 0.30, y: 0.06)
    @Published var barA = 0.34
    @Published var barB = 0.34
    @Published var elbowFlip = false
    @Published var cascade = 1
    @Published var showLinkage = true
    @Published var showOriginal = true
    @Published var showReach = false
    @Published var palette: Palette = .ember
    @Published var lineWidth = 2.5
    @Published var background = Color(red: 0.06, green: 0.055, blue: 0.075)

    @Published var strokes: [[CGPoint]] = []
    @Published var tracer = CGPoint(x: -0.12, y: 0.06)
    @Published var penDown = false
    @Published var text = "Hi"
    @Published var traceSpeed = 4.0
    @Published var tracing = false

    private var task: Task<Void, Never>?

    // MARK: Kinematics

    func clampTracer(_ m: CGPoint) -> CGPoint {
        let v = m - pivot
        let d = v.length
        let dmax = (barA + barB) * 0.999
        let dmin = abs(barA - barB) + 0.002
        guard d > 1e-9 else { return pivot + CGPoint(x: dmin, y: 0) }
        let c = clamp(d, dmin, dmax)
        return pivot + v * (c / d)
    }

    struct Linkage { var J: CGPoint; var Q: CGPoint; var R: CGPoint; var P: CGPoint }

    func linkage(for T: CGPoint) -> Linkage {
        let O = pivot
        let v = T - O
        let d = max(v.length, 1e-9)
        let a = (barA * barA - barB * barB + d * d) / (2 * d)
        let h = sqrt(max(0, barA * barA - a * a))
        let dir = v * (1 / d)
        let perp = CGPoint(x: -dir.y, y: dir.x) * (elbowFlip ? -1 : 1)
        let J = O + dir * a + perp * h
        let P = O + v * ratio
        let Q = O + (J - O) * ratio
        let R = J + (T - J) * ratio
        return Linkage(J: J, Q: Q, R: R, P: P)
    }

    func pencil(_ T: CGPoint, scale: Double? = nil) -> CGPoint {
        pivot + (T - pivot) * (scale ?? ratio)
    }

    // MARK: Pen

    func beginStroke() {
        penDown = true
        strokes.append([tracer])
    }

    func drag(to m: CGPoint) {
        tracer = clampTracer(m)
        guard penDown, !strokes.isEmpty else { return }
        if let last = strokes[strokes.count - 1].last, last.distance(to: tracer) < 0.0015 { return }
        strokes[strokes.count - 1].append(tracer)
    }

    func hover(to m: CGPoint) {
        if !penDown && !tracing { tracer = clampTracer(m) }
    }

    func endStroke() { penDown = false }

    func clear() { task?.cancel(); tracing = false; penDown = false; strokes = [] }
    func undo() { if !strokes.isEmpty { strokes.removeLast() } }

    // MARK: Demo tracing

    func trace(_ shape: [Cx]) {
        task?.cancel()
        penDown = false
        let center = CGPoint(x: pivot.x - 0.40, y: pivot.y)
        let pts = shape.map { CGPoint(x: center.x + $0.re * 0.21, y: center.y - $0.im * 0.21) }
        guard let first = pts.first else { return }
        tracing = true
        tracer = clampTracer(first)
        strokes.append([tracer])
        let step = max(1, Int(traceSpeed))
        task = Task { @MainActor [weak self] in
            var i = 0
            while let self, i < pts.count, !Task.isCancelled {
                for _ in 0..<step where i < pts.count {
                    self.tracer = self.clampTracer(pts[i])
                    self.strokes[self.strokes.count - 1].append(self.tracer)
                    i += 1
                }
                try? await Task.sleep(nanoseconds: 7_000_000)
            }
            guard let self, !Task.isCancelled, !self.strokes.isEmpty else { return }
            self.tracer = self.clampTracer(first)
            self.strokes[self.strokes.count - 1].append(self.tracer)
            self.tracing = false
        }
    }

    func traceShape(_ name: String) { trace(Outlines.preset(name)) }
    func traceText() { trace(Outlines.text(text, fontName: "HelveticaNeue-Bold")) }

    // MARK: Drawing

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let s = min(size.width, size.height)
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        func V(_ u: CGPoint) -> CGPoint { CGPoint(x: c.x + u.x * s, y: c.y + u.y * s) }
        let O = V(pivot)

        // Paper: faint dot grid
        let grid = 40.0
        var dots = Path()
        var gx = (size.width / 2).truncatingRemainder(dividingBy: grid)
        while gx < size.width {
            var gy = (size.height / 2).truncatingRemainder(dividingBy: grid)
            while gy < size.height {
                dots.addEllipse(in: CGRect(x: gx - 0.8, y: gy - 0.8, width: 1.6, height: 1.6))
                gy += grid
            }
            gx += grid
        }
        ctx.fill(dots, with: .color(.white.opacity(0.07)))

        if showReach {
            let r = (barA + barB) * s
            ctx.stroke(Path(ellipseIn: CGRect(x: O.x - r, y: O.y - r, width: 2 * r, height: 2 * r)),
                       with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        }

        // Original strokes (what the tracer follows)
        if showOriginal {
            for st in strokes where st.count > 1 {
                var p = Path()
                p.addLines(st.map(V))
                ctx.stroke(p, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: max(1, lineWidth * 0.7), lineCap: .round, lineJoin: .round, dash: [1, 4]))
            }
        }

        // Reduced copies
        for k in stride(from: cascade, through: 1, by: -1) {
            let sc = pow(ratio, Double(k))
            for st in strokes where st.count > 1 {
                let pts = st.map { V(pencil($0, scale: sc)) }
                strokeGradient(&ctx, points: pts, palette: palette, width: lineWidth, chunks: 40,
                               opacity: k == 1 ? 1 : 0.75, glow: k == 1 ? 6 : 0)
            }
        }

        // Linkage
        let T = V(tracer)
        let L = linkage(for: tracer)
        let J = V(L.J), Q = V(L.Q), R = V(L.R), P = V(L.P)
        if showLinkage {
            func bar(_ a: CGPoint, _ b: CGPoint, _ w: Double, _ col: Color) {
                var p = Path(); p.move(to: a); p.addLine(to: b)
                ctx.stroke(p, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: w + 3, lineCap: .round))
                ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            let brass = Color(red: 0.86, green: 0.70, blue: 0.38)
            let steel = Color(red: 0.62, green: 0.70, blue: 0.82)
            bar(Q, P, 5, steel)
            bar(R, P, 5, steel)
            bar(O, J, 8, brass)
            bar(J, T, 8, brass)
            func rivet(_ p: CGPoint, _ r: Double) {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.2, green: 0.2, blue: 0.24)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.55, y: p.y - r * 0.55, width: r * 1.1, height: r * 1.1)), with: .color(.white.opacity(0.8)))
            }
            rivet(J, 6); rivet(Q, 4.5); rivet(R, 4.5)

            // Pivot pin
            ctx.fill(Path(ellipseIn: CGRect(x: O.x - 13, y: O.y - 13, width: 26, height: 26)), with: .color(.white.opacity(0.12)))
            ctx.stroke(Path(ellipseIn: CGRect(x: O.x - 13, y: O.y - 13, width: 26, height: 26)), with: .color(.white.opacity(0.6)), lineWidth: 1.5)
            rivet(O, 7)

            // Tracer stylus
            ctx.stroke(Path(ellipseIn: CGRect(x: T.x - 11, y: T.y - 11, width: 22, height: 22)), with: .color(.white.opacity(penDown || tracing ? 1 : 0.7)), lineWidth: 2)
            var cross = Path()
            cross.move(to: CGPoint(x: T.x - 17, y: T.y)); cross.addLine(to: CGPoint(x: T.x + 17, y: T.y))
            cross.move(to: CGPoint(x: T.x, y: T.y - 17)); cross.addLine(to: CGPoint(x: T.x, y: T.y + 17))
            ctx.stroke(cross, with: .color(.white.opacity(0.6)), lineWidth: 1)

            // Pencil
            let pc = palette.color(0.15)
            ctx.fill(Path(ellipseIn: CGRect(x: P.x - 9, y: P.y - 9, width: 18, height: 18)), with: .color(pc.opacity(0.28)))
            ctx.fill(Path(ellipseIn: CGRect(x: P.x - 4.5, y: P.y - 4.5, width: 9, height: 9)), with: .color(pc))
            ctx.stroke(Path(ellipseIn: CGRect(x: P.x - 4.5, y: P.y - 4.5, width: 9, height: 9)), with: .color(.white), lineWidth: 1.2)

            func tag(_ s: String, _ at: CGPoint, _ dx: Double, _ dy: Double) {
                ctx.draw(Text(s).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(Color.white.opacity(0.6)),
                         at: CGPoint(x: at.x + dx, y: at.y + dy), anchor: .topLeading)
            }
            tag("TRACER", T, 16, 8)
            tag("PENCIL", P, 12, 10)
            tag("PIVOT", O, 16, 12)
        }
    }
}

struct PantographView: View {
    @ObservedObject var m: PantographModel

    private func canvasArea(_ size: CGSize) -> some View {
        let s = min(size.width, size.height)
        let toUnit = { (p: CGPoint) -> CGPoint in
            CGPoint(x: (p.x - size.width / 2) / s, y: (p.y - size.height / 2) / s)
        }
        return ZStack {
            m.background
            Canvas { ctx, sz in m.draw(&ctx, sz) }
            Color.clear.contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let p) = phase { m.hover(to: toUnit(p)) }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if !m.penDown { m.beginStroke() }
                            m.drag(to: toUnit(v.location))
                        }
                        .onEnded { _ in m.endStroke() }
                )
        }
        .overlay(alignment: .bottomLeading) {
            HintLabel(text: "Hover to move the arm · click and drag to draw · the arm can only reach so far")
        }
    }

    var body: some View {
        LabScaffold(title: "Pantograph",
                    subtitle: "A real parallelogram linkage. Guide the tracer over a drawing and the pencil repeats every move at a fraction of the size, shrinking toward the pivot.") {
            GeometryReader { geo in canvasArea(geo.size) }
        } inspector: {
            Card("Mechanism") {
                SliderRow(title: "Reduction ratio", value: $m.ratio, range: 0.05...0.95, format: "%.2f ×")
                SliderRow(title: "Arm A length", value: $m.barA, range: 0.15...0.55)
                SliderRow(title: "Arm B length", value: $m.barB, range: 0.15...0.55)
                SliderRow(title: "Pivot X", value: Binding(get: { m.pivot.x }, set: { m.pivot.x = $0 }), range: -0.6...0.6)
                SliderRow(title: "Pivot Y", value: Binding(get: { m.pivot.y }, set: { m.pivot.y = $0 }), range: -0.45...0.45)
                ToggleRow("Flip elbow", $m.elbowFlip)
                IntSliderRow(title: "Cascade (repeated reductions)", value: $m.cascade, range: 1...6)
            }
            Card("Auto-trace") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 5)], spacing: 5) {
                    ForEach(Outlines.presetNames, id: \.self) { n in
                        Button(n) { m.traceShape(n) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                HStack {
                    TextField("Text", text: $m.text).textFieldStyle(.roundedBorder)
                    Button("Trace") { m.traceText() }
                }
                .controlSize(.small)
                SliderRow(title: "Tracing speed", value: $m.traceSpeed, range: 1...16, format: "%.0f", step: 1)
                HStack {
                    Button { m.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                    Button { m.clear() } label: { Label("Clear paper", systemImage: "trash") }
                }
                .controlSize(.small)
            }
            Card("Look") {
                ToggleRow("Show linkage", $m.showLinkage)
                ToggleRow("Show original (tracing) lines", $m.showOriginal)
                ToggleRow("Show reach circle", $m.showReach)
                SliderRow(title: "Line width", value: $m.lineWidth, range: 0.5...8)
                PaletteChips(selection: $m.palette)
                ColorPicker("Background", selection: $m.background).font(.callout)
            }
            ExportButton(name: "pantograph", background: m.background) { ctx, size in
                m.draw(&ctx, size)
            }
        }
    }
}
