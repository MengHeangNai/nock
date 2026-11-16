import AppKit
import Combine

final class SystemNotificationController: ObservableObject {
    private static let quietAfterWakeSeconds: TimeInterval = 6

    @Published private(set) var current: IslandNotification?

    private let settings: DockSettings
    private let battery: BatteryMonitor
    private let bluetooth = BluetoothMonitor()
    private let wifi = WiFiMonitor()
    private var queue = NotificationQueue()
    private var batteryTracker = BatteryAlertTracker()
    private var wifiTracker = WiFiTracker()
    private var timeoutWork: DispatchWorkItem?
    private var armedRevision = 0
    private var quietUntil = Date.distantPast
    private var isIslandShown = false
    private var isBluetoothRunning = false
    private var isWiFiRunning = false
    private var cancellables = Set<AnyCancellable>()
    private var batteryCancellable: AnyCancellable?

    init(settings: DockSettings, battery: BatteryMonitor, systemHUD: SystemHUDController) {
        self.settings = settings
        self.battery = battery

        systemHUD.$hud
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] isShowing in
                self?.queue.setSuppressed(isShowing)
                self?.sync()
            }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.quietUntil = .distantFuture }
            .store(in: &cancellables)
        workspace.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.quietUntil = Date().addingTimeInterval(Self.quietAfterWakeSeconds) }
            .store(in: &cancellables)

        bluetooth.onNotification = { [weak self] notification in self?.post(notification) }
        wifi.onChange = { [weak self] state in
            guard let notification = self?.wifiTracker.observe(state) else { return }
            self?.post(notification)
        }
    }

    func start() {
        isIslandShown = true
        batteryTracker = BatteryAlertTracker()
        _ = batteryTracker.observe(level: battery.level, isPluggedIn: battery.isPluggedIn)
        batteryCancellable = battery.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.observeBattery() }
        refresh()
    }

    func stop() {
        isIslandShown = false
        batteryCancellable = nil
        refresh()
        queue.reset()
        sync()
    }

    private func refresh() {
        let isOn = isIslandShown && settings.showSystemNotifications
        setBluetooth(running: isOn && settings.notifyBluetooth)
        setWiFi(running: isOn && settings.notifyWiFi)
    }

    private func setBluetooth(running: Bool) {
        guard running != isBluetoothRunning else { return }
        isBluetoothRunning = running
        if running { bluetooth.start() } else { bluetooth.stop() }
    }

    private func setWiFi(running: Bool) {
        guard running != isWiFiRunning else { return }
        isWiFiRunning = running
        if running {
            wifiTracker = WiFiTracker()
            if let state = wifi.state { _ = wifiTracker.observe(state) }
            wifi.start()
        } else {
            wifi.stop()
        }
    }

    private func observeBattery() {
        guard let alert = batteryTracker.observe(level: battery.level, isPluggedIn: battery.isPluggedIn),
              settings.showSystemNotifications, settings.notifyBattery else { return }
        post(.battery(alert))
    }

    private func post(_ notification: IslandNotification) {
        guard Date() >= quietUntil else { return }
        queue.post(notification)
        sync()
    }

    private func sync() {
        if current != queue.current { current = queue.current }
        guard let showing = queue.current else {
            timeoutWork?.cancel()
            timeoutWork = nil
            return
        }
        guard queue.revision != armedRevision else { return }
        armedRevision = queue.revision
        announce(showing)
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.queue.finishCurrent()
            self?.sync()
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + showing.duration, execute: work)
    }

    private func announce(_ notification: IslandNotification) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: notification.announcement,
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
