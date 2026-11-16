import SwiftUI

private enum HUDStyle {
    static let iconSize: CGFloat = 26
    static let iconWidth: CGFloat = 38
    static let gap: CGFloat = 12
    static let rowGap: CGFloat = 9
    static let barHeight: CGFloat = 8
    static let labelSize: CGFloat = 13
    static let track = Color.white.opacity(0.18)
    static let fill = LinearGradient(colors: [.white.opacity(0.82), .white.opacity(0.96)],
                                     startPoint: .leading, endPoint: .trailing)
    static let secondary = Color.white.opacity(0.62)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)
}

struct HUDView: View {
    let reading: HUDReading

    var body: some View {
        HStack(spacing: HUDStyle.gap) {
            Image(systemName: reading.symbol, variableValue: reading.symbolValue)
                .font(.system(size: HUDStyle.iconSize, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: HUDStyle.iconWidth)

            VStack(spacing: HUDStyle.rowGap) {
                HStack {
                    Text(reading.label)
                        .foregroundStyle(HUDStyle.secondary)
                    Spacer(minLength: 8)
                    Text(reading.isMuted ? "Muted" : "\(reading.percent)%")
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .font(.system(size: HUDStyle.labelSize, weight: .semibold, design: .rounded))

                HUDBar(level: reading.level)
            }
        }
        .foregroundStyle(.white)
        .animation(HUDStyle.spring, value: reading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.isMuted ? "\(reading.label) muted" : "\(reading.label) \(reading.percent) percent")
    }
}

private struct HUDBar: View {
    let level: Float

    var body: some View {
        Capsule()
            .fill(HUDStyle.track)
            .frame(height: HUDStyle.barHeight)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(HUDStyle.fill)
                        .frame(width: proxy.size.width * CGFloat(level))
                }
            }
    }
}
