import AppKit
import ApplicationServices

struct OpenWindow: Identifiable, Equatable {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let icon: NSImage?
    let title: String
    let isMinimized: Bool
    let isFullScreen: Bool

    static func == (lhs: OpenWindow, rhs: OpenWindow) -> Bool {
        lhs.id == rhs.id && lhs.appName == rhs.appName && lhs.title == rhs.title && lhs.isMinimized == rhs.isMinimized
            && lhs.isFullScreen == rhs.isFullScreen
    }
}

struct PinnedWindow: Equatable {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    var windowID: CGWindowID?

    static func == (lhs: PinnedWindow, rhs: PinnedWindow) -> Bool { lhs.id == rhs.id }
}

final class PinnedWindowController: ObservableObject {
    @Published private(set) var windows: [OpenWindow] = []
    @Published private(set) var pinned: [PinnedWindow] = []
    @Published private(set) var isTrusted = AppWindows.isTrusted
    @Published private(set) var raiseErrors: [String: AXError] = [:]

    private static let checkInterval: TimeInterval = 0.1
    private static let listInterval: TimeInterval = 1.5
    private static let eventDelay: TimeInterval = 0.015
    private static let mouseDownDelay: TimeInterval = 0.03
    private static let appNotifications = [kAXFocusedWindowChangedNotification, kAXApplicationActivatedNotification,
                                           kAXApplicationDeactivatedNotification]

