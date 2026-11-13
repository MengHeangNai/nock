import AppKit
import Combine

enum IslandTab: String, CaseIterable, Identifiable {
    // Left of the notch
    case home, nowPlaying, lyrics, timer, battery, upNext, shelf, clipboard, notes
    // Right of the notch
    case terminal, aiUsage, colorPicker, keepAwake, downloads, devices, stats

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
        }
    }
}

/// Something shown in the "wings" beside the notch while the island is collapsed.
enum LiveActivity: Equatable {
    case timerDone
    case charging(Int)
    case timer
    case music
}

/// Notch geometry for one screen. On Macs without a notch, a pill in the menu bar stands in for it.
struct IslandMetrics: Equatable {
    var notchWidth: CGFloat = 150
    var notchHeight: CGFloat = 32
    var hasNotch = false
    var centerX: CGFloat = 0
    var screenTop: CGFloat = 0

    init() {}

    init(screen: NSScreen) {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchWidth = frame.width - left.width - right.width
            notchHeight = screen.safeAreaInsets.top
            centerX = frame.midX + (left.width - right.width) / 2
        } else {
            hasNotch = false
            notchWidth = 150
            notchHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
            centerX = frame.midX
        }
        screenTop = frame.maxY
    }

    var wingWidth: CGFloat { (notchHeight * (hasNotch ? 1.6 : 2.2)).rounded() }
    var expandedSize: CGSize { CGSize(width: max(840, notchWidth + 640), height: notchHeight + 200) }
}

final class IslandState: ObservableObject {
    @Published var expanded = false
    @Published var tab: IslandTab = .home
    @Published var metrics = IslandMetrics()
    @Published private(set) var chargingFlash = false

    private let nowPlaying: NowPlayingMonitor
    private let timer: IslandTimer
    private let battery: BatteryMonitor
    private var cancellables = Set<AnyCancellable>()
    private var chargingWork: DispatchWorkItem?
    private var timerDoneWork: DispatchWorkItem?

    init(nowPlaying: NowPlayingMonitor, timer: IslandTimer, battery: BatteryMonitor) {
        self.nowPlaying = nowPlaying
        self.timer = timer
        self.battery = battery

        // Briefly show the charge level when the power cable is connected.
        battery.$isPluggedIn
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in self?.flashCharging() }
            .store(in: &cancellables)

        // Dismiss the "timer done" alert by itself after a while.
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

    var live: LiveActivity? {
        if timer.didFinish { return .timerDone }
        if chargingFlash { return .charging(battery.level ?? 0) }
        if timer.isActive { return .timer }
        if nowPlaying.isPlaying { return .music }
        return nil
    }

    var size: CGSize {
        if expanded { return metrics.expandedSize }
        if live != nil {
            return CGSize(width: metrics.notchWidth + metrics.wingWidth * 2, height: metrics.notchHeight)
        }
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
