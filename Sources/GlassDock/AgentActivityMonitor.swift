import Combine
import Foundation

final class AgentActivityMonitor: ObservableObject {
    private struct WatchedLog {
        var tail: AgentLogTail
        var transcript: AgentTranscript
    }

    private static let pollSeconds = 1
    private static let rescanEveryPolls = 5
    private static let codexDayFolders = 2

    @Published private(set) var sessions: [AgentSession] = []

    var lead: AgentSession? { sessions.first }

    private let settings: DockSettings
    private let queue = DispatchQueue(label: "GlassDock.AgentActivity", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var isIslandShown = false
    private var settingObserver: AnyCancellable?
    private var logs: [URL: WatchedLog] = [:]
    private var polls = 0

    init(settings: DockSettings) {
        self.settings = settings
        settingObserver = settings.$showAgentActivity
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
    }

    func start() {
        isIslandShown = true
        refresh()
    }

    func stop() {
        isIslandShown = false
        refresh()
    }

    private func refresh() {
        let isOn = isIslandShown && settings.showAgentActivity
        if isOn, timer == nil {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: .seconds(Self.pollSeconds), leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.poll() }
            timer.resume()
            self.timer = timer
        } else if !isOn, let timer {
            timer.cancel()
            self.timer = nil
            queue.async { [weak self] in
                self?.logs = [:]
                self?.polls = 0
            }
            sessions = []
        }
    }

    private func poll() {
        let now = Date()
        if polls % Self.rescanEveryPolls == 0 {
            let since = now.addingTimeInterval(-AgentSession.activeSeconds)
            for (url, agent) in Self.recentLogs(since: since, now: now) where logs[url] == nil {
                logs[url] = WatchedLog(tail: AgentLogTail(url: url), transcript: AgentTranscript(id: url.path, agent: agent))
            }
        }
        polls += 1

        for (url, var log) in logs {
            guard let chunk = log.tail.read(), now.timeIntervalSince(chunk.modified) < AgentSession.activeSeconds else {
                logs[url] = nil
                continue
            }
            if chunk.restarted {
                log.transcript = AgentTranscript(id: url.path, agent: log.transcript.session.agent)
            }
            chunk.lines.forEach { log.transcript.apply($0, receivedAt: chunk.modified) }
            logs[url] = log
        }

        let visible = AgentSession.visible(logs.values.map(\.transcript.session), at: now)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.timer != nil, self.sessions != visible else { return }
            self.sessions = visible
        }
    }

    private static func recentLogs(since: Date, now: Date) -> [(URL, CodingAgent)] {
        let claude = AIUsageService.claudeProjectRoots()
            .flatMap { root in
                ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
                    .flatMap { AIUsageService.recentFiles(in: $0, since: since, includingSubfolders: false) }
            }
            .map { ($0, CodingAgent.claude) }

        let calendar = Calendar.current
        let codex = (0..<codexDayFolders)
            .compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
            .map { day -> URL in
                let parts = calendar.dateComponents([.year, .month, .day], from: day)
                return AIUsageService.codexSessionsRoot.appendingPathComponent(
                    String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
            }
            .flatMap { AIUsageService.recentFiles(in: $0, since: since, includingSubfolders: false) }
            .filter { $0.lastPathComponent.hasPrefix("rollout-") }
            .map { ($0, CodingAgent.codex) }

        return claude + codex
    }
}
