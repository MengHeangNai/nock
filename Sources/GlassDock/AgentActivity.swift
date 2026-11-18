import Foundation

enum CodingAgent {
    case claude, codex

    var title: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var symbol: String {
        switch self {
        case .claude: return "asterisk"
        case .codex: return "terminal"
        }
    }
}

struct AgentSession: Equatable, Identifiable {
    enum Phase: Equatable {
        case idle
        case thinking
        case working(String)
        case waiting
        case done
    }

    static let activeSeconds: TimeInterval = 120
    static let doneSeconds: TimeInterval = 4

    let id: String
    let agent: CodingAgent
    var project = ""
    var phase = Phase.idle
    var linesAdded = 0
    var linesRemoved = 0
    var updatedAt = Date.distantPast

    var isWaiting: Bool { phase == .waiting }
    var hasLineChanges: Bool { linesAdded > 0 || linesRemoved > 0 }

    var status: String {
        switch phase {
        case .idle: return ""
        case .thinking: return "Thinking"
        case .working(let activity): return activity
        case .waiting: return "Waiting for you"
        case .done: return "Done"
        }
    }

    var accessibilityLabel: String {
        var label = agent.title + (project.isEmpty ? "" : " in \(project)") + ": " + status
        if hasLineChanges {
            label += ", \(linesAdded) lines added, \(linesRemoved) removed"
        }
        return label
    }

    func isVisible(at now: Date) -> Bool {
        let age = now.timeIntervalSince(updatedAt)
        switch phase {
        case .idle: return false
        case .done: return age < Self.doneSeconds
        case .thinking, .working, .waiting: return age < Self.activeSeconds
        }
    }

    static func visible(_ sessions: [AgentSession], at now: Date) -> [AgentSession] {
        sessions
            .filter { $0.isVisible(at: now) }
            .sorted { ($0.isWaiting ? 1 : 0, $0.updatedAt) > ($1.isWaiting ? 1 : 0, $1.updatedAt) }
    }
}

struct AgentTranscript {
    private struct PendingTool {
        let id: String
        let activity: String
        let isQuestion: Bool
        let lines: (added: Int, removed: Int)?
    }

    private static let commandLength = 40
    private static let questionTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    private(set) var session: AgentSession
    private var pending: [PendingTool] = []
    private var patchCountedBeforeFileChange = false

    init(id: String, agent: CodingAgent) {
        session = AgentSession(id: id, agent: agent)
    }

    mutating func apply(_ line: String, receivedAt: Date) {
        guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
        let changed: Bool
        switch session.agent {
        case .claude: changed = applyClaude(record)
        case .codex: changed = applyCodex(record)
        }
        if changed {
            session.updatedAt = AIUsageService.parseDate(record["timestamp"] as? String) ?? receivedAt
        }
    }

    private mutating func applyClaude(_ record: [String: Any]) -> Bool {
        if let cwd = record["cwd"] as? String { session.project = Self.lastComponent(cwd) }
        guard record["isSidechain"] as? Bool != true, record["isMeta"] as? Bool != true,
              let message = record["message"] as? [String: Any] else { return false }

        switch record["type"] as? String {
        case "assistant":
            for block in message["content"] as? [[String: Any]] ?? [] where block["type"] as? String == "tool_use" {
                let name = block["name"] as? String ?? ""
                let input = block["input"] as? [String: Any] ?? [:]
                pending.append(PendingTool(id: block["id"] as? String ?? "",
                                           activity: Self.claudeActivity(tool: name, input: input),
                                           isQuestion: Self.questionTools.contains(name),
                                           lines: Self.claudeLines(tool: name, input: input)))
            }
            let stopReason = message["stop_reason"] as? String
            if stopReason == "end_turn" || stopReason == "stop_sequence" {
                pending.removeAll()
                session.phase = .done
            } else {
                session.phase = pendingPhase
            }
            return true
        case "user":
            if let text = message["content"] as? String {
                return startTurn(prompt: text)
            }
            let blocks = message["content"] as? [[String: Any]] ?? []
            let results = blocks.filter { $0["type"] as? String == "tool_result" }
            guard !results.isEmpty else {
                return startTurn(prompt: blocks.first { $0["type"] as? String == "text" }?["text"] as? String ?? "")
            }
            for result in results {
                let id = result["tool_use_id"] as? String ?? ""
                let tool = pending.first { $0.id == id }
                pending.removeAll { $0.id == id }
                guard result["is_error"] as? Bool != true else { continue }
                if let lines = Self.resultLines(record["toolUseResult"] as? [String: Any]) ?? tool?.lines {
                    session.linesAdded += lines.added
                    session.linesRemoved += lines.removed
                }
            }
            session.phase = pendingPhase
            return true
        default:
            return false
        }
    }

