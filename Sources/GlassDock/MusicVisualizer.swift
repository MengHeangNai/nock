import CoreGraphics
import Foundation

enum VisualizerStyle: String, CaseIterable, Identifiable {
    case bars, wave, rings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bars: return "Bars"
        case .wave: return "Wave"
        case .rings: return "Rings"
        }
    }

    var next: VisualizerStyle {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }
}

final class LevelHistory {
    static let capacity = 64
    static let minimumSpacing: TimeInterval = 1.0 / 60

    private(set) var frames: [[CGFloat]]
    private var lastRecorded: Date?

    init(frames: [[CGFloat]] = []) {
        self.frames = frames
    }

    convenience init(repeating frame: [CGFloat]) {
        self.init(frames: [[CGFloat]](repeating: frame, count: Self.capacity))
    }

    /// Adds a frame, dropping the oldest past the capacity. A frame less than 1/60 s after the last one is ignored.
    func record(_ frame: [CGFloat], at date: Date) {
        if let lastRecorded, date.timeIntervalSince(lastRecorded) < Self.minimumSpacing { return }
        lastRecorded = date
        frames.append(frame)
        if frames.count > Self.capacity { frames.removeFirst(frames.count - Self.capacity) }
    }
}

enum VisualizerShape {
    static let ringDelay = 4

    /// The loudness of one frame: the mean of its bands, 0...1.
    static func overall(_ frame: [CGFloat]) -> CGFloat {
        guard !frame.isEmpty else { return 0 }
        return min(1, max(0, frame.reduce(0, +) / CGFloat(frame.count)))
    }

    /// Spreads the few bands over `count` bars. Each bar reads a slightly older frame, so neighbours move apart like a spectrum.
    static func bars(from history: [[CGFloat]], count: Int) -> [CGFloat] {
        (0..<max(0, count)).map { index in
            guard let frame = history.dropLast((index * 5) % 7).last else { return 0 }
            return interpolate(frame, at: count > 1 ? Double(index) / Double(count - 1) : 0)
        }
    }

    /// The loudness over the last `count` frames, oldest first and lightly smoothed; frames not yet recorded count as silence.
    static func wave(from history: [[CGFloat]], count: Int) -> [CGFloat] {
        let recent = history.suffix(max(0, count)).map(overall)
        let levels = [CGFloat](repeating: 0, count: max(0, count) - recent.count) + recent
        return levels.indices.map { index in
            let neighbours = levels[max(0, index - 1)...min(levels.count - 1, index + 1)]
            return neighbours.reduce(0, +) / CGFloat(neighbours.count)
        }
    }

    /// One level per ring, innermost first. Each ring reads an older frame than the one inside it, so a beat travels outward.
    static func rings(from history: [[CGFloat]], count: Int) -> [CGFloat] {
        (0..<max(0, count)).map { ring in
            history.dropLast(ring * ringDelay).last.map(overall) ?? 0
        }
    }

    /// A gentle moving frame for when playback is known but the audio tap is unavailable.
    static func idleFrame(at time: TimeInterval, bandCount: Int) -> [CGFloat] {
        (0..<bandCount).map { band in
            let phase = time * (1.7 + 0.6 * Double(band)) + Double(band) * 1.3
            return CGFloat(0.3 + 0.25 * sin(phase))
        }
    }

    private static func interpolate(_ frame: [CGFloat], at position: Double) -> CGFloat {
        guard !frame.isEmpty else { return 0 }
        let scaled = position * Double(frame.count - 1)
        let lower = min(frame.count - 1, max(0, Int(scaled)))
        let upper = min(frame.count - 1, lower + 1)
        let fraction = scaled - Double(lower)
        let eased = CGFloat(fraction * fraction * (3 - 2 * fraction))
        return min(1, max(0, frame[lower] * (1 - eased) + frame[upper] * eased))
    }
}

