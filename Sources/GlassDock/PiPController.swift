import AppKit
import ApplicationServices
import Combine
import ScreenCaptureKit

final class PiPController: ObservableObject {
    @Published private(set) var active: Set<String> = []
    @Published private(set) var needsScreenAccess = false
    @Published private(set) var failure: String?
    @Published private(set) var keptLive: Set<String> = []
    @Published private(set) var looksProtected: Set<String> = []

    private final class Session {
        let panel: PiPPanel
        let window: OpenWindow
        var windowSize: CGSize
        var windowOrigin: CGPoint
        var displayFrame: CGRect?
        var wantsDisplayCapture = false
        var triedDisplayCapture = false
        var crop: PiPCrop?
        var isEditingCrop = false
        var stream: PiPStream
        var state = PiPSourceState.live
        var blankSince: Date?
        var needsRestart = false
        var isRestarting = false
        var restartFailures = 0

        var capturedCrop: PiPCrop? { isEditingCrop ? nil : crop }
        var windowFrame: CGRect { CGRect(origin: windowOrigin, size: windowSize) }

        init(panel: PiPPanel, window: OpenWindow, windowFrame: CGRect, stream: PiPStream) {
            self.panel = panel
            self.window = window
            windowSize = windowFrame.size
            windowOrigin = windowFrame.origin
            self.stream = stream
        }
    }

    private static let accessCheckInterval: TimeInterval = 2
    private static let maxRestartFailures = 5
    private static let screenRecordingSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let settings: DockSettings
    private let keepLive = PiPKeepLiveWindows()
    private var settingObserver: AnyCancellable?
    private var sessions: [String: Session] = [:]
    private var opening: Set<String> = []
    private var accessTimer: Timer?
    private var sourceTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []

    init(settings: DockSettings) {
        self.settings = settings
        settingObserver = settings.$pipKeepLive
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyKeepLiveSetting() } }
    }

    func isActive(_ window: OpenWindow) -> Bool {
        active.contains(window.id)
    }

    func isKeptLive(_ window: OpenWindow) -> Bool {
        keptLive.contains(window.id)
    }

    func looksProtected(_ window: OpenWindow) -> Bool {
        looksProtected.contains(window.id)
    }

    func block(for window: OpenWindow) -> PiPEligibility.Block? {
        PiPEligibility.block(isMinimized: window.isMinimized, isFullScreen: window.isFullScreen,
                             pid: window.pid, ownPID: ownPID)
    }

    func toggle(_ window: OpenWindow) {
        if isActive(window) {
            close(window.id)
            return
        }
        failure = nil
        guard CGPreflightScreenCaptureAccess() else {
            needsScreenAccess = true
            _ = CGRequestScreenCaptureAccess()
            watchAccess()
            return
        }
        needsScreenAccess = false
        open(window)
    }

    func closeAll() {
        Array(sessions.keys).forEach(close)
    }

    func watchAccess() {
        guard needsScreenAccess, accessTimer == nil else { return }
        let timer = Timer(timeInterval: Self.accessCheckInterval, repeats: true) { [weak self] _ in
            self?.updateAccess()
        }
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
    }

    func stopWatchingAccess() {
        accessTimer?.invalidate()
        accessTimer = nil
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: Self.screenRecordingSettingsURL) { NSWorkspace.shared.open(url) }
    }

    private func updateAccess() {
        guard CGPreflightScreenCaptureAccess() else { return }
        needsScreenAccess = false
        stopWatchingAccess()
    }

    private func open(_ window: OpenWindow) {
        guard block(for: window) == nil, !opening.contains(window.id) else { return }
        opening.insert(window.id)
        Task { @MainActor [weak self] in
            defer { self?.opening.remove(window.id) }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let target = Self.captureWindow(for: window, in: content.windows) else {
                    self?.failure = "Couldn't find this window to show in Picture in Picture"
                    return
                }
                try await self?.present(window, capturing: target)
            } catch {
                guard let self else { return }
                needsScreenAccess = !CGPreflightScreenCaptureAccess()
                failure = needsScreenAccess ? nil : error.localizedDescription
                watchAccess()
            }
        }
    }

    @MainActor
    private func present(_ window: OpenWindow, capturing target: SCWindow) async throws {
        let id = window.id
        let original = AXWindow.frame(of: window.element) ?? target.frame
        let areas = PinnedWindowController.displayAreas()
        guard PiPGeometry.aspect(of: original.size) != nil,
              let screen = WindowGeometry.displayIndex(for: original, among: areas).map({ NSScreen.physicalScreens[$0] })
                  ?? NSScreen.main
        else { return }
        var isOpen = false
        defer {
            if !isOpen {
                keepLive.restore(id)
                syncKeptLive()
            }
        }
        report(await keepLive.keep(window, id: id, isEnabled: settings.pipKeepLive, ownPID: ownPID))
        syncKeptLive()
        let frame = AXWindow.frame(of: window.element) ?? original
        guard let aspect = PiPGeometry.aspect(of: frame.size) else { return }
        let visible = screen.visibleFrame
        let size = PiPGeometry.fittedSize(width: PiPGeometry.defaultWidth, aspect: aspect, within: visible.size)

        let panel = PiPPanel(frame: PiPGeometry.initialFrame(size: size, in: visible, cascade: sessions.count),
                             aspect: aspect,
                             target: PiPTarget(element: window.element, pid: window.pid, windowID: target.windowID),
                             onClose: { [weak self] in self?.close(id) },
                             onShowWindow: { [weak self] in self?.showWindow(id) },
                             onCrop: { [weak self] in self?.handleCrop($0, id: id) })
        let stream = makeStream(id: id, panel: panel, target: target, display: nil, windowFrame: frame,
                                scale: screen.backingScaleFactor, crop: nil)
        try await stream.start()
        sessions[id] = Session(panel: panel, window: window, windowFrame: frame, stream: stream)
        isOpen = true
        if !settings.pipKeepLive { keepLive.restore(id) }
        active.insert(id)
        panel.present()
        watchSources()
    }

    private func makeStream(id: String, panel: PiPPanel, target: SCWindow, display: SCDisplay?, windowFrame: CGRect,
                            scale: CGFloat, crop: PiPCrop?) -> PiPStream {
        PiPStream(window: target, display: display, windowFrame: windowFrame, scale: scale, crop: crop,
                  onFrame: { [weak panel] in panel?.show($0) },
                  onAspect: { [weak panel] in panel?.updateAspect($0) },
                  onBlank: { [weak self] isBlank in
                      let session = self?.sessions[id]
                      session?.blankSince = isBlank ? session?.blankSince ?? Date() : nil
                  },
                  onBlackRegion: { [weak self] isProtected in
                      if isProtected { self?.looksProtected.insert(id) } else { self?.looksProtected.remove(id) }
                      if isProtected { self?.switchToDisplayCapture(id) }
                  },
                  onStop: { [weak self] in
                      self?.sessions[id]?.needsRestart = true
                      self?.refreshSources()
                  })
    }

    private func watchSources() {
        guard sourceTimer == nil else { return }
        let timer = Timer(timeInterval: PiPSourceState.checkInterval, repeats: true) { [weak self] _ in
            self?.refreshSources()
        }
        RunLoop.main.add(timer, forMode: .common)
        sourceTimer = timer
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                              NSWorkspace.didActivateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshSources() }
        }
    }

    private func stopWatchingSources() {
        sourceTimer?.invalidate()
        sourceTimer = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers = []
    }

    private func refreshSources() {
        let now = Date()
        for (id, session) in sessions { refresh(id, session, now: now) }
    }

    private func refresh(_ id: String, _ session: Session, now: Date) {
        guard let app = NSRunningApplication(processIdentifier: session.window.pid), !app.isTerminated,
              AXWindow.exists(session.window.element) else {
            close(id)
            return
        }
        let appHidden = app.isHidden
        let minimized = AXWindow.isMinimized(session.window.element)
        if PiPSourceState.decide(appHidden: appHidden, minimized: minimized, secondsOfBlankFrames: 0) != .live {
            session.blankSince = nil
        }
        let state = PiPSourceState.decide(appHidden: appHidden, minimized: minimized,
                                          secondsOfBlankFrames: session.blankSince.map { now.timeIntervalSince($0) } ?? 0)
        if state != session.state {
            if state == .live { session.needsRestart = true }
            session.state = state
            session.panel.setSource(state)
        }
        if let frame = AXWindow.frame(of: session.window.element) {
            let movedUnderDisplayCapture = session.displayFrame != nil && frame.origin != session.windowOrigin
            if frame.size != session.windowSize || movedUnderDisplayCapture {
                session.windowSize = frame.size
                session.windowOrigin = frame.origin
                if session.crop != nil || session.displayFrame != nil, !session.isEditingCrop { applyCapture(session) }
            }
            if let displayFrame = session.displayFrame, !displayFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                session.needsRestart = true
            }
        }
        if state == .unavailable(.notVisible), session.displayFrame != nil {
            session.wantsDisplayCapture = false
            session.needsRestart = true
            restart(id, session)
        }
        if state == .live { reassertKeepLive(id) }
        if state == .live, session.needsRestart { restart(id, session) }
    }

    private func reassertKeepLive(_ id: String) {
        guard settings.pipKeepLive, keepLive.isKept(id), keepLive.reassert(id) == .gaveUp else { return }
        failure = PiPKeepLive.gaveUpNote
        syncKeptLive()
    }

    private func applyKeepLiveSetting() {
        for (id, session) in sessions {
            if settings.pipKeepLive {
                engageKeepLive(id, session)
            } else {
                keepLive.restore(id)
            }
        }
        syncKeptLive()
    }

    private func engageKeepLive(_ id: String, _ session: Session) {
        Task { @MainActor [weak self] in
            guard let self, sessions[id] === session else { return }
            report(await keepLive.keep(session.window, id: id, isEnabled: settings.pipKeepLive, ownPID: ownPID))
            if sessions[id] !== session || !settings.pipKeepLive { keepLive.restore(id) }
            syncKeptLive()
        }
    }

    private func report(_ outcome: PiPKeepLiveWindows.Outcome) {
        if case .notKept(let note?) = outcome { failure = note }
    }

    private func showWindow(_ id: String) {
        guard let session = sessions[id] else { return }
        keepLive.restore(id)
        syncKeptLive()
        _ = AXWindow.restore(session.window.element, pid: session.window.pid)
    }

    private func syncKeptLive() {
        let ids = keepLive.keptIDs
        if keptLive != ids { keptLive = ids }
    }

    private func handleCrop(_ action: PiPCropAction, id: String) {
        guard let session = sessions[id] else { return }
        if let frame = AXWindow.frame(of: session.window.element) {
            session.windowSize = frame.size
            session.windowOrigin = frame.origin
        }
        switch action {
        case .begin: session.isEditingCrop = true
        case .apply(let crop):
            session.isEditingCrop = false
            session.crop = crop
        case .cancel: session.isEditingCrop = false
        case .reset: session.crop = nil
        }
        applyCapture(session)
    }

    private func applyCapture(_ session: Session) {
        guard let fullAspect = PiPGeometry.aspect(of: session.windowSize) else { return }
        session.stream.update(windowFrame: session.windowFrame, crop: session.capturedCrop)
        if session.isEditingCrop {
            session.panel.beginCropping(selection: session.crop, windowSize: session.windowSize, aspect: fullAspect)
        } else {
            session.panel.setCrop(session.crop, aspect: session.crop?.aspect(in: session.windowSize) ?? fullAspect)
        }
    }

    private func restart(_ id: String, _ session: Session) {
        guard !session.isRestarting else { return }
        session.isRestarting = true
        Task { @MainActor [weak self] in
            let restarted = await self?.restartStream(id, session) ?? false
            session.isRestarting = false
            if restarted {
                session.needsRestart = false
                session.restartFailures = 0
            } else {
                session.wantsDisplayCapture = false
                session.restartFailures += 1
                if session.restartFailures >= Self.maxRestartFailures { self?.close(id) }
            }
        }
    }

    @MainActor
    private func restartStream(_ id: String, _ session: Session) async -> Bool {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let target = Self.captureWindow(for: session.window, in: content.windows) else { return false }
            let scale = session.panel.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let origin = AXWindow.frame(of: session.window.element)?.origin ?? session.windowOrigin
            let frame = CGRect(origin: origin, size: session.windowSize)
            let display = session.wantsDisplayCapture
                ? content.displays.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) } : nil
            let stream = makeStream(id: id, panel: session.panel, target: target, display: display, windowFrame: frame,
                                    scale: scale, crop: session.capturedCrop)
            try await stream.start()
            guard sessions[id] === session else {
                stream.stop()
                return false
            }
            session.stream.stop()
            session.stream = stream
            session.windowOrigin = origin
            session.displayFrame = display?.frame
            session.blankSince = nil
            looksProtected.remove(id)
            return true
        } catch {
            return false
        }
    }

    private func switchToDisplayCapture(_ id: String) {
        guard let session = sessions[id], !session.triedDisplayCapture else { return }
        session.triedDisplayCapture = true
        session.wantsDisplayCapture = true
        session.needsRestart = true
        refreshSources()
    }

    private func close(_ id: String) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.stream.stop()
        keepLive.restore(id)
        syncKeptLive()
        session.panel.dismiss()
        active.remove(id)
        looksProtected.remove(id)
        if sessions.isEmpty { stopWatchingSources() }
    }

    private static func captureWindow(for window: OpenWindow, in windows: [SCWindow]) -> SCWindow? {
        if let id = AXWindow.windowID(of: window.element, pid: window.pid),
           let match = windows.first(where: { $0.windowID == id }) { return match }
        guard let frame = AXWindow.frame(of: window.element) else { return nil }
        let candidates = windows.compactMap { scWindow in
            scWindow.owningApplication.map {
                OnScreenWindow(id: scWindow.windowID,
                               candidate: WindowCandidate(pid: $0.processID, layer: scWindow.windowLayer, frame: scWindow.frame))
            }
        }
        return PinPolicy.windowID(matching: frame, pid: window.pid, among: candidates)
            .flatMap { id in windows.first { $0.windowID == id } }
    }
}