    private mutating func startTurn(prompt: String) -> Bool {
        if prompt.hasPrefix("<") { return false }
        pending.removeAll()
        if prompt.hasPrefix("[Request interrupted") {
            session.phase = .idle
            return true
        }
        session.phase = .thinking
        session.linesAdded = 0
        session.linesRemoved = 0
        return true
    }

    private mutating func applyCodex(_ record: [String: Any]) -> Bool {
        guard let payload = record["payload"] as? [String: Any] else { return false }
        switch record["type"] as? String {
        case "session_meta", "turn_context":
            if let cwd = payload["cwd"] as? String { session.project = Self.lastComponent(cwd) }
            return false
        case "event_msg":
            return applyCodexEvent(payload)
        case "response_item":
            return applyCodexItem(payload)
        default:
            return false
        }
    }

    private mutating func applyCodexEvent(_ payload: [String: Any]) -> Bool {
        switch payload["type"] as? String {
        case "task_started":
            pending.removeAll()
            session.phase = .thinking
            session.linesAdded = 0
            session.linesRemoved = 0
        case "task_complete":
            pending.removeAll()
            session.phase = .done
        case "turn_aborted":
            pending.removeAll()
            session.phase = .idle
        case "item_completed":
            guard let item = payload["item"] as? [String: Any], item["type"] as? String == "FileChange" else { return false }
            if patchCountedBeforeFileChange {
                patchCountedBeforeFileChange = false
                return false
            }
            for change in (item["changes"] as? [String: Any] ?? [:]).values {
                guard let change = change as? [String: Any] else { continue }
                if let diff = change["unified_diff"] as? String {
                    let lines = Self.patchLines(diff)
                    session.linesAdded += lines.added
                    session.linesRemoved += lines.removed
                } else if let content = change["content"] as? String {
                    if change["type"] as? String == "delete" {
                        session.linesRemoved += Self.lineCount(content)
                    } else {
                        session.linesAdded += Self.lineCount(content)
                    }
                }
            }
        default:
            return false
        }
        return true
    }

    private mutating func applyCodexItem(_ payload: [String: Any]) -> Bool {
        switch payload["type"] as? String {
        case "function_call", "custom_tool_call", "local_shell_call":
            let name = payload["name"] as? String ?? "shell"
            let input = payload["input"] as? String ?? payload["arguments"] as? String ?? ""
            pending.append(PendingTool(id: payload["call_id"] as? String ?? "",
                                       activity: Self.codexActivity(tool: name, input: input),
                                       isQuestion: false,
                                       lines: name == "apply_patch" ? Self.patchLines(input) : nil))
        case "function_call_output", "custom_tool_call_output":
            let id = payload["call_id"] as? String ?? ""
            if let lines = pending.first(where: { $0.id == id })?.lines {
                session.linesAdded += lines.added
                session.linesRemoved += lines.removed
                patchCountedBeforeFileChange = true
            }
            pending.removeAll { $0.id == id }
        case "web_search_call":
            session.phase = .working("Searching")
            return true
        case "reasoning", "message":
            guard payload["role"] == nil || payload["role"] as? String == "assistant" else { return false }
        default:
            return false
        }
        session.phase = pendingPhase
        return true
    }

    private var pendingPhase: AgentSession.Phase {
        if pending.contains(where: \.isQuestion) { return .waiting }
        return pending.last.map { .working($0.activity) } ?? .thinking
    }

    private static func claudeActivity(tool: String, input: [String: Any]) -> String {
        let file = lastComponent(input["file_path"] as? String ?? input["notebook_path"] as? String ?? "")
        switch tool {
        case "Edit", "MultiEdit", "NotebookEdit": return phrase("Editing", file)
        case "Write": return phrase("Writing", file)
        case "Read": return phrase("Reading", file)
        case "Bash": return phrase("Running", shortCommand(input["command"] as? String ?? ""))
        case "Grep", "Glob", "WebSearch", "ToolSearch": return "Searching"
        case "WebFetch": return phrase("Fetching", URL(string: input["url"] as? String ?? "")?.host ?? "")
        case "Agent", "Task": return "Running an agent"
        case "TodoWrite": return "Planning"
        default: return "Using " + (tool.components(separatedBy: "__").last ?? tool)
        }
    }

