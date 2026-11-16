import Foundation

enum LyricsViewMode: String, CaseIterable, Identifiable {
    case karaoke, list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .karaoke: return "Karaoke"
        case .list: return "List"
        }
    }

    var symbol: String {
        switch self {
        case .karaoke: return "music.mic"
        case .list: return "list.bullet"
        }
    }

    var next: LyricsViewMode {
        let all = Self.allCases
        return all[((all.firstIndex(of: self) ?? 0) + 1) % all.count]
    }
}

struct LyricWord: Equatable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval

    /// How much of the word has been sung at `position`, 0...1.
    func progress(at position: TimeInterval) -> Double {
        guard end > start else { return position >= start ? 1 : 0 }
        return min(1, max(0, (position - start) / (end - start)))
    }
}

enum KaraokeTiming {
    static let secondsPerCharacter: TimeInterval = 0.3
    static let minimumLineDuration: TimeInterval = 1

    /// Splits a line into words and shares `start`...`end` between them in proportion to their length.
    static func words(in text: String, from start: TimeInterval, to end: TimeInterval) -> [LyricWord] {
        let pieces = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let total = pieces.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        let span = max(0, end - start)
        var cursor = start
        return pieces.map { piece in
            let word = LyricWord(text: piece, start: cursor, end: cursor + span * Double(piece.count) / Double(total))
            cursor = word.end
            return word
        }
    }

    /// When a line stops being sung: its natural length by character count, cut short by the next line or the end of the track.
    static func lineEnd(of line: LyricLine, next: LyricLine?, trackDuration: TimeInterval) -> TimeInterval {
        let natural = max(minimumLineDuration, Double(line.text.count) * secondsPerCharacter)
        let ceiling = next?.time ?? (trackDuration > line.time ? trackDuration : line.time + natural)
        return line.time + min(natural, max(0, ceiling - line.time))
    }

    /// The sung words of the line at `index`, ready to be filled as the song plays.
    static func words(of lines: [LyricLine], at index: Int, trackDuration: TimeInterval) -> [LyricWord] {
        let line = lines[index]
        let next = lines.indices.contains(index + 1) ? lines[index + 1] : nil
        let text = line.text.isEmpty ? "♪" : line.text
        return words(in: text, from: line.time, to: lineEnd(of: line, next: next, trackDuration: trackDuration))
    }
}
