import SwiftUI
import UniformTypeIdentifiers

final class IslandContext {
    let settings: DockSettings
    let nowPlaying: NowPlayingMonitor
    let battery: BatteryMonitor
    let lyrics: LyricsService
    let timer: IslandTimer
    let shelf: ShelfStore
    let clipboard: ClipboardStore
    let notes: NotesStore
    let stats: SystemStats
    let systemHUD: SystemHUDController
    let notifications: SystemNotificationController
    let keyboardSounds: KeyboardSoundController
    let agents: AgentActivityMonitor
    let audioLevels = AudioLevelMonitor()
    let calendar = CalendarService()
    let keepAwake = KeepAwake()
    let colors = ColorPickerStore()
    let downloads = DownloadsWatcher()
    let devices = DevicesService()
    let aiUsage = AIUsageService()
    let terminal = TerminalSession()
    let pet: NotchPetMonitor
    let pinnedWindows = PinnedWindowController()
    let pip: PiPController

    init(settings: DockSettings, nowPlaying: NowPlayingMonitor, battery: BatteryMonitor,
         lyrics: LyricsService, timer: IslandTimer, shelf: ShelfStore, clipboard: ClipboardStore,
         notes: NotesStore, stats: SystemStats, systemHUD: SystemHUDController,
         notifications: SystemNotificationController, keyboardSounds: KeyboardSoundController) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.battery = battery
        self.lyrics = lyrics
        self.timer = timer
        self.shelf = shelf
        self.clipboard = clipboard
        self.notes = notes
        self.stats = stats
        self.systemHUD = systemHUD
        self.notifications = notifications
        self.keyboardSounds = keyboardSounds
        agents = AgentActivityMonitor(settings: settings)
        pet = NotchPetMonitor(settings: settings, nowPlaying: nowPlaying, battery: battery, shelf: shelf)
        pip = PiPController(settings: settings)
    }
}

struct IslandView: View {
    let context: IslandContext
    @ObservedObject private var state: IslandState
    @ObservedObject private var settings: DockSettings
    @ObservedObject private var nowPlaying: NowPlayingMonitor
    @ObservedObject private var timer: IslandTimer
    @ObservedObject private var systemHUD: SystemHUDController
    @ObservedObject private var notifications: SystemNotificationController
    @ObservedObject private var pet: NotchPetMonitor
    @ObservedObject private var battery: BatteryMonitor
    @ObservedObject private var agents: AgentActivityMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxShoulderRadius: CGFloat = 36

    init(context: IslandContext, state: IslandState) {
        self.context = context
        _state = ObservedObject(wrappedValue: state)
        _settings = ObservedObject(wrappedValue: context.settings)
        _nowPlaying = ObservedObject(wrappedValue: context.nowPlaying)
        _timer = ObservedObject(wrappedValue: context.timer)
        _systemHUD = ObservedObject(wrappedValue: context.systemHUD)
        _notifications = ObservedObject(wrappedValue: context.notifications)
        _pet = ObservedObject(wrappedValue: context.pet)
        _battery = ObservedObject(wrappedValue: context.battery)
        _agents = ObservedObject(wrappedValue: context.agents)
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }

    private var visibleTabs: [IslandTab] {
        IslandTab.allCases.filter { $0 == .home || !settings.hiddenIslandTabs.contains($0.rawValue) }
    }

    var body: some View {
        let metrics = state.metrics
        let size = state.size
        let isOpen = state.expanded || state.hud != nil || state.notification != nil
        let shoulderRadius = min((isOpen ? 22 : 10) * settings.islandShoulderCurve, Self.maxShoulderRadius)
        let shape = IslandShape(topRadius: shoulderRadius,
                                bottomRadius: isOpen ? min(44 * settings.islandCornerCurve, size.height * 0.45)
                                                     : metrics.notchHeight * 0.5 * settings.islandCornerCurve)
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.12)
        let wingAnimation: Animation = reduceMotion ? animation : .easeOut(duration: 0.3)
        let finish = battery.lowPowerMode ? .black : settings.islandFinish

