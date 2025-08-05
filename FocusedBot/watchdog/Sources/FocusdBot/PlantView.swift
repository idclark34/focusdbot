import SwiftUI

struct PlantView: View {
    var state: BotModel.PomodoroState
    var progress: Double        // 0‒1 growth
    var hue: Double             // not used now but kept for future

    private let potWidth: CGFloat = 90
    private let potHeight: CGFloat = 60
    private let stemMax: CGFloat = 80

    private var potColor: Color { .brown }
    private var rimColor: Color { .brown.darker(by: 0.1) }
    private var stemColor: Color { state == .distracted ? Color.brown.opacity(0.7) : .green }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {               // Stem + leaves + flower area (fixed height)
                stem
                leaves
                flower
            }
            .frame(height: stemMax)

            pot
        }
        .frame(width: potWidth, height: potHeight + stemMax, alignment: .bottom)
    }

    // MARK: Components
    private var pot: some View {
        ZStack(alignment: .top) {
            PotShape()
                .fill(potColor)
                .frame(width: potWidth, height: potHeight)
            RoundedRectangle(cornerRadius: 6)
                .fill(rimColor)
                .frame(width: potWidth, height: 18)
        }
    }

    private var stem: some View {
        Rectangle()
            .fill(stemColor)
            .frame(width: 10, height: CGFloat(progress) * stemMax)
            .offset(y: -CGFloat(stemMax) / 2)
            .opacity(state == .idle ? 0 : 1)
    }

    private var leaves: some View {
        let stemHeight = CGFloat(progress) * stemMax
        return ZStack {
            if progress > 0.15 {
                Ellipse()
                    .fill(stemColor)
                    .frame(width: 24, height: 12)
                    .rotationEffect(.degrees(-30))
                    .offset(x: -potWidth * 0.25, y: -stemHeight * 0.7)
            }
            if progress > 0.4 {
                Ellipse()
                    .fill(stemColor)
                    .frame(width: 24, height: 12)
                    .rotationEffect(.degrees(30))
                    .offset(x: potWidth * 0.25, y: -stemHeight * 0.4)
            }
        }
    }

    private var flower: some View {
        let show = progress > 0.9 || state == .success
        return Group {
            if show {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(y: -stemMax + -10)
                    .transition(.scale)
            }
        }
    }
}

// MARK: Shapes & helpers

struct PotShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let inset: CGFloat = rect.width * 0.15
        p.move(to: CGPoint(x: inset, y: 0))
        p.addLine(to: CGPoint(x: rect.width - inset, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

fileprivate extension Color {
    func darker(by amount: Double) -> Color {
        let ui = NSColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: Double(h), saturation: Double(s), brightness: max(0, Double(b) - amount))
    }
} 