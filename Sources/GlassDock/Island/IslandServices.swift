import AppKit
import SwiftUI
import EventKit
import IOKit.pwr_mgt

// MARK: - Calendar

final class CalendarService: ObservableObject {
    enum Access { case notDetermined, granted, denied }

    struct Event: Identifiable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let calendarID: String
        let color: Color
        let meetingURL: URL?
    }

    @Published private(set) var access: Access
    @Published private(set) var weekEvents: [Event] = []
    /// Timed events that haven't ended yet, over the next two days.
    @Published private(set) var upcoming: [Event] = []

    private let store = EKEventStore()
    private var timer: Timer?

    init() {
        access = Self.currentAccess()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.reload() }
        reload()
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.access = granted ? .granted : .denied
                self?.reload()
            }
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    var weekDays: [Date] {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// Up to three calendar colors for the events on a day.
    func colors(on day: Date) -> [Color] {
        var seen = Set<String>()
        var colors: [Color] = []
        for event in weekEvents where Calendar.current.isDate(event.start, inSameDayAs: day) {
            if seen.insert(event.calendarID).inserted { colors.append(event.color) }
            if colors.count == 3 { break }
        }
        return colors
    }

    func reload() {
        guard access == .granted else {
            weekEvents = []
            upcoming = []
            return
        }
        let calendar = Calendar.current
        let now = Date()
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return }
        let end = max(weekEnd, now.addingTimeInterval(2 * 86400))
        let predicate = store.predicateForEvents(withStart: weekStart, end: end, calendars: nil)
        let events = store.events(matching: predicate).map(Self.convert)
        weekEvents = events.filter { $0.start < weekEnd }
        upcoming = events
            .filter { !$0.isAllDay && $0.end > now && $0.start < now.addingTimeInterval(2 * 86400) }
            .sorted { $0.start < $1.start }
    }

    private static let meetingHosts = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "facetime.apple.com", "around.co",
    ]
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func convert(_ event: EKEvent) -> Event {
        Event(
            id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
            title: event.title ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            calendarID: event.calendar?.calendarIdentifier ?? "",
            color: Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.6, alpha: 1)),
            meetingURL: meetingURL(for: event)
        )
    }

    /// Finds a video-call link in the event's URL, location or notes.
    private static func meetingURL(for event: EKEvent) -> URL? {
        var candidates: [URL] = []
        if let url = event.url { candidates.append(url) }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: "\n")
        if let linkDetector, !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in linkDetector.matches(in: text, range: range) {
                if let url = match.url { candidates.append(url) }
            }
        }
        return candidates.first { url in
            guard let host = url.host?.lowercased() else { return false }
            return meetingHosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }
}

// MARK: - Keep Awake

final class KeepAwake: ObservableObject {
    @Published private(set) var isOn = false
    @Published private(set) var until: Date?

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    /// Keeps the display (and so the Mac) awake. nil means until turned off.
    func enable(for duration: TimeInterval?) {
        disable()
        let result = IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "GlassDock Keep Awake" as CFString,
                                                 &assertionID)
        guard result == kIOReturnSuccess else { return }
        isOn = true
        if let duration {
            until = Date().addingTimeInterval(duration)
            timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.disable() }
        }
    }

    func disable() {
        timer?.invalidate()
        timer = nil
        if isOn { IOPMAssertionRelease(assertionID) }
        isOn = false
        until = nil
    }
}

// MARK: - Color Picker

final class ColorPickerStore: ObservableObject {
    @Published private(set) var current: NSColor?
    @Published private(set) var recent: [String]

    private let sampler = NSColorSampler()
    private let key = "recentColors"

    init() {
        recent = UserDefaults.standard.stringArray(forKey: key) ?? []
        current = recent.first.flatMap(Self.color(fromHex:))
    }

    /// Opens the system color sampler; the picked color's HEX value is copied.
    func pick() {
        sampler.show { [weak self] color in
            guard let self, let color = color?.usingColorSpace(.sRGB) else { return }
            self.select(color)
            self.copy(Self.hex(color))
        }
    }

