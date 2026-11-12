import AppKit
import Combine

struct DockApp: Identifiable {
    let path: String
    let url: URL
    let name: String
    let bundleID: String?
    let icon: NSImage
    let isPinned: Bool
    let running: NSRunningApplication?

    var id: String { path }
    var isRunning: Bool { running != nil }
    var isFinder: Bool { bundleID == "com.apple.finder" }
}

/// Pinned apps plus running apps, kept in sync with NSWorkspace.
final class DockModel: ObservableObject {
    @Published private(set) var apps: [DockApp] = []

    private let settings: DockSettings
    private var iconCache: [String: NSImage] = [:]
    private var bundleIDCache: [String: String] = [:]
    private var cancellables = Set<AnyCancellable>()

    init(settings: DockSettings) {
        self.settings = settings

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(self, selector: #selector(workspaceChanged), name: name, object: nil)
        }

        settings.$pinnedPaths
            .combineLatest(settings.$showRunningApps)
            .sink { [weak self] pinned, showRunning in
                self?.rebuild(pinned: pinned, showRunning: showRunning)
            }
            .store(in: &cancellables)
    }

    @objc private func workspaceChanged() {
        rebuild(pinned: settings.pinnedPaths, showRunning: settings.showRunningApps)
    }

    private func rebuild(pinned: [String], showRunning: Bool) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleURL != nil && $0.processIdentifier != ownPID
        }

        var runningByBundleID: [String: NSRunningApplication] = [:]
        var runningByPath: [String: NSRunningApplication] = [:]
        for app in running {
            if let id = app.bundleIdentifier, runningByBundleID[id] == nil { runningByBundleID[id] = app }
            if let url = app.bundleURL { runningByPath[url.standardizedFileURL.path] = app }
        }

        var result: [DockApp] = []
        var seen = Set<String>()

        for path in pinned {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let bundleID = bundleIdentifier(for: url)
            guard seen.insert(bundleID ?? url.path).inserted else { continue }
            let runningApp = bundleID.flatMap { runningByBundleID[$0] } ?? runningByPath[url.path]
            result.append(makeApp(url: url, bundleID: bundleID, pinned: true, running: runningApp))
        }

        if showRunning {
            for app in running {
                guard let url = app.bundleURL?.standardizedFileURL else { continue }
                guard seen.insert(app.bundleIdentifier ?? url.path).inserted else { continue }
                result.append(makeApp(url: url, bundleID: app.bundleIdentifier, pinned: false, running: app))
            }
        }

        apps = result
    }

    private func bundleIdentifier(for url: URL) -> String? {
        if let cached = bundleIDCache[url.path] { return cached }
        let id = Bundle(url: url)?.bundleIdentifier
        if let id { bundleIDCache[url.path] = id }
        return id
    }

    private func makeApp(url: URL, bundleID: String?, pinned: Bool, running: NSRunningApplication?) -> DockApp {
        let name = running?.localizedName ?? {
            let display = FileManager.default.displayName(atPath: url.path)
            return display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        }()
        return DockApp(path: url.path, url: url, name: name, bundleID: bundleID,
                       icon: icon(for: url), isPinned: pinned, running: running)
    }

    private func icon(for url: URL) -> NSImage {
        if let cached = iconCache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 256, height: 256)
        iconCache[url.path] = image
        return image
    }

    // MARK: Actions

    /// Opens the app, or switches to it if it's running. `failed` is called on the main queue if it can't open.
    func open(_ app: DockApp, failed: (() -> Void)? = nil) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let path = app.path
        NSWorkspace.shared.openApplication(at: app.url, configuration: config) { _, error in
            if let error {
                NSLog("GlassDock: could not open \(path): \(error.localizedDescription)")
                DispatchQueue.main.async { failed?() }
            }
        }
    }

    /// Option-click: switch to the app and hide every other app.
    func openHidingOthers(_ app: DockApp) {
        open(app)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let keepPID = app.running?.processIdentifier
        for other in NSWorkspace.shared.runningApplications where other.activationPolicy == .regular {
            guard other.processIdentifier != ownPID, other.processIdentifier != keepPID else { continue }
            if let id = app.bundleID, other.bundleIdentifier == id { continue }
            other.hide()
        }
    }

    /// Switches to the app, then shows only its windows in Mission Control (App Exposé).
    func showAllWindows(_ app: DockApp) {
        open(app)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control")
            process.arguments = ["2"]
            do { try process.run() } catch {
                NSLog("GlassDock: could not start App Exposé: \(error.localizedDescription)")
            }
        }
    }

    /// Opens a document from the app's recent documents in that app.
    func openDocument(_ url: URL, with app: DockApp) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open([url], withApplicationAt: app.url, configuration: config) { _, error in
            if let error {
                NSLog("GlassDock: could not open \(url.path): \(error.localizedDescription)")
            }
        }
    }

    func newFinderWindow() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
    }

    func togglePin(_ app: DockApp) {
        if app.isPinned {
            settings.pinnedPaths.removeAll { URL(fileURLWithPath: $0).standardizedFileURL.path == app.path }
        } else {
            settings.pinnedPaths.append(app.path)
        }
    }

    func reveal(_ app: DockApp) {
        NSWorkspace.shared.activateFileViewerSelecting([app.url])
    }

    func hide(_ app: DockApp) { app.running?.hide() }
    func quit(_ app: DockApp) { app.running?.terminate() }
    func forceQuit(_ app: DockApp) { app.running?.forceTerminate() }

    func openTrash() {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        NSWorkspace.shared.open(trash)
    }
}
