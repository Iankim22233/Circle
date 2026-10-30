import SwiftUI

enum Lab: String, CaseIterable, Identifiable {
    case epicycles = "Epicycles"
    case pantograph = "Pantograph"
    case fractal = "Fractal Maker"
    case spirograph = "Spirograph"
    case harmonograph = "Harmonograph"
    case lsystem = "L‑Systems"
    case escape = "Escape Fractals"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .epicycles: return "circle.circle"
        case .pantograph: return "arrow.down.right.and.arrow.up.left"
        case .fractal: return "triangle"
        case .spirograph: return "gearshape.2"
        case .harmonograph: return "waveform.path"
        case .lsystem: return "leaf"
        case .escape: return "sparkles"
        }
    }

    var blurb: String {
        switch self {
        case .epicycles: return "Redraw any outline with circles"
        case .pantograph: return "A linkage that shrinks drawings"
        case .fractal: return "Design your own fractal"
        case .spirograph: return "Rolling gears and pens"
        case .harmonograph: return "Decaying pendulum art"
        case .lsystem: return "Grow plants from rules"
        case .escape: return "Mandelbrot, Julia & friends"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--ui-snapshot"), i + 1 < CommandLine.arguments.count {
            runUISnapshots(to: CommandLine.arguments[i + 1])
            NSApp.terminate(nil)
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            runSnapshots(to: CommandLine.arguments[i + 1])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct CircleLabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Circle Lab") {
            RootView()
                .frame(minWidth: 1100, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 900)
    }
}

struct RootView: View {
    @State private var lab: Lab = .epicycles
    @StateObject private var epicycles = EpicyclesModel()
    @StateObject private var pantograph = PantographModel()
    @StateObject private var fractal = FractalModel()
    @StateObject private var spiro = SpiroModel()
    @StateObject private var harmono = HarmonoModel()
    @StateObject private var lsystem = LSystemModel()
    @StateObject private var escape = JuliaModel()

    var body: some View {
        NavigationSplitView {
            List(Lab.allCases, selection: $lab) { l in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(l.rawValue).font(.body)
                        Text(l.blurb).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: l.icon)
                }
                .padding(.vertical, 3)
                .tag(l)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 280)
        } detail: {
            switch lab {
            case .epicycles: EpicyclesView(m: epicycles)
            case .pantograph: PantographView(m: pantograph)
            case .fractal: FractalView(m: fractal)
            case .spirograph: SpiroView(m: spiro)
            case .harmonograph: HarmonoView(m: harmono)
            case .lsystem: LSystemView(m: lsystem)
            case .escape: JuliaView(m: escape)
            }
        }
        .navigationTitle(lab.rawValue)
    }
}
