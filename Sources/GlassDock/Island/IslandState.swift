import AppKit
import Combine

enum IslandTab: String, CaseIterable, Identifiable {
    case home, nowPlaying, lyrics, timer, battery, upNext, shelf, clipboard, notes
    case terminal, aiUsage, colorPicker, keepAwake, downloads, devices, stats, windows, keyboard

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
        case .keyboard: return "keyboard"
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
        case .keyboard: return "Keyboard"
        }
    }
}

enum LiveActivity: Equatable {
    case timerDone
    case charging(Int)
    case timer
    case music
    case agent

    var wingLabel: String? {
        switch self {
        case .timerDone: return "Done"
        case .charging(let level): return "\(level)%"
        case .timer, .music, .agent: return nil
        }
    }
}

struct WingSide: Equatable {
    static let empty = WingSide(full: 0, compact: 0)

    var full: CGFloat
    var compact: CGFloat?
}

enum WingFit: Equatable {
    case full, compact, belowNotch

    static let leeway: CGFloat = 6

    init(_ side: WingSide, gap: CGFloat?) {
        let room = (gap ?? .infinity) - Self.leeway
        if side.full == 0 || side.full <= room {
            self = .full
        } else if let compact = side.compact, compact == 0 || compact <= room {
            self = .compact
        } else {
            self = .belowNotch
        }
    }

    func width(of side: WingSide) -> CGFloat {
        switch self {
        case .full: return side.full
        case .compact: return side.compact ?? side.full
        case .belowNotch: return 0
        }
    }

    func worst(_ other: WingFit) -> WingFit {
        (self == .belowNotch || other == .belowNotch) ? .belowNotch : (self == .compact || other == .compact) ? .compact : .full
    }
}

struct IslandWings: Equatable {
    let left: WingSide
    let right: WingSide
    let fit: WingFit

    init(left: WingSide, right: WingSide, gaps: MenuBarGaps?) {
        self.left = left
        self.right = right
        fit = WingFit(left, gap: gaps?.left).worst(WingFit(right, gap: gaps?.right))
    }

    var isBelowNotch: Bool { fit == .belowNotch }
    var leftWidth: CGFloat { fit.width(of: left) }
    var rightWidth: CGFloat { fit.width(of: right) }
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

    static let wingGlyphWidth: CGFloat = 16
    static let wingLabelFont = NSFont.rounded(ofSize: 13, weight: .semibold)

    var wingPadding: CGFloat { (notchHeight * 0.3).rounded() }
    var artworkSize: CGFloat { notchHeight * 0.62 }
    var agentWingMaxWidth: CGFloat { (notchHeight * (hasNotch ? 3.2 : 4)).rounded() }

    func wingWidth(content: CGFloat, inner: CGFloat? = nil) -> CGFloat {
        content > 0 ? (content + wingPadding + (inner ?? wingPadding)).rounded(.up) : 0
    }

    var petWingWidth: CGFloat { (notchHeight * (hasNotch ? 0.95 : 1.3)).rounded() }
    var petSize: CGSize { CGSize(width: notchWidth + petWingWidth * 2, height: notchHeight) }
    var belowNotchSize: CGSize { CGSize(width: notchWidth, height: notchHeight + artworkSize + wingPadding) }
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
    @Published var menuBarGaps: MenuBarGaps?
    @Published private(set) var chargingFlash = false

    private let settings: DockSettings
    private let nowPlaying: NowPlayingMonitor
    private let timer: IslandTimer
    private let battery: BatteryMonitor
    private let systemHUD: SystemHUDController
    private let notifications: SystemNotificationController
    private let agents: AgentActivityMonitor
    private var cancellables = Set<AnyCancellable>()
    private var chargingWork: DispatchWorkItem?
    private var timerDoneWork: DispatchWorkItem?

