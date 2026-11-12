import AppKit
import SwiftUI

/// The Island's Notes tab, backed by the Notes app on this Mac (via AppleScript).
///
/// Editing is only allowed for plain-text notes. Notes with formatting, checklists, tables, links or
/// attachments are shown read-only, because rewriting them from plain text would lose that content.
final class NotesStore: ObservableObject {
    struct Note: Identifiable, Equatable {
        let id: String
        var title: String
        var snippet: String
        var modified: Date
    }

    enum Status: Equatable {
        case idle, loading, ready, denied, failed(String)
    }

    enum EditorState: Equatable {
        case loading, saved, saving, readOnly, failed
    }

    @Published private(set) var notes: [Note] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var selectedID: String?
    @Published var draft = ""
    @Published private(set) var editorState: EditorState = .loading
    @Published private(set) var pinned: [String]

    private let queue = DispatchQueue(label: "GlassDock.Notes")
    private var saveWork: DispatchWorkItem?
    private var loadedText = ""
    private let pinnedKey = "pinnedNotes"
    private let legacyKey = "islandNotes"
    private static let recordSeparator = "\u{1E}"
    private static let fieldSeparator = "\u{1F}"

    init() {
        pinned = UserDefaults.standard.stringArray(forKey: pinnedKey) ?? []
    }

    var isEditable: Bool { editorState == .saved || editorState == .saving }

    /// Pinned first (pins are kept by GlassDock), then most recently edited.
    var sortedNotes: [Note] {
        notes.sorted { a, b in
            let pinA = pinned.contains(a.id), pinB = pinned.contains(b.id)
            if pinA != pinB { return pinA }
            return a.modified > b.modified
        }
    }

    // MARK: Loading

