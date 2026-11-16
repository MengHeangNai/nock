import SwiftUI

// MARK: - Now Playing

struct NowPlayingTab: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var timer: IslandTimer
    @ObservedObject var settings: DockSettings
    let audio: AudioLevelMonitor
    let state: IslandState

    var body: some View {
        if nowPlaying.player == nil {
            idleView
        } else {
            playerView
        }
    }

    private var playerView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ArtworkView(nowPlaying: nowPlaying, size: 64)
                    .onTapGesture { nowPlaying.openPlayer() }
                    .hoverLabel("Open \(nowPlaying.player?.displayName ?? "player")", edge: .bottom)

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowPlaying.title ?? "Unknown Song")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    Text(nowPlaying.artist ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    CurrentLyricLine(nowPlaying: nowPlaying, lyrics: lyrics)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if settings.showVisualizer {
                    MusicVisualizer(nowPlaying: nowPlaying, settings: settings, audio: audio)
                }

                if timer.isActive {
                    Button { state.tab = .timer } label: {
                        TimelineView(.periodic(from: .now, by: 0.5)) { context in
                            Label(IslandTimer.format(timer.remaining(at: context.date)), systemImage: "timer")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button { state.tab = .lyrics } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(nowPlaying.accentColor)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: nowPlaying.isPlaying)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverLabel("Lyrics", edge: .bottom, anchor: .trailing)
            }

            PlaybackProgress(nowPlaying: nowPlaying)

            HStack(spacing: 44) {
                controlButton("backward.end.fill", size: 16, action: nowPlaying.previous)
                controlButton(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 24, action: nowPlaying.playPause)
                controlButton("forward.end.fill", size: 16, action: nowPlaying.next)
            }
        }
    }

    private var idleView: some View {
        HStack(spacing: 16) {
            ArtworkView(nowPlaying: nowPlaying, size: 80)
                .onTapGesture { nowPlaying.openPlayer() }
                .hoverLabel("Choose Apple Music or Spotify", edge: .bottom, anchor: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("Not Playing")
                    .font(.system(size: 16, weight: .semibold))
                Text("Play something in Apple Music or Spotify")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                controlButton("play.fill", size: 22, action: nowPlaying.playPause)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLabel(playbackControlName(symbol), edge: .top)
    }
}

// MARK: - Pieces

/// Album artwork, falling back to the player's icon, then a music note.
struct ArtworkView: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    let size: CGFloat

    var body: some View {
        Group {
            if let artwork = nowPlaying.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else if let icon = nowPlaying.playerIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// The line being sung right now, shown under the artist.
struct CurrentLyricLine: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        if lyrics.status == .synced {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let index = lyrics.lineIndex(at: nowPlaying.position(at: context.date))
                let text = index.map { lyrics.lines[$0].text } ?? ""
                Text(text.isEmpty ? "♪" : text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(nowPlaying.accentColor)
                    .lineLimit(1)
                    .id(index ?? -1)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(.easeOut(duration: 0.25), value: index)
            }
            .padding(.top, 3)
        }
    }
}

/// Elapsed time, a draggable progress bar, and remaining time.
/// `compact` puts the times under the bar, for narrow spaces like the lyrics card.
struct PlaybackProgress: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    var compact = false
    var showsTimes = true
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = nowPlaying.duration
            let position = dragFraction.map { $0 * duration } ?? nowPlaying.position(at: context.date)
            let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
            let elapsed = Self.format(position)
            let remaining = "-" + Self.format(max(0, duration - position))

            Group {
                if !showsTimes {
                    bar(fraction: fraction, duration: duration)
                        .frame(height: 10)
                } else if compact {
                    VStack(spacing: 3) {
                        bar(fraction: fraction, duration: duration)
                            .frame(height: 10)
                        HStack {
                            Text(elapsed)
                            Spacer()
                            Text(remaining)
                        }
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                } else {
                    HStack(spacing: 10) {
                        Text(elapsed)
                            .frame(width: 40, alignment: .leading)
                        bar(fraction: fraction, duration: duration)
                            .frame(height: 14)
                        Text(remaining)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                }
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .opacity(duration > 0 ? 1 : 0.4)
            .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
        }
    }

    private func bar(fraction: Double, duration: TimeInterval) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white).frame(width: geometry.size.width * fraction)
            }
            .frame(height: dragFraction == nil ? (compact ? 4 : 5) : (compact ? 6 : 7))
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        dragFraction = min(max(value.location.x / geometry.size.width, 0), 1)
                    }
                    .onEnded { value in
                        guard duration > 0 else { return }
                        let target = min(max(value.location.x / geometry.size.width, 0), 1)
                        nowPlaying.seek(to: target * duration)
                        dragFraction = nil
                    }
            )
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Lyrics

