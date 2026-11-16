import Foundation
import Combine

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: TimeInterval
    let text: String
}

/// Looks up lyrics for the current song on LRCLIB (lrclib.net), a free lyrics library.
/// Only the title, artist, album and length are sent.
final class LyricsService: ObservableObject {
    enum Status: Equatable {
        case off, idle, loading, synced, plain, notFound
    }

    private struct Found {
        let lines: [LyricLine]
        let plain: String?
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var plainText: String?

    private let nowPlaying: NowPlayingMonitor
    private let settings: DockSettings
    private var cancellables = Set<AnyCancellable>()
    private var cache: [String: Found?] = [:]
    private var currentKey: String?

    init(nowPlaying: NowPlayingMonitor, settings: DockSettings) {
        self.nowPlaying = nowPlaying
        self.settings = settings

        Publishers.CombineLatest3(nowPlaying.$title, nowPlaying.$artist, settings.$showLyrics)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    static let lookahead: TimeInterval = 0.3

    /// Index of the line being sung at the given position.
    func lineIndex(at position: TimeInterval) -> Int? {
        Self.lineIndex(in: lines, at: position)
    }

    /// Index of the line being sung at the given position, in lines sorted by time.
    static func lineIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
        let target = position + lookahead
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= target {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    private func reload() {
        guard settings.showLyrics else {
            currentKey = nil
            apply(status: .off, lines: [], plain: nil)
            return
        }
        guard let title = nowPlaying.title, !title.isEmpty, let artist = nowPlaying.artist else {
            currentKey = nil
            apply(status: .idle, lines: [], plain: nil)
            return
        }

        let key = artist + "\n" + title
        guard key != currentKey else { return }
        currentKey = key

        if let cached = cache[key] {
            apply(cached)
            return
        }

        apply(status: .loading, lines: [], plain: nil)
        fetch(title: title, artist: artist, album: nowPlaying.album, duration: nowPlaying.duration) { [weak self] found in
            guard let self else { return }
            self.cache[key] = found
            if self.currentKey == key { self.apply(found) }
        }
    }

    private func apply(_ found: Found?) {
        guard let found else {
            apply(status: .notFound, lines: [], plain: nil)
            return
        }
        apply(status: found.lines.isEmpty ? .plain : .synced, lines: found.lines, plain: found.plain)
    }

    private func apply(status: Status, lines: [LyricLine], plain: String?) {
        self.lines = lines
        self.plainText = plain
        self.status = status
    }

    // MARK: Network

    private func fetch(title: String, artist: String, album: String?, duration: TimeInterval,
                       completion: @escaping (Found?) -> Void) {
        let search = {
            var components = URLComponents(string: "https://lrclib.net/api/search")!
            components.queryItems = [
                URLQueryItem(name: "track_name", value: title),
                URLQueryItem(name: "artist_name", value: artist),
            ]
            self.request(components.url!) { json in
                let results = (json as? [[String: Any]]) ?? []
                let ranked = results.sorted { Self.score($0, duration: duration) < Self.score($1, duration: duration) }
                completion(ranked.lazy.compactMap(Self.parse).first)
            }
        }

        // The exact-match endpoint needs the album and length; otherwise go straight to search.
        guard let album, !album.isEmpty, duration > 0 else {
            search()
            return
        }
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        request(components.url!) { json in
            if let json = json as? [String: Any], let found = Self.parse(json) {
                completion(found)
            } else {
                search()
            }
        }
    }

    private func request(_ url: URL, completion: @escaping (Any?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("GlassDock/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let json = ok ? data.flatMap { try? JSONSerialization.jsonObject(with: $0) } : nil
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }

    /// Lower is better: prefer synced lyrics, then the closest length.
    private static func score(_ result: [String: Any], duration: TimeInterval) -> Double {
        let synced = (result["syncedLyrics"] as? String).map { !$0.isEmpty } ?? false
        let length = (result["duration"] as? NSNumber)?.doubleValue ?? 0
        let distance = duration > 0 ? abs(length - duration) : 0
        return (synced ? 0 : 1000) + distance
    }

    private static func parse(_ json: [String: Any]) -> Found? {
        if json["instrumental"] as? Bool == true {
            return Found(lines: [], plain: "♪ Instrumental ♪")
        }
        let synced = (json["syncedLyrics"] as? String).map(parseLRC) ?? []
        let plain = (json["plainLyrics"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if synced.isEmpty && plain == nil { return nil }
        return Found(lines: synced, plain: plain)
    }

    private static let timestamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)

    /// Parses "[mm:ss.xx] line" text. A line may carry several timestamps.
    static func parseLRC(_ text: String) -> [LyricLine] {
        var entries: [(time: TimeInterval, text: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw as NSString
            let matches = timestamp.matches(in: raw, range: NSRange(location: 0, length: line.length))
            guard let last = matches.last else { continue }
            let lyric = line.substring(from: last.range.location + last.range.length)
                .trimmingCharacters(in: .whitespaces)
            for match in matches {
                let minutes = Double(line.substring(with: match.range(at: 1))) ?? 0
                let seconds = Double(line.substring(with: match.range(at: 2))
                    .replacingOccurrences(of: ":", with: ".")) ?? 0
                entries.append((minutes * 60 + seconds, lyric))
            }
        }
        return entries
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text) }
    }
}
