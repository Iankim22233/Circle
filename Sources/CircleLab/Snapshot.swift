import SwiftUI
import AppKit

/// `CircleLab --snapshot <dir>` renders every lab's canvas to a PNG and exits (handy for checking drawing code headlessly).
@MainActor
func runSnapshots(to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let size = CGSize(width: 1000, height: 700)

    func save<V: View>(_ name: String, background: Color, @ViewBuilder _ content: () -> V) {
        let view = ZStack { background; content() }.frame(width: size.width, height: size.height)
        let r = ImageRenderer(content: view)
        r.scale = 1
        guard let cg = r.cgImage else { print("failed \(name)"); return }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        print("wrote \(name)")
    }

    let epi = EpicyclesModel()
    save("epicycles", background: epi.background) { Canvas { c, s in epi.draw(&c, s, time: 5.5) } }
    epi.loadText(); epi.circleCount = 120; epi.showCircles = false; epi.trailLength = 1.5
    save("epicycles_text", background: epi.background) { Canvas { c, s in epi.draw(&c, s, time: 13.9) } }

    let pan = PantographModel()
    pan.cascade = 2
    pan.trace(Outlines.preset("Star"))
    // synchronous fill for the snapshot
    let pts = Outlines.preset("Heart").map { CGPoint(x: pan.pivot.x - 0.40 + $0.re * 0.21, y: pan.pivot.y - $0.im * 0.21) }
    pan.clear()
    pan.tracer = pan.clampTracer(pts[0]); pan.strokes = [pts.map { pan.clampTracer($0) }]
    pan.tracer = pan.clampTracer(pts[300])
    save("pantograph", background: pan.background) { Canvas { c, s in pan.draw(&c, s) } }

    let fr = FractalModel()
    save("fractal_koch", background: fr.background) { Canvas { c, s in fr.drawGenerator(&c, s, progress: 1) } }
    fr.loadGenPreset(genPresets[2])
    save("fractal_dragon", background: fr.background) { Canvas { c, s in fr.drawGenerator(&c, s, progress: 1) } }
    fr.mode = .ifs
    for (i, p) in fr.ifsPresets.enumerated() where [0, 3, 7].contains(i) {
        fr.loadIFS(p)
        save("ifs_\(p.name)", background: fr.background) { Canvas { c, s in fr.drawIFS(&c, s, handles: true) } }
    }
    fr.loadIFS(fr.ifsPresets[0]); fr.ifsRender = .copies; fr.copyDepth = 6
    save("ifs_copies", background: fr.background) { Canvas { c, s in fr.drawIFS(&c, s, handles: true) } }

    let sp = SpiroModel()
    save("spirograph", background: sp.background) { Canvas { c, s in sp.draw(&c, s, progress: 0.6) } }
    let ha = HarmonoModel()
    save("harmonograph", background: ha.background) { Canvas { c, s in ha.draw(&c, s, progress: 1) } }
    let ls = LSystemModel()
    save("lsystem_plant", background: ls.background) { Canvas { c, s in ls.draw(&c, s, progress: 1) } }
    ls.load(lsPresets[2]); ls.colorMode = .order
    save("lsystem_dragon", background: ls.background) { Canvas { c, s in ls.draw(&c, s, progress: 1) } }

    let jm = JuliaModel()
    let p = EscapeParams(kind: .mandelbrot, power: 2, maxIter: 300, center: CGPoint(x: -0.5, y: 0), span: 3.2, c: .zero, cycles: 1, shift: 0, palette: .rainbow, interior: packRGB(0.015, 0.015, 0.03))
    if let img = renderEscape(p, W: 1000, H: 700) { exportCG(img, "\(dir)/mandelbrot.png") }
    var pj = p; pj.kind = .julia; pj.center = .zero; pj.c = CGPoint(x: -0.8, y: 0.156); pj.palette = .ember
    if let img = renderEscape(pj, W: 1000, H: 700) { exportCG(img, "\(dir)/julia.png") }
    _ = jm
}

private func exportCG(_ cg: CGImage, _ path: String) {
    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

/// Renders the full lab UI (controls included) through an offscreen window.
@MainActor
func runUISnapshots(to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let epi = EpicyclesModel(), pan = PantographModel(), fr = FractalModel(), sp = SpiroModel()
    let ha = HarmonoModel(), ls = LSystemModel(), ju = JuliaModel()
    let pts = Outlines.preset("Star").map { CGPoint(x: pan.pivot.x - 0.40 + $0.re * 0.21, y: pan.pivot.y - $0.im * 0.21) }
    pan.strokes = [pts.map { pan.clampTracer($0) }]
    ju.viewSize = CGSize(width: 1100, height: 900)
    ju.request()
    func shot(_ name: String, _ view: some View) {
        let host = NSHostingView(rootView: view.preferredColorScheme(.dark).frame(width: 1440, height: 900))
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        win.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/ui_\(name).png"))
        print("ui \(name)")
    }
    shot("epicycles", EpicyclesView(m: epi))
    shot("pantograph", PantographView(m: pan))
    shot("fractal_gen", FractalView(m: fr))
    fr.mode = .ifs
    shot("fractal_ifs", FractalView(m: fr))
    shot("spiro", SpiroView(m: sp))
    shot("harmono", HarmonoView(m: ha))
    shot("lsystem", LSystemView(m: ls))
    shot("escape", JuliaView(m: ju))
}
