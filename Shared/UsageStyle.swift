import SwiftUI

enum UsageStyle {
    static func color(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return Color(red: 0.85, green: 0.47, blue: 0.34) // Claude clay
        case ..<0.85: return .orange
        default: return .red
        }
    }

    static func percent(_ utilization: Double) -> String {
        "\(Int(utilization.rounded()))%"
    }
}

/// Horizontal usage bar with a thin tick showing how much of the window's time has elapsed.
/// Usage to the right of the tick means you are burning faster than an even pace.
struct UsageBar: View {
    var window: UsageWindow
    var now: Date = .now
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(UsageStyle.color(for: window.fraction))
                    .frame(width: max(geo.size.width * window.fraction, window.fraction > 0 ? height : 0))
                if let elapsed = window.elapsedFraction(at: now) {
                    Rectangle()
                        .fill(.primary.opacity(0.55))
                        .frame(width: 1.5, height: height + 4)
                        .offset(x: geo.size.width * elapsed - 0.75)
                }
            }
        }
        .frame(height: height)
    }
}

struct UsageRing: View {
    var window: UsageWindow
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: window.fraction)
                .stroke(UsageStyle.color(for: window.fraction),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(UsageStyle.percent(window.utilization))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .padding(lineWidth / 2)
    }
}
