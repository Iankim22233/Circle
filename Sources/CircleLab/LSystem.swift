import SwiftUI

struct LSPreset {
    var name: String
    var axiom: String
    var rules: [String]
    var angle: Double
    var iterations: Int
    var start: Double
}

let lsPresets: [LSPreset] = [
    LSPreset(name: "Snowflake", axiom: "F--F--F", rules: ["F=F+F--F+F"], angle: 60, iterations: 4, start: 0),
    LSPreset(name: "Sierpinski", axiom: "F-G-G", rules: ["F=F-G+F+G-F", "G=GG"], angle: 120, iterations: 6, start: 0),
    LSPreset(name: "Dragon", axiom: "FX", rules: ["X=X+YF+", "Y=-FX-Y"], angle: 90, iterations: 12, start: 0),
    LSPreset(name: "Hilbert", axiom: "A", rules: ["A=-BF+AFA+FB-", "B=+AF-BFB-FA+"], angle: 90, iterations: 6, start: 0),
    LSPreset(name: "Plant", axiom: "X", rules: ["X=F+[[X]-X]-F[-FX]+X", "F=FF"], angle: 25, iterations: 6, start: 65),
    LSPreset(name: "Tree", axiom: "F", rules: ["F=FF-[-F+F+F]+[+F-F-F]"], angle: 22.5, iterations: 4, start: 90),
    LSPreset(name: "Gosper", axiom: "A", rules: ["A=A-B--B+A++AA+B-", "B=+A-BB--B-A++A+B"], angle: 60, iterations: 4, start: 0),
    LSPreset(name: "Crystal", axiom: "F+F+F+F", rules: ["F=FF+F++F+F"], angle: 90, iterations: 4, start: 0),
    LSPreset(name: "Lévy", axiom: "F", rules: ["F=+F--F+"], angle: 45, iterations: 12, start: 0)
]

enum LSColorMode: String, CaseIterable, Identifiable {
    case order = "Along the path", depth = "By branch depth"
    var id: String { rawValue }
}

struct Seg {
    var x0: Float, y0: Float, x1: Float, y1: Float
    var depth: UInt16
}

final class LSystemModel: ObservableObject {
    @Published var axiom = "X" { didSet { dirty = true } }
    @Published var rules: [String] = ["X=F+[[X]-X]-F[-FX]+X", "F=FF", "", ""] { didSet { dirty = true } }
    @Published var angle = 25.0 { didSet { dirty = true } }
    @Published var iterations = 6 { didSet { dirty = true } }
    @Published var startAngle = 65.0 { didSet { dirty = true } }
    @Published var jitter = 0.0 { didSet { dirty = true } }
    @Published var seed = 1.0 { didSet { dirty = true } }

    @Published var colorMode: LSColorMode = .depth { didSet { fullBuckets = nil } }
    @Published var palette: Palette = .ember { didSet { fullBuckets = nil } }
    @Published var lineWidth = 1.2 { didSet { fullBuckets = nil } }
    @Published var taper = 0.85 { didSet { fullBuckets = nil } }
    @Published var animate = false
    @Published var duration = 8.0
    @Published var loop = true
    @Published var playing = true
    @Published var background = Color(red: 0.035, green: 0.04, blue: 0.055)

    let clock = Clock()
    private var dirty = true
    private(set) var segs: [Seg] = []
    private(set) var truncated = false
    private(set) var maxDepth = 0
    private var bounds = CGRect.zero
    private var cacheSize = CGSize.zero
    private var fullBuckets: [(Path, Color, Double)]?

    private let maxSegs = 250_000
    private let maxSymbols = 2_500_000

    init() { load(lsPresets[4]) }

    func load(_ p: LSPreset) {
        axiom = p.axiom
        var r = p.rules
        while r.count < 4 { r.append("") }
        rules = r
        angle = p.angle
        iterations = p.iterations
        startAngle = p.start
        clock.reset()
    }

    private func expand() -> [UInt8] {
        var table = [UInt8: [UInt8]]()
        for line in rules {
            let parts = line.replacingOccurrences(of: " ", with: "").split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let k = parts[0].utf8.first, parts[0].utf8.count == 1 else { continue }
            table[k] = Array(parts[1].utf8)
        }
        var cur = Array(axiom.replacingOccurrences(of: " ", with: "").utf8)
        truncated = false
        for _ in 0..<iterations {
            var next: [UInt8] = []
            next.reserveCapacity(cur.count * 3)
            for ch in cur {
                if let rep = table[ch] { next.append(contentsOf: rep) } else { next.append(ch) }
                if next.count > maxSymbols { break }
            }
            if next.count > maxSymbols { truncated = true; break }
            cur = next
        }
        return cur
    }

    private func rebuild() {
        dirty = false
        fullBuckets = nil
        cacheSize = .zero
        let symbols = expand()
        var out: [Seg] = []
        out.reserveCapacity(min(symbols.count, maxSegs))
        var rng = SplitMix64(seed: UInt64(seed * 1000) &+ 17)
        var x: Float = 0, y: Float = 0
        var heading = startAngle * .pi / 180
        let turn = angle * .pi / 180
        var stack: [(Float, Float, Double)] = []
        var depth = 0
        var deepest = 0
        var minX: Float = 0, maxX: Float = 0, minY: Float = 0, maxY: Float = 0
        func jit() -> Double { jitter > 0 ? rng.range(-1, 1) * jitter * .pi / 180 : 0 }
        for s in symbols {
            switch s {
            case 70, 71, 65, 66: // F G A B draw
                let nx = x + Float(cos(heading)), ny = y + Float(sin(heading))
                out.append(Seg(x0: x, y0: y, x1: nx, y1: ny, depth: UInt16(min(depth, 60000))))
                x = nx; y = ny
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            case 102: // f move
                x += Float(cos(heading)); y += Float(sin(heading))
            case 43: heading += turn + jit()
            case 45: heading -= turn + jit()
            case 124: heading += .pi
            case 91:
                stack.append((x, y, heading)); depth += 1; deepest = max(deepest, depth)
            case 93:
                if let st = stack.popLast() { x = st.0; y = st.1; heading = st.2; depth -= 1 }
            default: break
            }
            if out.count >= maxSegs { truncated = true; break }
        }
        segs = out
        maxDepth = deepest
        bounds = CGRect(x: Double(minX), y: Double(minY), width: Double(max(maxX - minX, 1e-6)), height: Double(max(maxY - minY, 1e-6)))
    }

