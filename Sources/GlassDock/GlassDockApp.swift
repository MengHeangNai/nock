import AppKit
import SwiftUI
import Combine

@main
enum GlassDockMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = DockSettings.shared
    private lazy var model = DockModel(settings: settings)

    // Shared between modules.
    private let nowPlaying = NowPlayingMonitor()
    private let battery = BatteryMonitor()
    private let clipboard = ClipboardStore()
    private let shelf = ShelfStore()
    private let islandTimer = IslandTimer()
    private let notes = NotesStore()
    private let stats = SystemStats()
    private lazy var systemHUD = SystemHUDController(settings: settings)
    private lazy var notifications = SystemNotificationController(settings: settings, battery: battery, systemHUD: systemHUD)
    private lazy var lyrics = LyricsService(nowPlaying: nowPlaying, settings: settings)

    private var dockWindow: DockWindowController?
    private var islandWindow: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        clipboard.start()

        let dock = DockWindowController(model: model, settings: settings,
                                        nowPlaying: nowPlaying, battery: battery)
        dockWindow = dock

        let context = IslandContext(settings: settings, nowPlaying: nowPlaying,
                                    battery: battery, lyrics: lyrics, timer: islandTimer, shelf: shelf,
                                    clipboard: clipboard, notes: notes, stats: stats, systemHUD: systemHUD,
                                    notifications: notifications)
        let island = IslandWindowController(context: context)
        islandWindow = island

        settings.$enableDock
            .removeDuplicates()
            .sink { enabled in enabled ? dock.show() : dock.hide() }
            .store(in: &cancellables)
        settings.$enableIsland
            .removeDuplicates()
            .sink { enabled in enabled ? island.show() : island.hide() }
            .store(in: &cancellables)

        setUpStatusItem()

        if settings.hideSystemDock {
            SystemDock.hide()
        } else if SystemDock.isHiddenByGlassDock {
            // A previous run hid the macOS Dock and didn't get to restore it.
            SystemDock.restore()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        islandWindow?.closePiPs()
        systemHUD.stop()
        if SystemDock.isHiddenByGlassDock {
            SystemDock.restore()
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "GlassDock")

        let menu = NSMenu()
        menu.addItem(withTitle: "GlassDock Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit GlassDock", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(settings: settings, model: model, systemHUD: systemHUD))
            let window = NSWindow(contentViewController: host)
            window.title = "GlassDock Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
