import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    // Can take keyboard focus (for notes and clipboard search) without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class IslandWindowController {
    private let panel: IslandPanel
    private let state: IslandState
    private let space = IslandSpace()
    private var ticker: Timer?
    private var clickMonitor: Any?
    private var hoverStart: Date?
    private var lastInside = Date.distantPast

    init(context: IslandContext) {
        self.state = context.state

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
        panel.ignoresMouseEvents = true

        let host = FirstMouseHostingView(rootView: IslandView(context: context))
        host.sizingOptions = []
        panel.contentView = host

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
    }

    func show() {
        guard ticker == nil else { return }
        reposition()
        bringToFront()

        let ticker = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.handleOutsideClick()
        }
    }

    func hide() {
        ticker?.invalidate()
        ticker = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        state.expanded = false
        panel.orderOut(nil)
    }

    private func reposition() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else {
            return
        }
        let metrics = IslandMetrics(screen: screen)
        if state.metrics != metrics { state.metrics = metrics }

        let size = metrics.expandedSize
        let width = size.width + 80
        let height = size.height + 40
        panel.setFrame(NSRect(x: metrics.centerX - width / 2, y: screen.frame.maxY - height,
                              width: width, height: height), display: true)
    }

    /// The island's current shape in screen coordinates.
    private var islandRect: NSRect {
        let size = state.size
        let metrics = state.metrics
        return NSRect(x: metrics.centerX - size.width / 2, y: metrics.screenTop - size.height,
                      width: size.width, height: size.height)
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        let inside = islandRect.insetBy(dx: -6, dy: -6).contains(mouse)

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
            // While the user is typing in the island, only an outside click closes it.
            if state.expanded, !panel.isKeyWindow, now.timeIntervalSince(lastInside) > 0.4 {
                collapse()
            }
        }

        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }

    private func handleOutsideClick() {
        guard state.expanded, !islandRect.contains(NSEvent.mouseLocation) else { return }
        collapse()
    }

    private func expand() {
        hoverStart = nil
        state.expanded = true
    }

    private func collapse() {
        let wasKey = panel.isKeyWindow
        state.expanded = false
        if wasKey {
            // Hand keyboard focus back to the app the user was in.
            panel.orderOut(nil)
            bringToFront()
        }
    }

    private func bringToFront() {
        panel.orderFrontRegardless()
        space?.add(panel)
    }
}