    private static let observerCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        Unmanaged<PinnedWindowController>.fromOpaque(refcon).takeUnretainedValue().scheduleCheck()
    }

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let listQueue = DispatchQueue(label: "GlassDock.Windows", qos: .utility)
    private var listTimer: Timer?
    private var checkTimer: Timer?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var observers: [pid_t: AXObserver] = [:]
    private var mouseMonitor: Any?
    private var pendingCheck: DispatchWorkItem?
    private var pendingDue: Date?
    private var lastRaise: Date?
    private var press: (start: Date, location: CGPoint)?

    func isPinned(_ window: OpenWindow) -> Bool {
        pinned.contains { $0.id == window.id }
    }

    func startListing() {
        refreshWindows()
        guard listTimer == nil else { return }
        let timer = Timer(timeInterval: Self.listInterval, repeats: true) { [weak self] _ in
            self?.refreshWindows()
        }
        RunLoop.main.add(timer, forMode: .common)
        listTimer = timer
    }

    func stopListing() {
        listTimer?.invalidate()
        listTimer = nil
    }

    func refreshWindows() {
        let trusted = AppWindows.isTrusted
        if isTrusted != trusted { isTrusted = trusted }
        guard trusted else {
            if !windows.isEmpty { windows = [] }
            return
        }
        let ownPID = self.ownPID
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated }
            .map { (pid: $0.processIdentifier, name: $0.localizedName ?? "App", icon: $0.icon) }
        listQueue.async { [weak self] in
            var found: [OpenWindow] = []
            for app in apps {
                for window in AppWindows.list(pid: app.pid) {
                    guard let frame = AXWindow.frame(of: window.element),
                          WindowFilter.isNormal(WindowCandidate(pid: app.pid, layer: 0, frame: frame), ownPID: ownPID)
                    else { continue }
                    found.append(OpenWindow(id: AXWindow.identifier(of: window.element, pid: app.pid), element: window.element,
                                            pid: app.pid, appName: app.name, icon: app.icon, title: window.title,
                                            isMinimized: window.minimized,
                                            isFullScreen: AXWindow.hasFullScreenFlag(window.element)))
                }
            }
            found.sort {
                let byApp = $0.appName.localizedCaseInsensitiveCompare($1.appName)
                return byApp == .orderedSame ? $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    : byApp == .orderedAscending
            }
            DispatchQueue.main.async { self?.publish(found) }
        }
    }

    func togglePin(_ window: OpenWindow) {
        if isPinned(window) {
            remove { $0.id == window.id }
        } else {
            pin(window)
        }
    }

    func unpinAll() {
        remove { _ in true }
    }

    func snap(_ window: OpenWindow, to preset: SnapPreset) {
        let areas = Self.displayAreas()
        guard let frame = AXWindow.frame(of: window.element),
              let index = WindowGeometry.displayIndex(for: frame, among: areas) else { return }
        AXWindow.setFrame(preset.frame(in: areas[index].visibleFrame), of: window.element)
        refreshWindows()
    }

    func moveToNextDisplay(_ window: OpenWindow) {
        let areas = Self.displayAreas()
        guard areas.count > 1, let frame = AXWindow.frame(of: window.element),
              let index = WindowGeometry.displayIndex(for: frame, among: areas) else { return }
        let next = areas[(index + 1) % areas.count]
        AXWindow.setFrame(WindowGeometry.moved(frame, from: areas[index].visibleFrame, to: next.visibleFrame),
                          of: window.element)
        refreshWindows()
    }

    private func publish(_ found: [OpenWindow]) {
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = PinPolicy.pinnedFirst(found.map(\.id), pinned: pinned.map(\.id)).compactMap { byID[$0] }
        if windows != ordered { windows = ordered }
    }

    private func pin(_ window: OpenWindow) {
        guard AppWindows.isTrusted, !window.isMinimized, !isFullScreen(window) else { return }
        AXUIElementSetMessagingTimeout(window.element, 0.2)
        let entry = PinnedWindow(id: window.id, element: window.element, pid: window.pid,
                                 windowID: AXWindow.windowID(of: window.element, pid: window.pid,
                                                             excluding: Set(pinned.compactMap(\.windowID))))
        pinned.insert(entry, at: 0)
        startWatching()
        watch(entry)
        publish(windows)
        scheduleCheck()
    }

    private func remove(where shouldRemove: (PinnedWindow) -> Bool) {
        let removed = pinned.filter(shouldRemove)
        guard !removed.isEmpty else { return }
        pinned.removeAll(where: shouldRemove)
        removed.forEach(unwatch)
        removed.forEach { raiseErrors[$0.id] = nil }
        if pinned.isEmpty { stopWatching() }
        publish(windows)
    }

    private func isFullScreen(_ window: OpenWindow) -> Bool {
        if AXWindow.hasFullScreenFlag(window.element) { return true }
        guard let frame = AXWindow.frame(of: window.element),
              let index = WindowGeometry.displayIndex(for: frame, among: Self.displayAreas()),
              let uuid = NSScreen.physicalScreens[index].displayUUID else { return false }
        return IslandSpace.isFullScreen(displayUUID: uuid, in: IslandSpace.managedDisplaySpaces())
    }

    private func startWatching() {
        guard checkTimer == nil else { return }
        checkTimer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleCheck()
            })
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            if event.type == .leftMouseDown {
                self?.press = (Date(), NSEvent.mouseLocation)
                self?.scheduleCheck(after: Self.mouseDownDelay)
            } else {
                self?.press = nil
                self?.scheduleCheck()
            }
        }
    }

    private func stopWatching() {
        checkTimer?.invalidate()
        checkTimer = nil
        pendingCheck?.cancel()
        pendingCheck = nil
        pendingDue = nil
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens = []
        mouseMonitor.map(NSEvent.removeMonitor)
        mouseMonitor = nil
        press = nil
        lastRaise = nil
    }

    private func watch(_ window: PinnedWindow) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var observer = observers[window.pid]
        if observer == nil {
            var created: AXObserver?
            guard AXObserverCreate(window.pid, Self.observerCallback, &created) == .success, let created else { return }
            for name in Self.appNotifications {
                AXObserverAddNotification(created, AXUIElementCreateApplication(window.pid), name as CFString, refcon)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
            observers[window.pid] = created
            observer = created
        }
        if let observer {
            AXObserverAddNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString, refcon)
        }
    }

    private func unwatch(_ window: PinnedWindow) {
        guard let observer = observers[window.pid] else { return }
        AXObserverRemoveNotification(observer, window.element, kAXUIElementDestroyedNotification as CFString)
        guard !pinned.contains(where: { $0.pid == window.pid }) else { return }
        for name in Self.appNotifications {
            AXObserverRemoveNotification(observer, AXUIElementCreateApplication(window.pid), name as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[window.pid] = nil
    }

    private func scheduleCheck(after delay: TimeInterval = PinnedWindowController.eventDelay) {
        let due = Date().addingTimeInterval(delay)
        if let pendingDue, pendingDue <= due { return }
        pendingCheck?.cancel()
        pendingDue = due
        let work = DispatchWorkItem { [weak self] in
            self?.pendingDue = nil
            self?.checkNow()
        }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func mouseState() -> (heldFor: TimeInterval?, travel: CGFloat) {
        guard NSEvent.pressedMouseButtons != 0 else {
            press = nil
            return (nil, 0)
        }
        let current = press ?? (Date(), NSEvent.mouseLocation)
        press = current
        let location = NSEvent.mouseLocation
        return (Date().timeIntervalSince(current.start), hypot(location.x - current.location.x, location.y - current.location.y))
    }

    private func checkNow() {
        guard !pinned.isEmpty else { return }
        remove { window in
            guard let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else { return true }
            var role: CFTypeRef?
            return AXUIElementCopyAttributeValue(window.element, kAXRoleAttribute as CFString, &role) == .invalidUIElement
        }
        let mouse = mouseState()
        guard !pinned.isEmpty,
              PinPolicy.canRaise(secondsSinceLastRaise: lastRaise.map { Date().timeIntervalSince($0) },
                                 mouseHeldFor: mouse.heldFor, mouseTravel: mouse.travel,
                                 isIslandInUse: isIslandInUse) else { return }
        resolveMissingWindowIDs()
        let zOrder = AXWindow.onScreenWindows().filter { WindowFilter.isNormal($0.candidate, ownPID: ownPID) }
            .map { (id: $0.id, owner: $0.candidate.pid, frame: $0.candidate.frame) }
        let toRaise = PinPolicy.windowsToRaise(zOrder: zOrder, pinned: pinned.compactMap(\.windowID))
        guard !toRaise.isEmpty else { return }
        for id in toRaise {
            if let window = pinned.first(where: { $0.windowID == id }) { raise(window) }
        }
        lastRaise = Date()
    }

    private var isIslandInUse: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ownPID || NSApp.keyWindow is IslandPanel
    }

    private func resolveMissingWindowIDs() {
        for index in pinned.indices where pinned[index].windowID == nil {
            let claimed = Set(pinned.compactMap(\.windowID))
            pinned[index].windowID = AXWindow.windowID(of: pinned[index].element, pid: pinned[index].pid, excluding: claimed)
        }
    }

    private func raise(_ window: PinnedWindow) {
        let error = AXWindow.bringForward(window.element, pid: window.pid)
        if error == .success {
            if raiseErrors[window.id] != nil { raiseErrors[window.id] = nil }
        } else if raiseErrors[window.id] != error {
            raiseErrors[window.id] = error
        }
    }

    static func displayAreas() -> [DisplayArea] {
        NSScreen.physicalScreens.map(\.area)
    }
}
