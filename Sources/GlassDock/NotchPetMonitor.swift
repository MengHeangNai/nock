import AppKit
import Combine

final class NotchPetMonitor: ObservableObject {
    @Published private(set) var mood = PetMood.idle
    @Published private(set) var stage = PetStage.baby

    private static let pollInterval: TimeInterval = 3
    private static let celebrationSeconds: TimeInterval = 4
    private static let anyInputEvent = CGEventType(rawValue: ~0) ?? .mouseMoved

    private let settings: DockSettings
    private let nowPlaying: NowPlayingMonitor
    private let battery: BatteryMonitor
    private var isCelebrating = false
    private var celebrationEnd: DispatchWorkItem?
    private var shelfCount: Int
    private var poll: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(settings: DockSettings, nowPlaying: NowPlayingMonitor, battery: BatteryMonitor, shelf: ShelfStore) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        self.battery = battery
        shelfCount = shelf.files.count

        nowPlaying.$isPlaying.removeDuplicates().map { _ in }
            .merge(with: battery.$level.removeDuplicates().map { _ in },
                   battery.$isPluggedIn.removeDuplicates().map { _ in })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &cancellables)

        battery.$isPluggedIn
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in self?.celebrate() }
            .store(in: &cancellables)

        shelf.$files
            .sink { [weak self] files in
                guard let self else { return }
                if files.count > self.shelfCount { self.celebrate() }
                self.shelfCount = files.count
            }
            .store(in: &cancellables)

        settings.$showNotchPet
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in enabled ? self?.startPolling() : self?.stopPolling() }
            .store(in: &cancellables)
    }

    deinit {
        poll?.invalidate()
    }

    private func startPolling() {
        poll?.invalidate()
        refresh()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    private func refresh() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: Self.anyInputEvent)
        let nextMood = PetMood.decide(idleSeconds: idle, isMusicPlaying: nowPlaying.isPlaying,
                                      batteryLevel: battery.level, isOnBattery: !battery.isPluggedIn,
                                      isCelebrating: isCelebrating)
        if mood != nextMood { mood = nextMood }
        let nextStage = PetStage(firstLaunch: settings.firstLaunchDate, now: Date())
        if stage != nextStage { stage = nextStage }
    }

    private func celebrate() {
        celebrationEnd?.cancel()
        isCelebrating = true
        refresh()
        let work = DispatchWorkItem { [weak self] in
            self?.isCelebrating = false
            self?.refresh()
        }
        celebrationEnd = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.celebrationSeconds, execute: work)
    }
}