    func reload() {
        if status != .ready { status = .loading }
        // Two Apple Events in total: every note's ID and its age in seconds.
        let listScript = """
        tell application "Notes"
            set noteIDs to id of every note
            set noteDates to modification date of every note
        end tell
        set nowDate to current date
        set output to {}
        repeat with i from 1 to count of noteIDs
            set end of output to (item i of noteIDs) & tab & ((nowDate - (item i of noteDates)) as text)
        end repeat
        set AppleScript's text item delimiters to linefeed
        return output as text
        """
        run(listScript) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.status = error.isPermission ? .denied : .failed(error.message)
            case .success(let descriptor):
                let recent = (descriptor.stringValue ?? "")
                    .split(separator: "\n")
                    .compactMap { line -> (id: String, age: Double)? in
                        let parts = line.split(separator: "\t")
                        guard parts.count == 2, let age = Double(parts[1]) else { return nil }
                        return (String(parts[0]), age)
                    }
                    .sorted { $0.age < $1.age }
                let wanted = Array(Set(recent.prefix(40).map(\.id) + self.pinned))
                self.loadDetails(ids: wanted)
            }
        }
    }

    private func loadDetails(ids: [String]) {
        guard !ids.isEmpty else {
            notes = []
            status = .ready
            migrateLegacyNote()
            return
        }
        let list = ids.map { "\"\(Self.escape($0))\"" }.joined(separator: ", ")
        let script = """
        set nowDate to current date
        set output to {}
        tell application "Notes"
            repeat with theID in {\(list)}
                try
                    set n to note id theID
                    if name of container of n is not "Recently Deleted" then
                        set t to plaintext of n
                        if length of t > 200 then set t to text 1 thru 200 of t
                        set end of output to (theID as text) & (character id 31) & (name of n) & (character id 31) & ((nowDate - (modification date of n)) as text) & (character id 31) & t
                    end if
                end try
            end repeat
        end tell
        set AppleScript's text item delimiters to (character id 30)
        return output as text
        """
        run(script) { [weak self] result in
            guard let self else { return }
            guard case .success(let descriptor) = result else {
                if case .failure(let error) = result { self.status = .failed(error.message) }
                return
            }
            let now = Date()
            self.notes = (descriptor.stringValue ?? "")
                .components(separatedBy: Self.recordSeparator)
                .compactMap { record -> Note? in
                    let fields = record.components(separatedBy: Self.fieldSeparator)
                    guard fields.count >= 4, let age = Double(fields[2]) else { return nil }
                    return Note(id: fields[0], title: fields[1].isEmpty ? "New Note" : fields[1],
                                snippet: Self.snippet(from: fields[3]), modified: now.addingTimeInterval(-age))
                }
            self.status = .ready
            if let selected = self.selectedID, self.notes.contains(where: { $0.id == selected }) {
                // Keep the open note.
            } else if let first = self.sortedNotes.first {
                self.select(first.id)
            } else {
                self.selectedID = nil
            }
            self.migrateLegacyNote()
        }
    }

    func select(_ id: String) {
        flushSave()
        selectedID = id
        editorState = .loading
        loadedText = ""
        draft = ""
        let script = """
        tell application "Notes"
            set n to note id "\(Self.escape(id))"
            return (body of n) & (character id 30) & (plaintext of n) & (character id 30) & ((count of attachments of n) as text)
        end tell
        """
        run(script) { [weak self] result in
            guard let self, self.selectedID == id else { return }
            switch result {
            case .failure:
                self.editorState = .failed
            case .success(let descriptor):
                let parts = (descriptor.stringValue ?? "").components(separatedBy: Self.recordSeparator)
                guard parts.count >= 3 else { self.editorState = .failed; return }
                let attachments = Int(parts[2].trimmingCharacters(in: .whitespaces)) ?? 0
                self.loadedText = parts[1]
                self.draft = parts[1]
                self.editorState = attachments == 0 && Self.isPlainNote(html: parts[0]) ? .saved : .readOnly
            }
        }
    }

    // MARK: Editing

    /// Called as the user types; saves to Notes shortly after they pause.
    func draftChanged() {
        guard isEditable, let id = selectedID, draft != loadedText else { return }
        saveWork?.cancel()
        editorState = .saving
        let text = draft
        let work = DispatchWorkItem { [weak self] in self?.save(text, to: id) }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// Saves any pending edit right away (when switching notes or closing the island).
    func flushSave() {
        guard let work = saveWork else { return }
        saveWork = nil
        work.perform()
        work.cancel()
    }

    private func save(_ text: String, to id: String) {
        saveWork = nil
        let script = """
        tell application "Notes"
            set body of note id "\(Self.escape(id))" to "\(Self.escape(Self.html(from: text)))"
        end tell
        """
        run(script) { [weak self] result in
            guard let self else { return }
            if case .failure = result {
                if self.selectedID == id { self.editorState = .failed }
                return
            }
            if self.selectedID == id {
                self.loadedText = text
                if self.draft == text { self.editorState = .saved }
            }
            if let index = self.notes.firstIndex(where: { $0.id == id }) {
                let firstLine = text.components(separatedBy: "\n").first ?? ""
                self.notes[index].title = firstLine.isEmpty ? "New Note" : firstLine
                self.notes[index].snippet = Self.snippet(from: text)
                self.notes[index].modified = Date()
            }
        }
    }

    func createNote() {
        flushSave()
        create(text: "New Note") { [weak self] id in
            self?.selectedID = id
            self?.reload()
            if let id { self?.select(id) }
        }
    }

    private func create(text: String, completion: @escaping (String?) -> Void) {
        let script = """
        tell application "Notes"
            set n to make new note at default folder of default account with properties {body:"\(Self.escape(Self.html(from: text)))"}
            return id of n
        end tell
        """
        run(script) { result in
            if case .success(let descriptor) = result { completion(descriptor.stringValue) } else { completion(nil) }
        }
    }

    /// Moves the note to Notes' Recently Deleted folder, where it can be recovered.
    func deleteSelected() {
        guard let id = selectedID else { return }
        saveWork?.cancel()
        saveWork = nil
        run("tell application \"Notes\" to delete note id \"\(Self.escape(id))\"") { [weak self] result in
            guard let self, case .success = result else { return }
            self.notes.removeAll { $0.id == id }
            self.pinned.removeAll { $0 == id }
            UserDefaults.standard.set(self.pinned, forKey: self.pinnedKey)
            self.selectedID = nil
            if let next = self.sortedNotes.first { self.select(next.id) }
        }
    }

    func togglePin() {
        guard let id = selectedID else { return }
        if pinned.contains(id) { pinned.removeAll { $0 == id } } else { pinned.insert(id, at: 0) }
        UserDefaults.standard.set(pinned, forKey: pinnedKey)
    }

    func openInNotes() {
        guard let id = selectedID else { return }
        flushSave()
        run("""
        tell application "Notes"
            show note id "\(Self.escape(id))"
            activate
        end tell
        """) { _ in }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Moves the text from GlassDock's earlier built-in notepad into a real note, once.
    private func migrateLegacyNote() {
        guard let text = UserDefaults.standard.string(forKey: legacyKey) else { return }
        UserDefaults.standard.removeObject(forKey: legacyKey)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        create(text: "GlassDock Note\n" + text) { [weak self] _ in self?.reload() }
    }

    // MARK: Helpers

    struct ScriptError: Error {
        let number: Int
        let message: String
        /// -1743: the user hasn't allowed GlassDock to control Notes.
        var isPermission: Bool { number == -1743 || number == -1744 }
    }

    private func run(_ source: String, completion: @escaping (Result<NSAppleEventDescriptor, ScriptError>) -> Void) {
        queue.async {
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let result: Result<NSAppleEventDescriptor, ScriptError>
            if let error {
                result = .failure(ScriptError(number: error[NSAppleScript.errorNumber] as? Int ?? 0,
                                              message: error[NSAppleScript.errorMessage] as? String ?? "Unknown error"))
            } else {
                result = .success(descriptor ?? NSAppleEventDescriptor.null())
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The first non-empty line after the title.
    private static func snippet(from text: String) -> String {
        text.components(separatedBy: .newlines)
            .dropFirst()
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// First line becomes the note's title; the rest become plain lines.
    static func html(from text: String) -> String {
        text.components(separatedBy: "\n").enumerated().map { index, line in
            let escaped = line
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            if index == 0 { return "<div><h1>\(escaped.isEmpty ? "New Note" : escaped)</h1></div>" }
            return escaped.isEmpty ? "<div><br></div>" : "<div>\(escaped)</div>"
        }.joined()
    }

    /// True when the note (apart from its title line) is plain text, so editing it as text loses nothing.
    static func isPlainNote(html: String) -> Bool {
        var rest = html.lowercased()
        if let titleEnd = rest.range(of: "</div>") { rest = String(rest[titleEnd.upperBound...]) }
        let richTags = ["<b>", "<b ", "<i>", "<u>", "<strike", "<ul", "<ol", "<li", "<table", "<img", "<a ",
                        "<object", "<h1", "<h2", "<h3", "<span", "<font", "<tt", "<pre", "<blockquote"]
        return !richTags.contains { rest.contains($0) }
    }
}

// MARK: - Notes tab

struct NotesTab: View {
    @ObservedObject var notes: NotesStore

    var body: some View {
        Group {
            switch notes.status {
            case .denied:
                VStack(spacing: 10) {
                    Text("GlassDock needs permission to use Notes")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Button("Open Settings") { notes.openAutomationSettings() }
                        .buttonStyle(IslandButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                IslandMessage(text: "Couldn't read Notes: \(message)", systemImage: "exclamationmark.triangle")
            case .idle, .loading:
                if notes.notes.isEmpty {
                    IslandMessage(text: "Loading Notes…", spinner: true)
                } else {
                    content
                }
            case .ready:
                content
            }
        }
        .onAppear { notes.reload() }
        .onDisappear { notes.flushSave() }
    }

    private var content: some View {
        HStack(spacing: 14) {
            sidebar.frame(width: 230)
            editor
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                (Text("Notes").fontWeight(.semibold) + Text(" \(notes.notes.count)").foregroundColor(.secondary))
                    .font(.system(size: 14))
                Spacer()
                Button { notes.createNote() } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .hoverLabel("New note", edge: .bottom, anchor: .trailing)
            }
            .padding(.horizontal, 10)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(notes.sortedNotes) { note in
                        row(note)
                    }
                }
            }
        }
    }

    private func row(_ note: NotesStore.Note) -> some View {
        let selected = note.id == notes.selectedID
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if notes.pinned.contains(note.id) {
                    Image(systemName: "pin.fill").font(.system(size: 9))
                }
                Text(note.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            Text([Self.dateLabel(note.modified), note.snippet].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.white.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { notes.select(note.id) }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            if notes.selectedID == nil {
                IslandMessage(text: "No notes yet — create one with the pencil button")
            } else if notes.isEditable {
                TextEditor(text: $notes.draft)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .onChange(of: notes.draft) { notes.draftChanged() }
            } else {
                ScrollView {
                    Text(notes.draft)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Text(footerText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if notes.selectedID != nil {
                    footerButton("arrow.up.forward.app", help: "Open in Notes") { notes.openInNotes() }
                    footerButton(notes.pinned.contains(notes.selectedID ?? "") ? "pin.slash" : "pin",
                                 help: notes.pinned.contains(notes.selectedID ?? "") ? "Unpin" : "Pin") { notes.togglePin() }
                    footerButton("trash", help: "Delete") { notes.deleteSelected() }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var footerText: String {
        switch notes.editorState {
        case .loading: return "Loading…"
        case .saving: return "Saving…"
        case .saved: return "Saved to Notes as you type"
        case .readOnly: return "Has formatting or attachments — edit it in Notes"
        case .failed: return "Couldn't open this note"
        }
    }

    private func footerButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .hoverLabel(help, edge: .top, anchor: symbol == "trash" ? .trailing : .center)
    }

    private static func dateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