    init(settings: DockSettings, nowPlaying: NowPlayingMonitor, timer: IslandTimer, battery: BatteryMonitor,
         systemHUD: SystemHUDController, notifications: SystemNotificationController, agents: AgentActivityMonitor) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.timer = timer
        self.battery = battery
        self.systemHUD = systemHUD
        self.notifications = notifications
        self.agents = agents

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
        if agents.lead?.isWaiting == true { return .agent }
        if timer.isActive { return .timer }
        if nowPlaying.isPlaying { return .music }
        if agents.lead != nil { return .agent }
        return nil
    }

    var isIdlePillHidden: Bool {
        !expanded && hud == nil && notification == nil
            && (isHiddenForFullScreen || !settings.islandWithoutNotch.showsIdlePill(hasNotch: metrics.hasNotch))
    }

    var showsWings: Bool {
        !expanded && hud == nil && notification == nil && !isIdlePillHidden && (live != nil || settings.showNotchPet)
    }

    var showsPet: Bool {
        showsWings && live == nil
            && IslandWings(left: WingSide(full: metrics.petWingWidth), right: WingSide(full: metrics.petWingWidth),
                    gaps: menuBarGaps).fit == .full
    }

    var wings: IslandWings? {
        live.map { live in
            let sides = wingSides(for: live)
            return IslandWings(left: sides.left, right: sides.right, gaps: menuBarGaps)
        }
    }

    var size: CGSize {
        if expanded { return metrics.expandedSize }
        if hud != nil { return metrics.hudSize }
        if notification != nil { return metrics.notificationSize }
        if let wings {
            if wings.isBelowNotch { return metrics.belowNotchSize }
            return CGSize(width: metrics.notchWidth + wings.leftWidth + wings.rightWidth, height: metrics.notchHeight)
        }
        if showsPet { return metrics.petSize }
        return CGSize(width: metrics.notchWidth, height: metrics.notchHeight)
    }

    /// The wings can differ in width, so the island shifts to keep its notch part over the real notch.
    var xOffset: CGFloat {
        guard !expanded, hud == nil, notification == nil, let wings, !wings.isBelowNotch else { return 0 }
        return (wings.rightWidth - wings.leftWidth) / 2
    }

    private func wingSides(for live: LiveActivity) -> (left: WingSide, right: WingSide) {
        let metrics = metrics
        let glyph = WingSide(full: metrics.wingWidth(content: IslandMetrics.wingGlyphWidth))
        let label = { (text: String) in metrics.wingWidth(content: IslandMetrics.wingLabelFont.lineWidth(of: text)) }
        switch live {
        case .timerDone, .charging:
            return (glyph, WingSide(full: label(live.wingLabel ?? ""), compact: 0))
        case .timer:
            return (glyph, WingSide(full: label(IslandTimer.format(timer.remaining()))))
        case .music:
            return (WingSide(full: metrics.wingWidth(content: metrics.artworkSize, inner: metrics.wingPadding / 2)),
                    WingSide(full: metrics.wingWidth(content: PlayingBars.width, inner: metrics.wingPadding / 2), compact: 0))
        case .agent:
            guard let lead = agents.lead else { return (.empty, .empty) }
            let status = metrics.wingWidth(content: AgentStatusWing.contentWidth(of: lead))
            let lines = metrics.wingWidth(content: AgentLinesWing.contentWidth(of: lead, count: agents.sessions.count))
            return (WingSide(full: min(status, metrics.agentWingMaxWidth), compact: glyph.full),
                    WingSide(full: lines, compact: 0))
        }
    }

    private func flashCharging() {
        chargingWork?.cancel()
        chargingFlash = true
        let work = DispatchWorkItem { [weak self] in self?.chargingFlash = false }
        chargingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}

extension NSFont {
    private static let lineWidths = NSCache<NSString, NSNumber>()

    static func rounded(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
    }

    func lineWidth(of text: String) -> CGFloat {
        let sample = String(text.map { $0.isNumber ? "0" : $0 })
        let key = "\(fontName) \(pointSize) \(sample)" as NSString
        if let width = Self.lineWidths.object(forKey: key) { return CGFloat(width.doubleValue) }
        let width = NSAttributedString(string: sample, attributes: [.font: self]).size().width.rounded(.up) + 1
        Self.lineWidths.setObject(NSNumber(value: Double(width)), forKey: key)
        return width
    }
}
