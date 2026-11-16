import SwiftUI

private enum NotificationLayout {
    static let badgeSize: CGFloat = 40
    static let iconSize: CGFloat = 19
    static let gap: CGFloat = 12
    static let textGap: CGFloat = 2
    static let titleSize: CGFloat = 15
    static let subtitleSize: CGFloat = 12.5
    static let arrivalDelay: UInt64 = 250_000_000
    static let pulseCount = 2
    static let warning = Color.orange
    static let critical = Color(red: 1, green: 0.4, blue: 0.36)
    static let secondary = Color.white.opacity(0.62)
    static let badgeOpacity = 0.16
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.78)
    static let fade = Animation.easeInOut(duration: 0.2)
}

extension NotificationStyle {
    fileprivate var tint: Color {
        switch self {
        case .info: return .white
        case .warning: return NotificationLayout.warning
        case .critical: return NotificationLayout.critical
        }
    }
}

struct NotificationView: View {
    let notification: IslandNotification
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrival = 0

    var body: some View {
        HStack(spacing: NotificationLayout.gap) {
            badge
            VStack(alignment: .leading, spacing: NotificationLayout.textGap) {
                Text(notification.title)
                    .font(.system(size: NotificationLayout.titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                if let subtitle = notification.subtitle {
                    Text(subtitle)
                        .font(.system(size: NotificationLayout.subtitleSize, weight: .medium, design: .rounded))
                        .foregroundStyle(notification.style == .info ? NotificationLayout.secondary : notification.style.tint)
                }
            }
            .lineLimit(1)
            .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? NotificationLayout.fade : NotificationLayout.spring, value: notification)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notification.announcement)
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(nanoseconds: NotificationLayout.arrivalDelay)
            arrival += 1
        }
        .onChange(of: notification) {
            if !reduceMotion { arrival += 1 }
        }
    }

    private var badge: some View {
        Image(systemName: notification.symbol)
            .font(.system(size: NotificationLayout.iconSize, weight: .semibold))
            .foregroundStyle(notification.style.tint)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            .symbolEffect(.bounce, options: .nonRepeating, value: arrival)
            .symbolEffect(.pulse, options: .repeat(NotificationLayout.pulseCount),
                          isActive: notification.style != .info && !reduceMotion)
            .frame(width: NotificationLayout.badgeSize, height: NotificationLayout.badgeSize)
            .background(notification.style.tint.opacity(NotificationLayout.badgeOpacity), in: Circle())
    }
}
