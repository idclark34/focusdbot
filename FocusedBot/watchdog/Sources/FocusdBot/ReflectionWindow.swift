import SwiftUI
import AppKit

struct AppSlice: Identifiable {
    let id = UUID()
    let name: String
    let seconds: Int
    let color: Color
}

final class ReflectionWindowController {
    private let panel: NSPanel

    init(model: BotModel, slices: [AppSlice]) {
        let size = NSSize(width: 280, height: 360)
        self.panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .nonactivatingPanel],
                              backing: .buffered,
                              defer: false)
        panel.level = .floating
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.title = "Session Summary"

        let root = ReflectionView(slices: slices) { [weak panel] in
            panel?.orderOut(nil)
        }.environmentObject(model)
        let host = NSHostingView(rootView: root)
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
    }

    func show() { panel.makeKeyAndOrderFront(nil) }
}

struct ReflectionView: View {
    let slices: [AppSlice]
    let close: () -> Void
    @State private var note: String = ""
    @EnvironmentObject var model: BotModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Great work! 🍅").font(.title2.bold())

            PieChart(slices: slices)
                .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(slices) { s in
                    HStack {
                        Circle().fill(s.color).frame(width: 10, height: 10)
                        Text("\(s.name): \(s.seconds/60)m")
                            .font(.caption)
                    }
                }
            }

            TextField("What did you accomplish?", text: $note)
                .textFieldStyle(.roundedBorder)
                .padding(.top, 8)

            Button("OK") {
                if !note.trimmingCharacters(in: .whitespaces).isEmpty {
                    model.sessionSummaries.insert(note, at: 0)
                    if model.sessionSummaries.count > 10 { model.sessionSummaries.removeLast() }
                }
                close()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }
}

struct PieChart: View {
    let slices: [AppSlice]
    var total: Double { Double(slices.reduce(0){$0+$1.seconds}) }

    struct Segment: Identifiable { let id = UUID(); let start: Double; let end: Double; let color: Color }

    private var segments: [Segment] {
        var start: Double = 0
        var segs: [Segment] = []
        for s in slices {
            let end = start + Double(s.seconds)/total
            segs.append(Segment(start: start, end: end, color: s.color))
            start = end
        }
        return segs
    }

    var body: some View {
        ZStack {
            ForEach(segments) { seg in
                PieSlice(start: seg.start, end: seg.end)
                    .fill(seg.color)
            }
        }
    }
}

struct PieSlice: Shape {
    let start: Double // 0-1
    let end: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: center)
        p.addArc(center: center, radius: rect.width/2, startAngle: .degrees(start*360-90), endAngle: .degrees(end*360-90), clockwise: false)
        p.closeSubpath()
        return p
    }
} 