    func select(_ color: NSColor) {
        let color = color.usingColorSpace(.sRGB) ?? color
        current = color
        let hex = Self.hex(color)
        recent.removeAll { $0 == hex }
        recent.insert(hex, at: 0)
        recent = Array(recent.prefix(14))
        UserDefaults.standard.set(recent, forKey: key)
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func components(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let color = color.usingColorSpace(.sRGB) ?? color
        return (color.redComponent, color.greenComponent, color.blueComponent)
    }

    static func hex(_ color: NSColor) -> String {
        let c = components(color)
        return String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }

    static func rgb(_ color: NSColor) -> String {
        let c = components(color)
        return "rgb(\(Int((c.r * 255).rounded())), \(Int((c.g * 255).rounded())), \(Int((c.b * 255).rounded())))"
    }

    static func hsl(_ color: NSColor) -> String {
        let c = components(color)
        let maximum = max(c.r, c.g, c.b)
        let minimum = min(c.r, c.g, c.b)
        let lightness = (maximum + minimum) / 2
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        if maximum != minimum {
            let delta = maximum - minimum
            saturation = lightness > 0.5 ? delta / (2 - maximum - minimum) : delta / (maximum + minimum)
            if maximum == c.r {
                hue = (c.g - c.b) / delta + (c.g < c.b ? 6 : 0)
            } else if maximum == c.g {
                hue = (c.b - c.r) / delta + 2
            } else {
                hue = (c.r - c.g) / delta + 4
            }
            hue /= 6
        }
        return "hsl(\(Int((hue * 360).rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    static func color(fromHex hex: String) -> NSColor? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Downloads

final class DownloadsWatcher: ObservableObject {
    struct Item: Identifiable, Equatable {
        let url: URL
        let added: Date
        let size: Int64
        let inProgress: Bool
        var id: URL { url }

        var displayName: String {
            inProgress ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
        }
    }

    @Published private(set) var items: [Item] = []
    let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

    private var timer: Timer?
    private let queue = DispatchQueue(label: "GlassDock.Downloads")
    private static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let folder = self.folder
        queue.async {
            let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .fileSizeKey]
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            let items = urls.map { url -> Item in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return Item(url: url,
                            added: values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast,
                            size: Int64(values?.fileSize ?? 0),
                            inProgress: Self.partialExtensions.contains(url.pathExtension.lowercased()))
            }
            .sorted { $0.added > $1.added }
            let recent = Array(items.prefix(20))
            DispatchQueue.main.async {
                if self.items != recent { self.items = recent }
            }
        }
    }

    func moveToTrash(_ item: Item) {
        try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
        refresh()
    }
}

// MARK: - Devices

final class DevicesService: ObservableObject {
    struct Battery: Hashable {
        let label: String
        let level: Int
    }

    struct Device: Identifiable {
        let name: String
        let kind: String
        let batteries: [Battery]
        var id: String { name }

        var symbol: String {
            let lower = name.lowercased()
            if lower.contains("airpods max") { return "airpodsmax" }
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return "airpods" }
            switch kind.lowercased() {
            case let k where k.contains("headphone") || k.contains("headset"): return "headphones"
            case let k where k.contains("keyboard"): return "keyboard"
            case let k where k.contains("mouse"): return "computermouse"
            case let k where k.contains("trackpad"): return "rectangle.and.hand.point.up.left"
            case let k where k.contains("gamepad") || k.contains("controller"): return "gamecontroller"
            case let k where k.contains("speaker"): return "hifispeaker"
            default: return "dot.radiowaves.left.and.right"
            }
        }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    private var timer: Timer?

    func start() {
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reads connected Bluetooth devices (and their batteries) from system_profiler.
    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var devices: [Device] = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                devices = Self.parse(data)
            }
            DispatchQueue.main.async {
                self.devices = devices
                self.isLoading = false
                self.hasLoaded = true
            }
        }
    }

    private static func parse(_ data: Data) -> [Device] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        let batteryKeys = [
            ("device_batteryLevelMain", ""),
            ("device_batteryLevelLeft", "L"),
            ("device_batteryLevelRight", "R"),
            ("device_batteryLevelCase", "Case"),
        ]
        var result: [Device] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let batteries = batteryKeys.compactMap { key, label -> Battery? in
                        guard let text = info[key] as? String,
                              let level = Int(text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
                        else { return nil }
                        return Battery(label: label, level: level)
                    }
                    result.append(Device(name: name, kind: info["device_minorType"] as? String ?? "", batteries: batteries))
                }
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Terminal

/// Runs one shell command at a time and collects its output. Not a full terminal emulator:
/// interactive programs (vim, top, ssh prompts) won't work.
final class TerminalSession: ObservableObject {
    @Published private(set) var output = ""
    @Published private(set) var isRunning = false
    @Published private(set) var directory = FileManager.default.homeDirectoryForCurrentUser
    private(set) var history: [String] = []

    private var process: Process?
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private static let ansiEscape = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    var prompt: String {
        let path = directory.path
        let shown = path.hasPrefix(home.path) ? "~" + path.dropFirst(home.path.count) : path
        return "\(shown) %"
    }

    func run(_ input: String) {
        let command = input.trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty, !isRunning else { return }
        history.removeAll { $0 == command }
        history.append(command)

        if command == "clear" {
            output = ""
            return
        }
        append("\(prompt) \(command)\n")
        if command == "cd" || command.hasPrefix("cd ") {
            changeDirectory(String(command.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        environment["CLICOLOR"] = "0"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.append(text) }
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async {
                if !rest.isEmpty { self?.append(rest) }
                if finished.terminationStatus != 0 { self?.append("[exit \(finished.terminationStatus)]\n") }
                self?.isRunning = false
                self?.process = nil
            }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
        } catch {
            append("Couldn't run the command: \(error.localizedDescription)\n")
        }
    }

    func interrupt() {
        process?.interrupt()
    }

    private func changeDirectory(_ path: String) {
        let target: URL
        if path.isEmpty || path == "~" {
            target = home
        } else if path.hasPrefix("~/") {
            target = home.appendingPathComponent(String(path.dropFirst(2)))
        } else if path.hasPrefix("/") {
            target = URL(fileURLWithPath: path)
        } else {
            target = directory.appendingPathComponent(path)
        }
        var isDirectory: ObjCBool = false
        let standardized = target.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue {
            directory = standardized
        } else {
            append("cd: no such directory: \(path)\n")
        }
    }

    private func append(_ text: String) {
        let range = NSRange(text.startIndex..., in: text)
        let clean = Self.ansiEscape.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            .replacingOccurrences(of: "\r", with: "")
        output += clean
        if output.count > 30_000 { output = String(output.suffix(20_000)) }
    }
}