        ZStack(alignment: .top) {
            if state.expanded {
                expandedContent(metrics)
                    .overlay(alignment: .top) { expandedOverlay(metrics) }
                    .transition(contentTransition)
            } else if let reading = state.hud {
                hudContent(reading, metrics: metrics)
                    .transition(contentTransition)
            } else if let notification = state.notification {
                notificationContent(notification, metrics: metrics)
                    .transition(contentTransition)
            } else if let live = state.live, let wings = state.wings, !state.isIdlePillHidden {
                if wings.isBelowNotch {
                    dropDown(metrics, inset: metrics.wingPadding) { belowNotchContent(live, metrics: metrics) }
                        .transition(contentTransition)
                } else {
                    collapsedContent(live, wings: wings, metrics: metrics)
                        .transition(contentTransition)
                }
            } else if state.showsPet {
                petContent(metrics)
                    .transition(contentTransition)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .padding(.horizontal, shoulderRadius)
        .background { islandBackground(finish, shape: shape, notchHeight: metrics.notchHeight) }
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(state.expanded ? 0.45 : 0), radius: 16, y: 6)
        .opacity(state.isIdlePillHidden ? 0 : 1)
        .onTapGesture {
            if timer.didFinish { timer.dismissFinished() }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            context.shelf.add(providers)
            state.tab = .shelf
            return true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .offset(x: state.xOffset)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(wingAnimation, value: state.wings)
        .animation(animation, value: state.expanded)
        .animation(animation, value: state.live)
        .animation(animation, value: state.showsPet)
        .animation(animation, value: state.hud != nil)
        .animation(animation, value: state.notification != nil)
        .animation(animation, value: finish)
        .animation(animation, value: settings.islandShoulderCurve)
        .animation(animation, value: settings.islandCornerCurve)
    }

    private func islandBackground(_ finish: IslandFinish, shape: IslandShape, notchHeight: CGFloat) -> some View {
        ZStack {
            if finish != .black {
                if #available(macOS 26.0, *) {
                    Color.clear.glassEffect(.regular, in: shape)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
            }
            Color.black.opacity(finish == .black ? 1 : 0.35)
                .overlay(alignment: .top) {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 0.55),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: notchHeight * 1.8)
                        .opacity(finish == .dynamicGlass ? 1 : 0)
                }
        }
    }

    private func hudContent(_ reading: HUDReading, metrics: IslandMetrics) -> some View {
        dropDown(metrics, inset: 24) { HUDView(reading: reading) }
    }

    private func notificationContent(_ notification: IslandNotification, metrics: IslandMetrics) -> some View {
        dropDown(metrics, inset: 24) { NotificationView(notification: notification) }
    }

    private func dropDown<Content: View>(_ metrics: IslandMetrics, inset: CGFloat,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notchHeight)
            content()
                .padding(.horizontal, inset)
                .frame(maxHeight: .infinity)
        }
    }

    private func collapsedContent(_ live: LiveActivity, wings: IslandWings, metrics: IslandMetrics) -> some View {
        HStack(spacing: 0) {
            leftWing(live, isCompact: wings.fit == .compact)
                .padding(.leading, metrics.wingPadding)
                .frame(width: wings.leftWidth, alignment: .leading)
            Spacer(minLength: metrics.notchWidth)
            if wings.fit == .full {
                rightWing(live)
                    .padding(.trailing, metrics.wingPadding)
                    .frame(width: wings.rightWidth, alignment: .trailing)
            }
        }
        .frame(height: metrics.notchHeight)
    }

    private func belowNotchContent(_ live: LiveActivity, metrics: IslandMetrics) -> some View {
        HStack(spacing: metrics.wingPadding) {
            leftWing(live, isCompact: false)
            rightWing(live)
        }
    }

    private func petContent(_ metrics: IslandMetrics) -> some View {
        HStack(spacing: 0) {
            NotchPetView(mood: pet.mood, stage: pet.stage, size: metrics.notchHeight * 0.78)
                .frame(width: metrics.petWingWidth)
            Spacer(minLength: metrics.notchWidth)
        }
        .frame(height: metrics.notchHeight)
    }

    @ViewBuilder
    private func leftWing(_ live: LiveActivity, isCompact: Bool) -> some View {
        switch live {
        case .music:
            ArtworkView(nowPlaying: nowPlaying, size: state.metrics.artworkSize)
        case .timer:
            wingGlyph("timer", color: .orange)
        case .timerDone:
            wingGlyph("bell.fill", color: .orange)
        case .charging:
            wingGlyph("bolt.fill", color: .green)
        case .agent:
            if let lead = agents.lead {
                AgentStatusWing(session: lead, count: agents.sessions.count, isCompact: isCompact)
            }
        }
    }

    private func wingGlyph(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .frame(width: IslandMetrics.wingGlyphWidth)
    }

    @ViewBuilder
    private func rightWing(_ live: LiveActivity) -> some View {
        switch live {
        case .music:
            PlayingBars(color: nowPlaying.accentColor, audio: context.audioLevels)
        case .timer:
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(IslandTimer.format(timer.remaining(at: context.date)))
                    .font(Font(IslandMetrics.wingLabelFont))
                    .monospacedDigit()
                    .foregroundStyle(timer.isPaused ? Color.secondary : Color.orange)
            }
        case .timerDone, .charging:
            Text(live.wingLabel ?? "")
                .font(Font(IslandMetrics.wingLabelFont))
                .foregroundStyle(live == .timerDone ? Color.orange : Color.green)
        case .agent:
            if let lead = agents.lead {
                AgentLinesWing(session: lead, count: agents.sessions.count)
            }
        }
    }

    @ViewBuilder
    private func expandedOverlay(_ metrics: IslandMetrics) -> some View {
        if let reading = state.hud {
            floatingCard(metrics) { HUDView(reading: reading) }
        } else if let notification = state.notification {
            floatingCard(metrics) { NotificationView(notification: notification) }
        }
    }

    private func floatingCard<Content: View>(_ metrics: IslandMetrics, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(width: metrics.hudSize.width)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            .padding(.top, metrics.notchHeight + 10)
            .transition(contentTransition)
    }

    private func expandedContent(_ metrics: IslandMetrics) -> some View {
        let tabs = visibleTabs
        let current = tabs.contains(state.tab) ? state.tab : .home

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach(tabs.filter(\.isLeftOfNotch)) { tabButton($0, current: current) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear.frame(width: metrics.notchWidth + 12)

                HStack(spacing: 2) {
                    ForEach(tabs.filter { !$0.isLeftOfNotch }) { tabButton($0, current: current) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .frame(height: metrics.notchHeight)

            tabContent(current)
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 18 * max(settings.islandCornerCurve, DockSettings.defaultIslandCurve))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tabButton(_ tab: IslandTab, current: IslandTab) -> some View {
        Button { state.tab = tab } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 22)
                .background(current == tab ? Color.white.opacity(0.16) : .clear, in: Capsule())
                .foregroundStyle(current == tab ? Color.white : Color.white.opacity(0.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLabel(tab.title, edge: .bottom)
    }

    @ViewBuilder
    private func tabContent(_ tab: IslandTab) -> some View {
        let c = context
        switch tab {
        case .home:
            HomeDashboard(nowPlaying: c.nowPlaying, calendar: c.calendar, battery: c.battery,
                          settings: c.settings, pet: c.pet, state: state)
        case .nowPlaying: NowPlayingTab(nowPlaying: c.nowPlaying, lyrics: c.lyrics, timer: c.timer, settings: c.settings,
                                       audio: c.audioLevels, state: state)
        case .lyrics: LyricsTab(nowPlaying: c.nowPlaying, lyrics: c.lyrics, settings: c.settings)
        case .timer: TimerTab(timer: c.timer)
        case .battery: BatteryTab(battery: c.battery)
        case .upNext: UpNextTab(calendar: c.calendar)
        case .shelf: ShelfTab(shelf: c.shelf)
        case .clipboard: ClipboardTab(clipboard: c.clipboard)
        case .notes: NotesTab(notes: c.notes)
        case .terminal: TerminalTab(terminal: c.terminal)
        case .aiUsage: AIUsageTab(usage: c.aiUsage, settings: c.settings, agents: c.agents)
        case .colorPicker: ColorPickerTab(colors: c.colors)
        case .keepAwake: KeepAwakeTab(keepAwake: c.keepAwake)
        case .downloads: DownloadsTab(downloads: c.downloads)
        case .devices: DevicesTab(devices: c.devices, battery: c.battery)
        case .stats: StatsTab(stats: c.stats)
        case .windows: WindowsTab(controller: c.pinnedWindows, pip: c.pip)
        case .keyboard: KeyboardTab(sounds: c.keyboardSounds, settings: c.settings)
        }
    }
}

private struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4, rect.height / 2)
        let left = rect.minX + top
        let right = rect.maxX - top
        let bottom = min(bottomRadius, rect.height - top, (right - left) / 2)
        let pull = bottom * 0.4

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + top), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addCurve(to: CGPoint(x: left + bottom, y: rect.maxY),
                      control1: CGPoint(x: left, y: rect.maxY - pull),
                      control2: CGPoint(x: left + pull, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addCurve(to: CGPoint(x: right, y: rect.maxY - bottom),
                      control1: CGPoint(x: right - pull, y: rect.maxY),
                      control2: CGPoint(x: right, y: rect.maxY - pull))
        path.addLine(to: CGPoint(x: right, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct PlayingBars: View {
    static let barWidth: CGFloat = 3
    private static let barGap: CGFloat = 2
    static let width = CGFloat(AudioLevelMonitor.bandCount) * (barWidth + barGap) - barGap

    var color: Color = .white
    @ObservedObject var audio: AudioLevelMonitor

    var body: some View {
        HStack(alignment: .center, spacing: Self.barGap) {
            ForEach(0..<AudioLevelMonitor.bandCount, id: \.self) { index in
                if audio.isCapturing {
                    Capsule()
                        .fill(color)
                        .frame(width: Self.barWidth, height: 4 + 12 * audio.levels[index])
                } else {
                    PlayingBar(color: color, duration: [0.42, 0.55, 0.36, 0.5][index], low: 4, high: [12, 15, 10, 13][index])
                }
            }
        }
        .frame(height: 16)
        .onAppear { audio.start() }
        .onDisappear { audio.stop() }
    }
}

private struct PlayingBar: View {
    let color: Color
    let duration: Double
    let low: CGFloat
    let high: CGFloat
    @State private var up = false

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: PlayingBars.barWidth, height: up ? high : low)
            .onAppear {
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) { up = true }
            }
    }
}
