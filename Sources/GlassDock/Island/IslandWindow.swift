import AppKit
import Combine
import SwiftUI

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class IslandWindowController {
    private let context: IslandContext
    private var windows: [CGDirectDisplayID: IslandDisplayWindow] = [:]
    private var isShown = false
    private var ticker: Timer?
    private var clickMonitor: Any?
    private var modeObserver: AnyCancellable?
    private var fullScreenObserver: AnyCancellable?

    init(context: IslandContext) {
        self.context = context

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        }
        modeObserver = context.settings.$islandWithoutNotch
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.sync() } }
        fullScreenObserver = context.settings.$hideIslandInFullScreen
            .removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateFullScreen() } }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                    object: nil, queue: .main) { [weak self] _ in
            self?.updateFullScreen()
        }
        workspaceCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                    object: nil, queue: .main) { [weak self] _ in
            self?.updateFullScreen()
        }
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        context.systemHUD.start()
        context.notifications.start()
        sync()

        let ticker = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.windows.values.forEach { $0.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.windows.values.forEach { $0.handleOutsideClick() }
        }
    }

    func hide() {
        isShown = false
        context.systemHUD.stop()
        context.notifications.stop()
        ticker?.invalidate()
        ticker = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        sync()
    }

    private func sync() {
        let mode = context.settings.islandWithoutNotch
        let screens = isShown ? NSScreen.screens.filter { mode.showsIsland(hasNotch: IslandMetrics(screen: $0).hasNotch) } : []
        let wanted = Set(screens.map(\.displayID))

        for id in windows.keys where !wanted.contains(id) {
            windows.removeValue(forKey: id)?.close()
        }
        for screen in screens {
            let window = windows[screen.displayID] ?? makeWindow(for: screen)
            window.reposition(on: screen)
        }
        updateFullScreen()
    }

    private func updateFullScreen() {
        let spaces = context.settings.hideIslandInFullScreen ? IslandSpace.managedDisplaySpaces() : []
        for (id, window) in windows {
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
            window.hideForFullScreen(uuid.map { IslandSpace.isFullScreen(displayUUID: $0, in: spaces) } ?? false)
        }
    }

    private func makeWindow(for screen: NSScreen) -> IslandDisplayWindow {
        let window = IslandDisplayWindow(context: context) { [weak self] opened in
            self?.windows.values.filter { $0 !== opened }.forEach { $0.collapse() }
        }
        windows[screen.displayID] = window
        return window
    }
}

final class IslandDisplayWindow {
    private let panel: IslandPanel
    private let state: IslandState
    private var space = IslandSpace()
    private let onExpand: (IslandDisplayWindow) -> Void
    private var hoverStart: Date?
    private var lastInside = Date.distantPast

    init(context: IslandContext, onExpand: @escaping (IslandDisplayWindow) -> Void) {
        self.onExpand = onExpand
        state = IslandState(nowPlaying: context.nowPlaying, timer: context.timer, battery: context.battery,
                            systemHUD: context.systemHUD, notifications: context.notifications)

        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        let host = FirstMouseHostingView(rootView: IslandView(context: context, state: state))
        host.sizingOptions = []
        panel.contentView = host
    }

    func reposition(on screen: NSScreen) {
        let metrics = IslandMetrics(screen: screen)
        if state.metrics != metrics { state.metrics = metrics }

        let size = metrics.expandedSize
        let width = size.width + 80
        let height = size.height + 40
        panel.setFrame(NSRect(x: metrics.centerX - width / 2, y: screen.frame.maxY - height,
                              width: width, height: height), display: true)
        if !panel.isVisible { bringToFront() }
    }

    func close() {
        space = nil
        panel.close()
    }

    private var islandRect: NSRect {
        let size = state.size
        let metrics = state.metrics
        return NSRect(x: metrics.centerX - size.width / 2, y: metrics.screenTop - size.height,
                      width: size.width, height: size.height)
    }

    func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        let inside = !state.isHiddenForFullScreen && islandRect.insetBy(dx: -6, dy: -6).contains(mouse)

        if inside {
            lastInside = now
            if !state.expanded {
                let buttonDown = NSEvent.pressedMouseButtons & 1 == 1
                let draggingFiles = buttonDown && (NSPasteboard(name: .drag).types?.contains(.fileURL) ?? false)
                if draggingFiles {
                    state.tab = .shelf
                    expand()
                } else if let hoverStart {
                    if !buttonDown, now.timeIntervalSince(hoverStart) > 0.15 { expand() }
                } else {
                    hoverStart = now
                }
            }
        } else {
            hoverStart = nil
            if state.expanded, !panel.isKeyWindow, now.timeIntervalSince(lastInside) > 0.4 {
                collapse()
            }
        }

        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }

    func handleOutsideClick() {
        guard state.expanded, !islandRect.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    private func expand() {
        hoverStart = nil
        state.expanded = true
        onExpand(self)
    }

    func hideForFullScreen(_ hidden: Bool) {
        guard state.isHiddenForFullScreen != hidden else { return }
        if hidden, state.expanded { collapse() }
        state.isHiddenForFullScreen = hidden
    }

    func collapse() {
        let wasKey = panel.isKeyWindow
        state.expanded = false
        if wasKey {
            panel.orderOut(nil)
            bringToFront()
        }
    }

    private func bringToFront() {
        panel.orderFrontRegardless()
        space?.add(panel)
    }
}
