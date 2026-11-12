import SwiftUI

struct NowPlayingWidget: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.14) {
            artwork
                .contentShape(Rectangle())
                .onTapGesture { nowPlaying.openPlayer() }
                .help(nowPlaying.player == nil ? "Choose Apple Music or Spotify" : "Open player")
            VStack(alignment: .leading, spacing: 1) {
                Text(nowPlaying.title ?? "Not Playing")
                    .font(.system(size: size * 0.2, weight: .semibold))
                    .lineLimit(1)
                Text(nowPlaying.artist ?? (nowPlaying.player == nil ? "Music or Spotify" : ""))
                    .font(.system(size: size * 0.17))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: size * 0.04) {
                control("backward.fill", action: nowPlaying.previous)
                control(nowPlaying.isPlaying ? "pause.fill" : "play.fill", action: nowPlaying.playPause)
                control("forward.fill", action: nowPlaying.next)
            }
        }
        .padding(.horizontal, size * 0.14)
    }

    private var artwork: some View {
        ArtworkView(nowPlaying: nowPlaying, size: size * 0.62)
    }

    private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.2))
                .frame(width: size * 0.3, height: size * 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLabel(playbackControlName(symbol), edge: .top)
    }
}

struct BatteryWidget: View {
    @ObservedObject var battery: BatteryMonitor
    let size: CGFloat

    var body: some View {
        let level = battery.level ?? 0
        let low = level <= 20 && !battery.isCharging
        VStack(spacing: size * 0.04) {
            Image(systemName: symbol(for: level))
                .font(.system(size: size * 0.3))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(low ? Color.red : Color.primary)
            Text("\(level)%")
                .font(.system(size: size * 0.2, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func symbol(for level: Int) -> String {
        if battery.isCharging || battery.isPluggedIn { return "battery.100percent.bolt" }
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

struct ClockWidget: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: size * 0.02) {
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(context.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: size * 0.17))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, size * 0.08)
        }
    }
}


#Preview {
    NowPlayingWidget(
        nowPlaying: NowPlayingMonitor(),
        size: 200
    )
}