struct VisualizerPalette: Equatable {
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double
    }

    static let neutral = VisualizerPalette(primary: RGB(red: 0.86, green: 0.88, blue: 0.94),
                                           secondary: RGB(red: 0.52, green: 0.58, blue: 0.70))

    private static let sampleSide = 16
    private static let hueBins = 12
    private static let minimumVividness = 0.04
    private static let minimumSecondaryShare = 0.2

    var primary: RGB
    var secondary: RGB

    private init(primary: RGB, secondary: RGB) {
        self.primary = primary
        self.secondary = secondary
    }

    /// Picks two accent colors from `side` x `side` premultiplied RGBA pixels. Gray or very dark art gives `neutral`.
    init(pixels: [UInt8], side: Int) {
        var weights = [Double](repeating: 0, count: Self.hueBins)
        var sums = [RGB](repeating: RGB(red: 0, green: 0, blue: 0), count: Self.hueBins)
        for index in 0..<min(side * side, pixels.count / 4) {
            let alpha = Double(pixels[index * 4 + 3]) / 255
            guard alpha > 0.1 else { continue }
            let color = RGB(red: min(1, Double(pixels[index * 4]) / 255 / alpha),
                            green: min(1, Double(pixels[index * 4 + 1]) / 255 / alpha),
                            blue: min(1, Double(pixels[index * 4 + 2]) / 255 / alpha))
            let weight = color.saturation * color.brightness * alpha
            let bin = min(Self.hueBins - 1, Int(color.hue * Double(Self.hueBins)))
            weights[bin] += weight
            sums[bin].red += color.red * weight
            sums[bin].green += color.green * weight
            sums[bin].blue += color.blue * weight
        }

        guard weights.reduce(0, +) > Double(side * side) * Self.minimumVividness,
              let main = weights.indices.max(by: { weights[$0] < weights[$1] }) else {
            self = .neutral
            return
        }

        func average(_ bin: Int) -> RGB {
            RGB(red: sums[bin].red / weights[bin], green: sums[bin].green / weights[bin],
                blue: sums[bin].blue / weights[bin]).vivid
        }
        let distant = weights.indices.filter { bin in
            let gap = abs(bin - main)
            return min(gap, Self.hueBins - gap) >= 2 && weights[bin] >= weights[main] * Self.minimumSecondaryShare
        }
        let primary = average(main)
        if let second = distant.max(by: { weights[$0] < weights[$1] }) {
            self.init(primary: primary, secondary: average(second))
        } else {
            let shifted = RGB(hue: primary.hue + 1.0 / Double(Self.hueBins), saturation: primary.saturation,
                              brightness: primary.brightness)
            self.init(primary: primary, secondary: shifted)
        }
    }

    /// Picks two accent colors from an image after scaling it down. Returns nil when the small bitmap cannot be made.
    init?(image: CGImage) {
        let side = Self.sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        self.init(pixels: pixels, side: side)
    }
}

extension VisualizerPalette.RGB {
    init(hue: Double, saturation: Double, brightness: Double) {
        let scaled = (hue - hue.rounded(.down)) * 6
        let fraction = scaled - scaled.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        switch Int(scaled) % 6 {
        case 0: self.init(red: brightness, green: rising, blue: low)
        case 1: self.init(red: falling, green: brightness, blue: low)
        case 2: self.init(red: low, green: brightness, blue: rising)
        case 3: self.init(red: low, green: falling, blue: brightness)
        case 4: self.init(red: rising, green: low, blue: brightness)
        default: self.init(red: brightness, green: low, blue: falling)
        }
    }

    var brightness: Double { max(red, green, blue) }

    var saturation: Double {
        let top = brightness
        return top > 0 ? (top - min(red, green, blue)) / top : 0
    }

    var hue: Double {
        let top = brightness
        let delta = top - min(red, green, blue)
        guard delta > 0 else { return 0 }
        let sector: Double
        if top == red {
            sector = (green - blue) / delta
        } else if top == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        let turns = sector / 6
        return turns - turns.rounded(.down)
    }

    var vivid: Self {
        Self(hue: hue, saturation: max(saturation, 0.5), brightness: max(brightness, 0.85))
    }
}
