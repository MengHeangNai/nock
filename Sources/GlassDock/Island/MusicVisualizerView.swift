import SwiftUI

private enum VisualizerLayout {
    static let size = CGSize(width: 128, height: 52)
    static let frameInterval: TimeInterval = 1.0 / 30
    static let barCount = 24
    static let ringCount = 4
    static let stillOpacity = 0.45
    static let stillFrame: [CGFloat] = [0.55, 0.7, 0.5, 0.35]
}

struct MusicVisualizer: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var settings: DockSettings
    let audio: AudioLevelMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button { settings.visualizerStyle = settings.visualizerStyle.next } label: {
            Group {
                if reduceMotion {
                    VisualizerCanvas(style: settings.visualizerStyle, palette: nowPlaying.palette,
                                     history: LevelHistory(repeating: VisualizerLayout.stillFrame), time: 0)
                        .opacity(VisualizerLayout.stillOpacity)
                } else {
                    LiveVisualizer(nowPlaying: nowPlaying, style: settings.visualizerStyle, audio: audio)
                }
            }
            .accessibilityHidden(true)
            .frame(width: VisualizerLayout.size.width, height: VisualizerLayout.size.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLabel("\(settings.visualizerStyle.title) visualizer, click to change", edge: .bottom)
        .accessibilityLabel("Music visualizer, \(settings.visualizerStyle.title)")
        .accessibilityHint("Changes the visualizer style")
    }
}

private struct LiveVisualizer: View {
    @ObservedObject var nowPlaying: NowPlayingMonitor
    let style: VisualizerStyle
    let audio: AudioLevelMonitor
    @State private var history = LevelHistory()
    @State private var isCapturing = false

    var body: some View {
        TimelineView(.animation(minimumInterval: VisualizerLayout.frameInterval)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let _ = history.record(frame(at: time), at: timeline.date)
            VisualizerCanvas(style: style, palette: nowPlaying.palette, history: history, time: time)
        }
        .onAppear { setCapturing(nowPlaying.isPlaying) }
        .onChange(of: nowPlaying.isPlaying) { _, isPlaying in setCapturing(isPlaying) }
        .onDisappear { setCapturing(false) }
    }

    private func frame(at time: TimeInterval) -> [CGFloat] {
        guard nowPlaying.isPlaying else { return [CGFloat](repeating: 0, count: AudioLevelMonitor.bandCount) }
        return audio.isCapturing ? audio.levels : VisualizerShape.idleFrame(at: time, bandCount: AudioLevelMonitor.bandCount)
    }

    private func setCapturing(_ wanted: Bool) {
        guard wanted != isCapturing else { return }
        isCapturing = wanted
        if wanted { audio.start() } else { audio.stop() }
    }
}

private struct VisualizerCanvas: View {
    let style: VisualizerStyle
    let palette: VisualizerPalette
    let history: LevelHistory
    let time: TimeInterval

    var body: some View {
        Canvas { context, size in
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [palette.primary.color, palette.secondary.color]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
            switch style {
            case .bars: drawBars(context, size, shading)
            case .wave: drawWave(context, size, shading)
            case .rings: drawRings(context, size, shading)
            }
        }
    }

    private func drawBars(_ context: GraphicsContext, _ size: CGSize, _ shading: GraphicsContext.Shading) {
        let levels = VisualizerShape.bars(from: history.frames, count: VisualizerLayout.barCount)
        let slot = size.width / CGFloat(levels.count)
        let width = slot * 0.55
        for (index, level) in levels.enumerated() {
            let height = max(3, level * size.height)
            let rect = CGRect(x: slot * CGFloat(index) + (slot - width) / 2, y: (size.height - height) / 2,
                              width: width, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: shading)
        }
    }

    private func drawWave(_ context: GraphicsContext, _ size: CGSize, _ shading: GraphicsContext.Shading) {
        let envelope = VisualizerShape.wave(from: history.frames, count: LevelHistory.capacity)
        for (offset, opacity, width) in [(1.7, 0.35, 1.5), (0.0, 1.0, 2.5)] {
            var path = Path()
            for (index, level) in envelope.enumerated() {
                let progress = CGFloat(index) / CGFloat(envelope.count - 1)
                let taper = sin(progress * .pi)
                let carrier = sin(progress * .pi * 6 + time * 5 + offset)
                let point = CGPoint(x: progress * size.width,
                                    y: size.height / 2 - max(0.04, level) * taper * carrier * size.height / 2)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            var layer = context
            layer.opacity = opacity
            layer.stroke(path, with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawRings(_ context: GraphicsContext, _ size: CGSize, _ shading: GraphicsContext.Shading) {
        let levels = VisualizerShape.rings(from: history.frames, count: VisualizerLayout.ringCount)
        for (index, level) in levels.enumerated() {
            let scale = CGFloat(index + 1) / CGFloat(levels.count) * (0.7 + 0.3 * level)
            let rect = CGRect(x: size.width * (1 - scale) / 2, y: size.height * (1 - scale) / 2,
                              width: size.width * scale, height: size.height * scale)
            var ring = context
            ring.opacity = 0.35 + 0.65 * Double(level)
            ring.stroke(Path(ellipseIn: rect), with: shading, lineWidth: 1.5 + 1.5 * level)
        }
    }
}

extension VisualizerPalette.RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}
