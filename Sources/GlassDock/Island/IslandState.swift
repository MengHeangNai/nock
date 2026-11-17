import AppKit
import Combine

enum IslandTab: String, CaseIterable, Identifiable {
    case home, nowPlaying, lyrics, timer, battery, upNext, shelf, clipboard, notes
    case terminal, aiUsage, colorPicker, keepAwake, downloads, devices, stats, windows

    var id: String { rawValue }

    var isLeftOfNotch: Bool {
        switch self {
        case .home, .nowPlaying, .lyrics, .timer, .battery, .upNext, .shelf, .clipboard, .notes: return true
        default: return false
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .nowPlaying: return "music.note"
        case .lyrics: return "quote.bubble.fill"
        case .timer: return "timer"
        case .battery: return "battery.75percent"
        case .upNext: return "calendar"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .notes: return "note.text"
        case .terminal: return "terminal.fill"
        case .aiUsage: return "gauge.with.dots.needle.67percent"
        case .colorPicker: return "eyedropper"
        case .keepAwake: return "cup.and.saucer.fill"
        case .downloads: return "arrow.down.circle"
        case .devices: return "headphones"
        case .stats: return "chart.xyaxis.line"
        case .windows: return "pin.fill"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .nowPlaying: return "Now Playing"
        case .lyrics: return "Lyrics"
        case .timer: return "Timer"
        case .battery: return "Battery"
        case .upNext: return "Up Next"
        case .shelf: return "Shelf"
        case .clipboard: return "Clipboard"
        case .notes: return "Notes"
        case .terminal: return "Terminal"
        case .aiUsage: return "AI Usage"
        case .colorPicker: return "Color Picker"
        case .keepAwake: return "Keep Awake"
        case .downloads: return "Downloads"
        case .devices: return "Devices"
        case .stats: return "Stats"
        case .windows: return "Windows"
        }
    }
}

enum LiveActivity: Equatable {
    case timerDone
    case charging(Int)
    case timer
    case music
}

struct IslandMetrics: Equatable {
    var notchWidth: CGFloat = 150
    var notchHeight: CGFloat = 32
    var hasNotch = false
    var centerX: CGFloat = 0
    var screenTop: CGFloat = 0

    init() {}

    init(screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top,
                  topLeftWidth: screen.auxiliaryTopLeftArea?.width, topRightWidth: screen.auxiliaryTopRightArea?.width)
    }

    init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat, topLeftWidth: CGFloat?, topRightWidth: CGFloat?) {
        if safeAreaTop > 0, let topLeftWidth, let topRightWidth {
            hasNotch = true
            notchWidth = frame.width - topLeftWidth - topRightWidth
            notchHeight = safeAreaTop
            centerX = frame.midX + (topLeftWidth - topRightWidth) / 2
        } else {
            hasNotch = false
            notchWidth = 150
            notchHeight = max(frame.maxY - visibleFrame.maxY, 24)
            centerX = frame.midX
        }
        screenTop = frame.maxY
    }

    var wingWidth: CGFloat { (notchHeight * (hasNotch ? 1.6 : 2.2)).rounded() }
    var petWingWidth: CGFloat { (notchHeight * (hasNotch ? 0.95 : 1.3)).rounded() }
    var petSize: CGSize { CGSize(width: notchWidth + petWingWidth * 2, height: notchHeight) }
    var expandedSize: CGSize { CGSize(width: max(840, notchWidth + 640), height: notchHeight + 200) }
    var hudSize: CGSize { CGSize(width: 300, height: notchHeight + 66) }
    var notificationSize: CGSize { CGSize(width: 300, height: notchHeight + 58) }
}

enum IslandWithoutNotchMode: String, CaseIterable, Identifiable {
    case alwaysShown, onHover, off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alwaysShown: return "Always shown"
        case .onHover: return "Show on hover"
        case .off: return "Off"
        }
    }

    func showsIsland(hasNotch: Bool) -> Bool {
        hasNotch || self != .off
    }

    func showsIdlePill(hasNotch: Bool) -> Bool {
        hasNotch || self == .alwaysShown
    }
}

enum IslandFinish: String, CaseIterable, Identifiable {
    case black, liquidGlass, dynamicGlass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return "Black"
        case .liquidGlass: return "Liquid Glass"
        case .dynamicGlass: return "Dynamic Glass"
        }
    }
}

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var tab: IslandTab = .home
    @Published var metrics = IslandMetrics()
    @Published var isHiddenForFullScreen = false
    @Published private(set) var chargingFlash = false

    private let settings: DockSettings
    private let nowPlaying: NowPlayingMonitor
    private let timer: IslandTimer
    private let battery: BatteryMonitor
    private let systemHUD: SystemHUDController
    private let notifications: SystemNotificationController
    private var cancellables = Set<AnyCancellable>()
    private var chargingWork: DispatchWorkItem?
    private var timerDoneWork: DispatchWorkItem?

    init(settings: DockSettings, nowPlaying: NowPlayingMonitor, timer: IslandTimer, battery: BatteryMonitor,
         systemHUD: SystemHUDController, notifications: SystemNotificationController) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.timer = timer
        self.battery = battery
        self.systemHUD = systemHUD
        self.notifications = notifications

        battery.$isPluggedIn
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in self?.flashCharging() }
            .store(in: &cancellables)

        timer.$didFinish
            .filter { $0 }
            .sink { [weak self] _ in
                self?.timerDoneWork?.cancel()
                let work = DispatchWorkItem { [weak timer] in timer?.dismissFinished() }
                self?.timerDoneWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
            }
            .store(in: &cancellables)
    }

    var hud: HUDReading? { systemHUD.hud }

    var notification: IslandNotification? { hud == nil && !isHiddenForFullScreen ? notifications.current : nil }

    var live: LiveActivity? {
        if timer.didFinish { return .timerDone }
        if chargingFlash { return .charging(battery.level ?? 0) }
        if timer.isActive { return .timer }
        if nowPlaying.isPlaying { return .music }
        return nil
    }

    var isIdlePillHidden: Bool {
        !expanded && hud == nil && notification == nil
            && (isHiddenForFullScreen || !settings.islandWithoutNotch.showsIdlePill(hasNotch: metrics.hasNotch))
    }

    var showsPet: Bool {
        settings.showNotchPet && !expanded && hud == nil && notification == nil && live == nil && !isIdlePillHidden
    }

    var size: CGSize {
        if expanded { return metrics.expandedSize }
        if hud != nil { return metrics.hudSize }
        if notification != nil { return metrics.notificationSize }
        if live != nil {
            return CGSize(width: metrics.notchWidth + metrics.wingWidth * 2, height: metrics.notchHeight)
        }
        if showsPet { return metrics.petSize }
        return CGSize(width: metrics.notchWidth, height: metrics.notchHeight)
    }

    private func flashCharging() {
        chargingWork?.cancel()
        chargingFlash = true
        let work = DispatchWorkItem { [weak self] in self?.chargingFlash = false }
        chargingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