    private func buckets(upTo n: Int, size: CGSize) -> [(Path, Color, Double)] {
        let margin = 40.0
        let s = min((size.width - 2 * margin) / bounds.width, (size.height - 2 * margin) / bounds.height)
        let ox = size.width / 2 - (bounds.midX) * s
        let oy = size.height / 2 + (bounds.midY) * s
        let total = max(segs.count, 1)
        let count = colorMode == .order ? 64 : maxDepth + 1
        var paths = [Path](repeating: Path(), count: count)
        for i in 0..<n {
            let sg = segs[i]
            let b = colorMode == .order ? min(63, i * 64 / total) : min(Int(sg.depth), count - 1)
            paths[b].move(to: CGPoint(x: ox + Double(sg.x0) * s, y: oy - Double(sg.y0) * s))
            paths[b].addLine(to: CGPoint(x: ox + Double(sg.x1) * s, y: oy - Double(sg.y1) * s))
        }
        var result: [(Path, Color, Double)] = []
        for b in 0..<count {
            let f = Double(b) / Double(max(count - 1, 1))
            let w = colorMode == .order ? lineWidth : max(0.3, lineWidth * pow(taper, Double(b)))
            result.append((paths[b], palette.color(f), w))
        }
        return result
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, progress: Double) {
        if dirty { rebuild() }
        guard !segs.isEmpty else { return }
        let n = max(1, Int(Double(segs.count) * progress))
        let list: [(Path, Color, Double)]
        if n == segs.count {
            if fullBuckets == nil || cacheSize != size {
                fullBuckets = buckets(upTo: segs.count, size: size)
                cacheSize = size
            }
            list = fullBuckets!
        } else {
            list = buckets(upTo: n, size: size)
        }
        for (path, color, w) in list {
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
    }

    var summary: String {
        "\(segs.count) lines" + (truncated ? " (limited – lower the iterations)" : "")
    }
}

struct LSystemView: View {
    @ObservedObject var m: LSystemModel

    var body: some View {
        LabScaffold(title: "L‑Systems",
                    subtitle: "Plants and curves grown from text. A starting word is rewritten by your rules again and again; a turtle then walks the result, drawing lines.") {
            ZStack {
                m.background
                TimelineView(.animation(paused: !m.animate)) { tl in
                    let t = m.clock.advance(tl.date)
                    let p = m.animate ? revealProgress(t: t, duration: m.duration, loop: m.loop) : 1
                    Canvas { ctx, size in m.draw(&ctx, size, progress: p) }
                }
            }
            .overlay(alignment: .bottomLeading) { HintLabel(text: m.summary) }
        } inspector: {
            Card("Presets") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 5)], spacing: 5) {
                    ForEach(lsPresets, id: \.name) { p in
                        Button(p.name) { m.load(p) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            Card("Rules") {
                HStack {
                    Text("Start").font(.callout).frame(width: 38, alignment: .leading)
                    TextField("Axiom", text: $m.axiom).textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
                }
                ForEach(0..<4, id: \.self) { i in
                    HStack {
                        Text("Rule \(i + 1)").font(.callout).frame(width: 38, alignment: .leading)
                        TextField("e.g. F=F+F-F", text: Binding(get: { m.rules[i] }, set: { m.rules[i] = $0 }))
                            .textFieldStyle(.roundedBorder).font(.system(.callout, design: .monospaced))
                    }
                }
                Text("F G A B draw · f moves · + − turn · [ ] branch · | reverse. Other letters are just placeholders for rules.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Card("Turtle") {
                IntSliderRow(title: "Iterations", value: $m.iterations, range: 0...14)
                SliderRow(title: "Turn angle", value: $m.angle, range: 1...180, format: "%.1f°")
                SliderRow(title: "Starting direction", value: $m.startAngle, range: 0...360, format: "%.0f°")
                SliderRow(title: "Wobble", value: $m.jitter, range: 0...30, format: "%.1f°")
                if m.jitter > 0 { SliderRow(title: "Wobble pattern", value: $m.seed, range: 1...50, format: "%.0f", step: 1) }
            }
            Card("Look") {
                Picker("Colour", selection: $m.colorMode) {
                    ForEach(LSColorMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).controlSize(.small)
                SliderRow(title: "Line width", value: $m.lineWidth, range: 0.3...8)
                if m.colorMode == .depth { SliderRow(title: "Thinner per branch", value: $m.taper, range: 0.5...1) }
                PaletteChips(selection: $m.palette)
                ColorPicker("Background", selection: $m.background).font(.callout)
                ToggleRow("Grow animation", $m.animate)
                if m.animate {
                    SliderRow(title: "Seconds to grow", value: $m.duration, range: 1...30, format: "%.0f s", step: 1)
                    ToggleRow("Loop", $m.loop)
                    PlayControls(clock: m.clock, playing: $m.playing)
                }
            }
            ExportButton(name: "lsystem", background: m.background) { ctx, size in
                m.draw(&ctx, size, progress: 1)
            }
        }
    }
}
