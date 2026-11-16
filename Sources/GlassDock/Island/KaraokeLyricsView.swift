import SwiftUI

private enum KaraokeLayout {
    static let frameInterval: TimeInterval = 1.0 / 30
    static let reducedMotionInterval: TimeInterval = 0.25
    static let cornerRadius: CGFloat = 18
    static let horizontalPadding: CGFloat = 20
    static let lineSpacing: CGFloat = 8
    static let neighbourFontSize: CGFloat = 12
    static let neighbourHeight: CGFloat = 16
    static let neighbourScale: CGFloat = 0.7
    static let neighbourOpacity = 0.35
    static let currentFontSize: CGFloat = 28
    static let currentScale: CGFloat = 0.5
    static let currentLineLimit = 2
    static let unsungOpacity = 0.35
    static let topWash = 0.32
    static let middleWash = 0.16
    static let bottomWash = 0.28
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.85)
    static let fade = Animation.easeInOut(duration: 0.2)
    static let backgroundFade = Animation.easeInOut(duration: 0.8)
}

struct KaraokeLyricsView: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var lyrics: LyricsService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let interval = reduceMotion ? KaraokeLayout.reducedMotionInterval : KaraokeLayout.frameInterval
        ZStack {
            KaraokeBackground(palette: nowPlaying.palette)
            TimelineView(.animation(minimumInterval: interval, paused: !nowPlaying.isPlaying)) { context in
                let position = nowPlaying.position(at: context.date)
                KaraokeStage(lines: lyrics.lines, index: lyrics.lineIndex(at: position),
                             position: position + LyricsService.lookahead, trackDuration: nowPlaying.duration,
                             reduceMotion: reduceMotion)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: KaraokeLayout.cornerRadius, style: .continuous))
    }
}

private struct KaraokeBackground: View {
    let palette: VisualizerPalette

    var body: some View {
        ZStack {
            palette.primary.color.opacity(KaraokeLayout.topWash)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
            palette.primary.color.opacity(KaraokeLayout.middleWash)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: .black, location: 0.5),
                                             .init(color: .clear, location: 0.8)],
                                     startPoint: .top, endPoint: .bottom))
            palette.secondary.color.opacity(KaraokeLayout.bottomWash)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
        }
        .animation(KaraokeLayout.backgroundFade, value: palette)
        .accessibilityHidden(true)
    }
}

private struct KaraokeStage: View {
    let lines: [LyricLine]
    let index: Int?
    let position: TimeInterval
    let trackDuration: TimeInterval
    let reduceMotion: Bool

    private var previous: String? { index.flatMap { $0 > 0 ? lines[$0 - 1].text : nil } }
    private var next: String? {
        let upcoming = (index ?? -1) + 1
        return lines.indices.contains(upcoming) ? lines[upcoming].text : nil
    }
    private var words: [LyricWord] {
        index.map { KaraokeTiming.words(of: lines, at: $0, trackDuration: trackDuration) }
            ?? [LyricWord(text: "♪", start: 0, end: 0)]
    }
    private var transition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity))
    }

    var body: some View {
        let currentWords = words
        VStack(spacing: KaraokeLayout.lineSpacing) {
            neighbour(previous)
            Text(sung(currentWords))
                .font(.system(size: KaraokeLayout.currentFontSize, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(KaraokeLayout.currentLineLimit)
                .minimumScaleFactor(KaraokeLayout.currentScale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(index ?? -1)
                .transition(transition)
            neighbour(next)
        }
        .padding(.horizontal, KaraokeLayout.horizontalPadding)
        .padding(.vertical, KaraokeLayout.lineSpacing)
        .animation(reduceMotion ? KaraokeLayout.fade : KaraokeLayout.spring, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(currentWords.map(\.text).joined(separator: " "))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func neighbour(_ text: String?) -> some View {
        Text(text.map { $0.isEmpty ? "♪" : $0 } ?? "")
            .font(.system(size: KaraokeLayout.neighbourFontSize, weight: .medium))
            .foregroundStyle(.white.opacity(KaraokeLayout.neighbourOpacity))
            .lineLimit(1)
            .minimumScaleFactor(KaraokeLayout.neighbourScale)
            .frame(maxWidth: .infinity, minHeight: KaraokeLayout.neighbourHeight)
            .id(index ?? -1)
            .transition(transition)
    }

    private func sung(_ words: [LyricWord]) -> AttributedString {
        var line = AttributedString()
        for (offset, word) in words.enumerated() {
            var piece = AttributedString(offset < words.count - 1 ? word.text + " " : word.text)
            let progress = reduceMotion ? 1 : word.progress(at: position)
            piece.foregroundColor = Color.white.opacity(KaraokeLayout.unsungOpacity + (1 - KaraokeLayout.unsungOpacity) * progress)
            line += piece
        }
        return line
    }
}
