import AppKit
import SwiftUI
import Combine

/// Live interaction state shared between the window controller and the SwiftUI view.
final class DockState: ObservableObject {
    /// Cursor x in window coordinates while it is over the dock, otherwise nil.
    @Published var mouseX: CGFloat?
    @Published var revealed = true
    /// True while an item's menu is open. The dock then holds still, so the icon stays under its menu.
    @Published var menuOpen = false
    /// Frame of the glass bar in window coordinates (top-left origin). Not published: only read by the tracker.
    var barFrame: CGRect = .zero
}

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DockWindowController {
    private let panel: DockPanel
    private let state = DockState()
    private let settings: DockSettings
    private var timer: Timer?
    private var lastActivity = Date()
    private var cancellables = Set<AnyCancellable>()

    init(model: DockModel, settings: DockSettings, nowPlaying: NowPlayingMonitor, battery: BatteryMonitor) {
        self.settings = settings

        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        let root = DockView(model: model, settings: settings, state: state,
                            nowPlaying: nowPlaying, battery: battery)
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.reposition()
        }
        settings.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reposition() } }
            .store(in: &cancellables)
    }

    func show() {
        guard timer == nil else { return }
        reposition()
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        state.mouseX = nil
        panel.orderOut(nil)
    }

    private func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        let scale = settings.magnification ? settings.maxScale : 1
        let height = DockLayout.windowHeight(iconSize: settings.iconSize, maxScale: scale)
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    /// Polls the cursor so the dock can magnify, auto-hide, and let clicks fall through
    /// the transparent parts of its full-width window.
    private func tick() {
        if state.menuOpen {
            lastActivity = Date()
            return
        }
        let mouse = NSEvent.mouseLocation
        let frame = panel.frame
        let local = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)

        var hit = state.barFrame
        if hit.width > 0 {
            let scale = settings.magnification ? settings.maxScale : 1
            let extraTop = state.mouseX != nil ? settings.iconSize * (scale - 1) : 0
            let top = hit.minY - extraTop
            hit = CGRect(x: hit.minX, y: top, width: hit.width, height: frame.height - top)
        }
        let inside = state.revealed && hit.contains(local)

        if settings.autoHide {
            let atBottomEdge = mouse.y <= frame.minY + 1 && mouse.x >= frame.minX && mouse.x <= frame.maxX
            if inside || atBottomEdge {
                lastActivity = Date()
                if !state.revealed { state.revealed = true }
            } else if state.revealed, Date().timeIntervalSince(lastActivity) > 0.6 {
                state.revealed = false
            }
        } else if !state.revealed {
            state.revealed = true
        }

        let newX: CGFloat? = inside ? local.x : nil
        if newX != state.mouseX { state.mouseX = newX }
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }
}
