import Foundation

/// Reads Claude Code and Codex usage from their local log files. Nothing is sent anywhere.
///  - Claude Code: ~/.claude/projects/**/*.jsonl (token usage per reply)
///  - Codex: ~/.codex/sessions/**/*.jsonl (token counts, plus rate-limit percentages when present)
final class AIUsageService: ObservableObject {
    struct ToolUsage {
        /// Tokens in the current 5-hour window (Claude Code).
        var windowTokens = 0
        var windowResets: Date?
        var todayTokens = 0
        var todayRequests = 0
        var lastActivity: Date?
        /// Codex's own limit figures, when its logs include them.
        var primaryPercent: Double?
        var primaryResets: Date?
        var weeklyPercent: Double?
        var weeklyResets: Date?
        var plan: String?
    }

    @Published private(set) var claude: ToolUsage?
    @Published private(set) var codex: ToolUsage?
    /// Claude Code plan limits from Anthropic; only loaded when turned on in Settings.
    @Published private(set) var claudeLimits: ClaudeLimits.Result?
    @Published private(set) var claudeLimitsMessage: String?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    private var timer: Timer?

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshClaudeLimits() {
        guard DockSettings.shared.claudeLimitsEnabled else {
            claudeLimits = nil
            claudeLimitsMessage = nil
            return
        }
        ClaudeLimits.fetch { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let limits):
                    self?.claudeLimits = limits
                    self?.claudeLimitsMessage = nil
                case .failure(let failure):
                    self?.claudeLimitsMessage = failure.message
                }
            }
        }
    }

    func refresh() {
        refreshClaudeLimits()
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .utility).async {
            let claude = Self.loadClaude()
            let codex = Self.loadCodex()
            DispatchQueue.main.async {
                self.claude = claude
                self.codex = codex
                self.isLoading = false
                self.hasLoaded = true
            }
        }
    }

    // MARK: Claude Code

    private static func loadClaude() -> ToolUsage? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let now = Date()
        let since = now.addingTimeInterval(-30 * 3600)
        var seen = Set<String>()
        var entries: [(date: Date, tokens: Int)] = []

        for file in recentFiles(in: root, since: since) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let date = parseDate(object["timestamp"] as? String), date >= since else { continue }

                // Streaming writes the same reply more than once; count each reply once.
                let key = "\(message["id"] as? String ?? "")|\(object["requestId"] as? String ?? "")"
                if key != "|", !seen.insert(key).inserted { continue }

                let tokens = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
                    .reduce(0) { $0 + ((usage[$1] as? NSNumber)?.intValue ?? 0) }
                entries.append((date, tokens))
            }
        }

        var result = ToolUsage()
        let startOfDay = Calendar.current.startOfDay(for: now)
        for entry in entries where entry.date >= startOfDay {
            result.todayTokens += entry.tokens
            result.todayRequests += 1
        }
        result.lastActivity = entries.map(\.date).max()

        // A 5-hour window starts at the hour of its first message.
        var windowStart: Date?
        var windowTokens = 0
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            if let start = windowStart, entry.date < start.addingTimeInterval(5 * 3600) {
                windowTokens += entry.tokens
            } else {
                windowStart = Calendar.current.dateInterval(of: .hour, for: entry.date)?.start ?? entry.date
                windowTokens = entry.tokens
            }
        }
        if let start = windowStart, now < start.addingTimeInterval(5 * 3600) {
            result.windowTokens = windowTokens
            result.windowResets = start.addingTimeInterval(5 * 3600)
        }
        return result
    }

    // MARK: Codex

    private static func loadCodex() -> ToolUsage? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let now = Date()
        let since = now.addingTimeInterval(-30 * 3600)
        var entries: [(date: Date, tokens: Int)] = []
        var latestLimits: (date: Date, limits: [String: Any])?

        for file in recentFiles(in: root, since: since) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("token_count") {
                guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let payload = object["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let date = parseDate(object["timestamp"] as? String) else { continue }

                if date >= since,
                   let info = payload["info"] as? [String: Any],
                   let last = info["last_token_usage"] as? [String: Any],
                   let total = (last["total_tokens"] as? NSNumber)?.intValue {
                    entries.append((date, total))
                }
                if let limits = payload["rate_limits"] as? [String: Any],
                   latestLimits.map({ date > $0.date }) ?? true {
                    latestLimits = (date, limits)
                }
            }
        }

        var result = ToolUsage()
        let startOfDay = Calendar.current.startOfDay(for: now)
        for entry in entries where entry.date >= startOfDay {
            result.todayTokens += entry.tokens
            result.todayRequests += 1
        }
        result.lastActivity = entries.map(\.date).max()

        if let latestLimits {
            func window(_ key: String) -> (Double?, Date?) {
                guard let window = latestLimits.limits[key] as? [String: Any] else { return (nil, nil) }
                let percent = (window["used_percent"] as? NSNumber)?.doubleValue
                var resets: Date?
                if let at = (window["resets_at"] as? NSNumber)?.doubleValue {
                    resets = Date(timeIntervalSince1970: at)
                } else if let seconds = (window["resets_in_seconds"] as? NSNumber)?.doubleValue {
                    resets = latestLimits.date.addingTimeInterval(seconds)
                }
                // The window has reset since the last log entry.
                if let resets, resets < now { return (0, nil) }
                return (percent, resets)
            }
            (result.primaryPercent, result.primaryResets) = window("primary")
            (result.weeklyPercent, result.weeklyResets) = window("secondary")
            if let plan = latestLimits.limits["plan_type"] as? String, !plan.isEmpty {
                result.plan = plan.prefix(1).uppercased() + plan.dropFirst()
            }
        }
        return result
    }

    // MARK: Helpers

    private static func recentFiles(in root: URL, since: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if let modified, modified >= since { files.append(url) }
        }
        return files
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plainFormatter = ISO8601DateFormatter()

    private static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractionalFormatter.date(from: string) ?? plainFormatter.date(from: string)
    }

    static func formatTokens(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}