struct LyricsTab: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var settings: DockSettings

    var body: some View {
        if nowPlaying.player == nil {
            lyricsContent
        } else {
            HStack(spacing: 18) {
                MiniPlayerCard(nowPlaying: nowPlaying)
                lyricsContent
            }
        }
    }

    @ViewBuilder
    private var lyricsContent: some View {
        switch lyrics.status {
        case .synced:
            syncedContent
        case .plain:
            ScrollView(showsIndicators: false) {
                Text(lyrics.plainText ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .loading:
            message("Finding lyrics…", spinner: true)
        case .notFound:
            message("No lyrics found for this song")
        case .off:
            message("Lyrics are turned off in Settings")
        case .idle:
            message("Play a song to see its lyrics")
        }
    }

    private var syncedContent: some View {
        ZStack(alignment: .topTrailing) {
            switch settings.lyricsMode {
            case .karaoke: KaraokeLyricsView(nowPlaying: nowPlaying, lyrics: lyrics)
            case .list: SyncedLyricsView(nowPlaying: nowPlaying, lyrics: lyrics)
            }
            modeButton
        }
    }

    private var modeButton: some View {
        let target = settings.lyricsMode.next
        return Button { settings.lyricsMode = target } label: {
            Image(systemName: target.symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .hoverLabel("\(target.title) view", edge: .bottom, anchor: .trailing)
        .accessibilityLabel("Show lyrics as \(target.title.lowercased())")
    }

    private func message(_ text: String, spinner: Bool = false) -> some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().controlSize(.small) }
            Text(text)
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A compact version of the Now Playing view, shown beside the lyrics.
private struct MiniPlayerCard: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ArtworkView(nowPlaying: nowPlaying, size: 44)
                    .onTapGesture { nowPlaying.openPlayer() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.title ?? "Unknown Song")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(nowPlaying.artist ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(nowPlaying.accentColor)
                    .symbolEffect(.variableColor.iterative.reversing, isActive: nowPlaying.isPlaying)
            }

            PlaybackProgress(nowPlaying: nowPlaying, compact: true)

            HStack(spacing: 0) {
                control("backward.end.fill", size: 13, action: nowPlaying.previous)
                control(nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: 18, action: nowPlaying.playPause)
                control("forward.end.fill", size: 13, action: nowPlaying.next)
            }
        }
        .padding(12)
        .frame(width: 210)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxHeight: .infinity)
    }

    private func control(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(maxWidth: .infinity, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLabel(playbackControlName(symbol), edge: .top)
    }
}

/// Full lyrics that scroll with the song. Click a line to jump to it.
private struct SyncedLyricsView: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let current = lyrics.lineIndex(at: nowPlaying.position(at: context.date))
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(lyrics.lines) { line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(line.id == current ? Color.white : Color.white.opacity(0.3))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { nowPlaying.seek(to: line.time) }
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, 50)
                    .animation(.easeOut(duration: 0.25), value: current)
                }
                .onChange(of: current, initial: true) { _, index in
                    guard let index else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) }
                }
            }
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.2),
                .init(color: .black, location: 0.8),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }
}