    private static func codexActivity(tool: String, input: String) -> String {
        switch tool {
        case "shell", "local_shell", "container.exec", "exec_command":
            let arguments = (try? JSONSerialization.jsonObject(with: Data(input.utf8))) as? [String: Any] ?? [:]
            let command = arguments["cmd"] as? String
                ?? (arguments["command"] as? [String])?.last
                ?? arguments["command"] as? String ?? ""
            return phrase("Running", shortCommand(command))
        case "apply_patch":
            return phrase("Editing", patchFile(input))
        case "update_plan":
            return "Planning"
        case "exec":
            guard let call = input.firstMatch(of: #/tools\.(\w+)\(/#)?.output.1 else { return "Running code" }
            switch call {
            case "exec_command":
                let command = input.firstMatch(of: #/cmd\s*:\s*["'`]([^"'`]*)/#).map { String($0.output.1) } ?? ""
                return phrase("Running", shortCommand(command))
            case "apply_patch":
                return phrase("Editing", patchFile(input))
            case "web__run":
                return "Searching"
            default:
                return "Running code"
            }
        default:
            return "Using " + tool
        }
    }

    private static func shortCommand(_ command: String) -> String {
        let line = command.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let words = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return words.count > commandLength ? String(words.prefix(commandLength)) + "…" : words
    }

    private static func patchLines(_ patch: String) -> (added: Int, removed: Int) {
        var added = 0
        var removed = 0
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("+"), !line.hasPrefix("+++") { added += 1 }
            if line.hasPrefix("-"), !line.hasPrefix("---") { removed += 1 }
        }
        return (added, removed)
    }

    private static func lineCount(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count - (text.hasSuffix("\n") ? 1 : 0)
    }

    private static func claudeLines(tool: String, input: [String: Any]) -> (added: Int, removed: Int)? {
        switch tool {
        case "Edit":
            return (lineCount(input["new_string"] as? String ?? ""), lineCount(input["old_string"] as? String ?? ""))
        case "MultiEdit":
            let edits = input["edits"] as? [[String: Any]] ?? []
            return edits.reduce((0, 0)) { total, edit in
                (total.0 + lineCount(edit["new_string"] as? String ?? ""), total.1 + lineCount(edit["old_string"] as? String ?? ""))
            }
        case "Write":
            return (lineCount(input["content"] as? String ?? ""), 0)
        default:
            return nil
        }
    }

    private static func resultLines(_ result: [String: Any]?) -> (added: Int, removed: Int)? {
        guard let result else { return nil }
        if let hunks = result["structuredPatch"] as? [[String: Any]], !hunks.isEmpty {
            let lines = hunks.flatMap { $0["lines"] as? [String] ?? [] }
            return patchLines(lines.joined(separator: "\n"))
        }
        if result["type"] as? String == "create", let content = result["content"] as? String {
            return (lineCount(content), 0)
        }
        return nil
    }

    private static func patchFile(_ patch: String) -> String {
        guard let path = patch.firstMatch(of: #/\*\*\* (?:Update|Add|Delete) File: ([^\n\\"]+)/#)?.output.1 else { return "" }
        return lastComponent(String(path).trimmingCharacters(in: .whitespaces))
    }

    private static func phrase(_ verb: String, _ target: String) -> String {
        target.isEmpty ? verb : verb + " " + target
    }

    private static func lastComponent(_ path: String) -> String {
        path.isEmpty ? "" : (path as NSString).lastPathComponent
    }
}

struct AgentLogChunk {
    var lines: [String]
    var restarted: Bool
    var modified: Date
}

struct AgentLogTail {
    static let firstReadLimit: UInt64 = 2 << 20

    let url: URL
    private var offset: UInt64 = 0
    private var fileNumber: UInt64?
    private var partial = Data()

    init(url: URL) {
        self.url = url
    }

    mutating func read() -> AgentLogChunk? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value else { return nil }
        let number = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let modified = attributes[.modificationDate] as? Date ?? Date()

        var restarted = false
        var skipsFirstLine = false
        if fileNumber == nil || number != fileNumber || size < offset {
            restarted = fileNumber != nil
            offset = size > Self.firstReadLimit ? size - Self.firstReadLimit : 0
            skipsFirstLine = offset > 0
            partial = Data()
            fileNumber = number
        }
        guard size > offset, let handle = try? FileHandle(forReadingFrom: url) else {
            return AgentLogChunk(lines: [], restarted: restarted, modified: modified)
        }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.read(upToCount: Int(size - offset))) ?? Data()
        offset += UInt64(data.count)

        var buffer = partial + data
        if skipsFirstLine {
            buffer = buffer.firstIndex(of: 0x0A).map { buffer[buffer.index(after: $0)...] } ?? Data()
        }
        var pieces = buffer.split(separator: 0x0A, omittingEmptySubsequences: false)
        partial = Data(pieces.removeLast())
        let lines = pieces.compactMap { String(data: $0, encoding: .utf8) }.filter { !$0.isEmpty }
        return AgentLogChunk(lines: lines, restarted: restarted, modified: modified)
    }
}
