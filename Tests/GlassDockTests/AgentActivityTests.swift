import XCTest
@testable import GlassDock

final class AgentTranscriptTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func claude(_ lines: [String]) -> AgentTranscript {
        var transcript = AgentTranscript(id: "claude", agent: .claude)
        lines.forEach { transcript.apply($0, receivedAt: now) }
        return transcript
    }

    private func codex(_ lines: [String]) -> AgentTranscript {
        var transcript = AgentTranscript(id: "codex", agent: .codex)
        lines.forEach { transcript.apply($0, receivedAt: now) }
        return transcript
    }

    private let prompt = #"{"type":"user","cwd":"/Users/me/Projects/demo-app","message":{"role":"user","content":"Fix the bug"}}"#
    private let thinking = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":""}],"stop_reason":"tool_use"}}"#
    private let editCall = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/Users/me/Projects/demo-app/Sources/KeyboardSoundController.swift","old_string":"a\nb","new_string":"a\nc\nd"}}],"stop_reason":"tool_use"}}"#
    private let editResult = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"toolUseResult":{"structuredPatch":[{"oldStart":1,"oldLines":2,"newStart":1,"newLines":3,"lines":[" a","-b","+c","+d"]}]}}"#
    private let endTurn = #"{"type":"assistant","timestamp":"2027-01-15T08:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":""}],"stop_reason":"end_turn"}}"#

    private func toolCall(_ id: String, _ name: String, _ input: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":""# + id + #"","name":""# + name
            + #"","input":"# + input + #"}],"stop_reason":"tool_use"}}"#
    }

    private func toolResult(_ id: String, isError: Bool = false) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":""# + id
            + #"","is_error":\#(isError),"content":""}]}}"#
    }

    func testClaudePromptStartsThinkingInTheProject() {
        let session = claude([prompt]).session
        XCTAssertEqual(session.phase, .thinking)
        XCTAssertEqual(session.project, "demo-app")
        XCTAssertEqual(session.status, "Thinking")
    }

    func testClaudeEditShowsTheFileThenCountsThePatch() {
        var transcript = claude([prompt, thinking, editCall])
        XCTAssertEqual(transcript.session.status, "Editing KeyboardSoundController.swift")

        transcript.apply(editResult, receivedAt: now)
        XCTAssertEqual(transcript.session.phase, .thinking)
        XCTAssertEqual(transcript.session.linesAdded, 2)
        XCTAssertEqual(transcript.session.linesRemoved, 1)
    }

    func testClaudeCountsToolInputsWhenTheResultHasNoPatch() {
        let write = toolCall("t2", "Write", #"{"file_path":"/tmp/README.md","content":"one\ntwo\nthree\n"}"#)
        let session = claude([prompt, editCall, toolResult("t1"), write, toolResult("t2")]).session
        XCTAssertEqual(session.linesAdded, 3 + 3)
        XCTAssertEqual(session.linesRemoved, 2)
    }

    func testClaudeCountsANewFileFromTheCreateResult() {
        let write = toolCall("t2", "Write", #"{"file_path":"/tmp/New.swift","content":"x"}"#)
        let result = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":""}]},"toolUseResult":{"type":"create","content":"a\nb\nc\nd","structuredPatch":[]}}"#
        XCTAssertEqual(claude([prompt, write, result]).session.linesAdded, 4)
    }

    func testClaudeFailedToolCountsNothing() {
        let session = claude([prompt, editCall, toolResult("t1", isError: true)]).session
        XCTAssertEqual(session.linesAdded, 0)
        XCTAssertEqual(session.linesRemoved, 0)
    }

    func testClaudeToolActivities() {
        let bash = toolCall("b", "Bash", #"{"command":"swift test --filter AgentTranscriptTests --parallel\nexit"}"#)
        XCTAssertEqual(claude([prompt, bash]).session.status, "Running swift test --filter AgentTranscriptTests…")
        XCTAssertEqual(claude([prompt, toolCall("r", "Read", #"{"file_path":"/x/README.md"}"#)]).session.status, "Reading README.md")
        XCTAssertEqual(claude([prompt, toolCall("g", "Grep", #"{"pattern":"x"}"#)]).session.status, "Searching")
        XCTAssertEqual(claude([prompt, toolCall("m", "mcp__docs__lookup", "{}")]).session.status, "Using lookup")
    }

    func testClaudeWaitsForAnAnswerUntilTheQuestionIsAnswered() {
        var transcript = claude([prompt, toolCall("q", "AskUserQuestion", #"{"questions":[]}"#)])
        XCTAssertEqual(transcript.session.phase, .waiting)
        XCTAssertEqual(transcript.session.status, "Waiting for you")

        transcript.apply(toolResult("q"), receivedAt: now)
        XCTAssertEqual(transcript.session.phase, .thinking)
        XCTAssertEqual(claude([prompt, toolCall("p", "ExitPlanMode", "{}")]).session.phase, .waiting)
    }

    func testClaudeEndTurnIsDoneAtTheRecordTime() {
        let session = claude([prompt, editCall, editResult, endTurn]).session
        XCTAssertEqual(session.phase, .done)
        XCTAssertEqual(session.updatedAt, AIUsageService.parseDate("2027-01-15T08:00:00.000Z"))
        XCTAssertEqual(session.linesAdded, 2)
    }

    func testClaudeNewPromptResetsTheTurnAndInterruptGoesIdle() {
        var transcript = claude([prompt, editCall, editResult, endTurn, prompt])
        XCTAssertEqual(transcript.session.phase, .thinking)
        XCTAssertEqual(transcript.session.linesAdded, 0)

        transcript.apply(#"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#,
                         receivedAt: now)
        XCTAssertEqual(transcript.session.phase, .idle)
    }

    func testClaudeIgnoresCommandsMetaAndSidechainRecords() {
        let command = #"{"type":"user","message":{"role":"user","content":"<command-name>/model</command-name>"}}"#
        let meta = #"{"type":"user","isMeta":true,"message":{"role":"user","content":"Caveat"}}"#
        let sidechain = #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"tool_use","id":"s","name":"Read","input":{}}],"stop_reason":"tool_use"}}"#
        let session = claude([prompt, endTurn, command, meta, sidechain, "not json"]).session
        XCTAssertEqual(session.phase, .done)
    }

    func testCodexCommandPatchAndCompletion() {
        let meta = #"{"type":"session_meta","payload":{"cwd":"/Users/me/Projects/api-server"}}"#
        let started = #"{"type":"event_msg","payload":{"type":"task_started"}}"#
        let exec = #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","call_id":"c1","input":"const r = await tools.exec_command({cmd: \"npm test -- --watch=false\"});"}}"#
        let output = #"{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"c1","output":""}}"#
        let change = #"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"FileChange","changes":{"/a/app.ts":{"type":"update","unified_diff":"--- a\n+++ b\n@@\n-x\n+y\n+z"},"/a/new.ts":{"type":"add","content":"1\n2\n"}}}}}"#
        let complete = #"{"type":"event_msg","payload":{"type":"task_complete"}}"#

        var transcript = codex([meta, started, exec])
        XCTAssertEqual(transcript.session.project, "api-server")
        XCTAssertEqual(transcript.session.status, "Running npm test -- --watch=false")

        transcript.apply(output, receivedAt: now)
        transcript.apply(change, receivedAt: now)
        XCTAssertEqual(transcript.session.phase, .thinking)
        XCTAssertEqual(transcript.session.linesAdded, 4)
        XCTAssertEqual(transcript.session.linesRemoved, 1)

        transcript.apply(complete, receivedAt: now)
        XCTAssertEqual(transcript.session.phase, .done)
    }

    func testCodexDirectPatchIsCountedOnce() {
        let patch = #"*** Begin Patch\n*** Update File: src/main.rs\n@@\n-old\n+new\n*** End Patch"#
        let call = #"{"type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","call_id":"p1","input":""# + patch + #""}}"#
        let output = #"{"type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"p1","output":""}}"#
        let change = #"{"type":"event_msg","payload":{"type":"item_completed","item":{"type":"FileChange","changes":{"src/main.rs":{"type":"update","unified_diff":"-old\n+new"}}}}}"#

        var transcript = codex([call])
        XCTAssertEqual(transcript.session.status, "Editing main.rs")
        transcript.apply(output, receivedAt: now)
        transcript.apply(change, receivedAt: now)
        XCTAssertEqual(transcript.session.linesAdded, 1)
        XCTAssertEqual(transcript.session.linesRemoved, 1)
    }

    func testCodexShellCallAndAbort() {
        let shell = #"{"type":"response_item","payload":{"type":"function_call","name":"shell","call_id":"s1","arguments":"{\"command\":[\"bash\",\"-lc\",\"cargo build\"]}"}}"#
        var transcript = codex([shell])
        XCTAssertEqual(transcript.session.status, "Running cargo build")
        transcript.apply(#"{"type":"event_msg","payload":{"type":"turn_aborted"}}"#, receivedAt: now)
        XCTAssertEqual(transcript.session.phase, .idle)
    }

    func testVisibilityAndOrder() {
        var done = AgentSession(id: "done", agent: .claude, phase: .done, updatedAt: now)
        var working = AgentSession(id: "working", agent: .codex, phase: .working("Searching"), updatedAt: now.addingTimeInterval(-10))
        let waiting = AgentSession(id: "waiting", agent: .claude, phase: .waiting, updatedAt: now.addingTimeInterval(-60))
        let idle = AgentSession(id: "idle", agent: .claude, phase: .idle, updatedAt: now)

        XCTAssertEqual(AgentSession.visible([done, working, waiting, idle], at: now.addingTimeInterval(3)).map(\.id),
                       ["waiting", "done", "working"])
        XCTAssertEqual(AgentSession.visible([done, working, waiting, idle], at: now.addingTimeInterval(5)).map(\.id),
                       ["waiting", "working"])

        done.updatedAt = .distantPast
        working.updatedAt = now.addingTimeInterval(-AgentSession.activeSeconds)
        XCTAssertTrue(AgentSession.visible([done, working], at: now).isEmpty)
    }

    func testAccessibilityLabel() {
        let session = AgentSession(id: "a", agent: .claude, project: "nock", phase: .working("Reading README.md"),
                                   linesAdded: 12, linesRemoved: 3)
        XCTAssertEqual(session.accessibilityLabel, "Claude Code in nock: Reading README.md, 12 lines added, 3 removed")
    }
}

final class AgentLogTailTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID().uuidString).jsonl")
        try Data().write(to: url)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func append(_ text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    func testReadsOnlyNewCompleteLines() throws {
        var tail = AgentLogTail(url: url)
        try append("{\"a\":1}\n{\"b\":")
        XCTAssertEqual(tail.read()?.lines, ["{\"a\":1}"])

        XCTAssertEqual(tail.read()?.lines, [])
        try append("2}\n{\"c\":3}\n")
        XCTAssertEqual(tail.read()?.lines, ["{\"b\":2}", "{\"c\":3}"])
    }

    func testStartsOverWhenTheFileShrinks() throws {
        var tail = AgentLogTail(url: url)
        try append("first line\nsecond line\n")
        XCTAssertEqual(tail.read()?.restarted, false)

        try Data("new\n".utf8).write(to: url)
        let chunk = try XCTUnwrap(tail.read())
        XCTAssertTrue(chunk.restarted)
        XCTAssertEqual(chunk.lines, ["new"])
    }

    func testFirstReadOfALargeFileStartsAtACompleteLineNearTheEnd() throws {
        let line = String(repeating: "x", count: 99) + "\n"
        let count = Int(AgentLogTail.firstReadLimit) / line.utf8.count + 10
        try Data((String(repeating: line, count: count) + "last\n").utf8).write(to: url)

        var tail = AgentLogTail(url: url)
        let lines = try XCTUnwrap(tail.read()).lines
        XCTAssertEqual(lines.last, "last")
        XCTAssertLessThan(lines.count, count)
        XCTAssertTrue(lines.dropLast().allSatisfy { $0.count == 99 })
    }

    func testMissingFileReadsNil() throws {
        var tail = AgentLogTail(url: url.appendingPathExtension("gone"))
        XCTAssertNil(tail.read())
    }
}
