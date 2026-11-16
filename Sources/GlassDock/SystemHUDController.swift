import AppKit
import Combine

final class SystemHUDController: ObservableObject {
    static let visibleSeconds: TimeInterval = 1.5
    private static let accessCheckSeconds: TimeInterval = 2

    @Published private(set) var hud: HUDReading?
    @Published private(set) var access: HUDAccess = .settingOff

    private let volume = SystemVolumeMonitor()
    private let keyboard = KeyboardBacklight()
    private let worker = DispatchQueue(label: "GlassDock.SystemHUD", qos: .userInteractive)
    private lazy var tap = MediaKeyTap { [weak self] press in self?.handle(press) ?? false }
    private var brightnessDisplays = Set<CGDirectDisplayID>()
    private var lastBacklight: Float = 0 // only used on `worker`
    private var accessTimer: Timer?
    private var hideWork: DispatchWorkItem?
    private var replacesSystemHUD: Bool
    private var isIslandShown = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: DockSettings) {
        replacesSystemHUD = settings.replaceSystemHUD
        volume.onChange = { [weak self] reading in self?.show(reading) }

        settings.$replaceSystemHUD
            .removeDuplicates()
            .sink { [weak self] replaces in
                self?.replacesSystemHUD = replaces
                self?.refresh()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refreshBrightnessDisplays() }
            .store(in: &cancellables)
    }

    func start() {
        isIslandShown = true
        refresh()
    }

    func stop() {
        isIslandShown = false
        refresh()
    }

    private func refresh() {
        HUDDiag.note("refresh: setting=\(replacesSystemHUD) island=\(isIslandShown) trusted=\(AppWindows.isTrusted)") // TEMP-HUD-DIAG
        let wasEnabled = access.isEnabled
        updateAccess()
        guard access.isEnabled != wasEnabled else { return }
        if access.isEnabled {
            volume.start()
            refreshBrightnessDisplays()
            let timer = Timer(timeInterval: Self.accessCheckSeconds, repeats: true) { [weak self] _ in self?.updateAccess() }
            RunLoop.main.add(timer, forMode: .common)
            accessTimer = timer
        } else {
            accessTimer?.invalidate()
            accessTimer = nil
            volume.stop()
            hideWork?.cancel()
            hideWork = nil
            hud = nil
        }
    }

    private func updateAccess() {
        let next = HUDAccess.resolve(replacesSystemHUD: replacesSystemHUD, isIslandShown: isIslandShown,
                                     isTrusted: AppWindows.isTrusted) { tap.start() }
        if next != .replacing { tap.stop() }
        setAccess(next)
    }

    private func setAccess(_ value: HUDAccess) {
        if access != value {
            HUDDiag.note("access \(access) -> \(value)") // TEMP-HUD-DIAG
            access = value
        }
    }

    private func refreshBrightnessDisplays() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(ids.count), &ids, &count)
        brightnessDisplays = Set(ids.prefix(Int(count)).filter { DisplayBrightness.read($0) != nil })
    }

    /// Runs on the main thread inside the event tap, so it only decides and hands the work to `worker`.
    private func handle(_ press: MediaKeyPress) -> Bool {
        guard !press.isLeftToSystem, let work = work(for: press) else { return false }
        if press.isDown {
            let steps = press.isFineStep ? HUDStep.fine : HUDStep.standard
            worker.async { [weak self] in
                guard let reading = work(steps) else {
                    HUDDiag.note("action produced no reading key=\(press.key)") // TEMP-HUD-DIAG
                    return
                }
                DispatchQueue.main.async { self?.show(reading) }
            }
        }
        return true
    }

    private func work(for press: MediaKeyPress) -> ((Int) -> HUDReading?)? {
        switch press.key.action {
        case .step(.volume, let direction):
            guard volume.canSetVolume else { return nil }
            let device = volume.device
            return { steps in
                guard let current = SystemVolumeMonitor.reading(of: device) else { return nil }
                let target = HUDStep.next(from: current.value, direction: direction, steps: steps)
                guard SystemVolumeMonitor.setVolume(target, on: device) else { return nil }
                return HUDReading(kind: .volume, value: target)
            }
        case .toggleMute:
            guard volume.canSetMute else { return nil }
            let device = volume.device
            return { _ in
                guard let current = SystemVolumeMonitor.reading(of: device),
                      SystemVolumeMonitor.setMuted(!current.isMuted, on: device) else { return nil }
                return HUDReading(kind: .volume, value: current.value, isMuted: !current.isMuted)
            }
        case .step(.brightness, let direction):
            let cursorDisplay = displayUnderCursor()
            let builtIn = brightnessDisplays.first { CGDisplayIsBuiltin($0) != 0 }
            let chosen = BrightnessTarget.display(underCursor: cursorDisplay, adjustable: brightnessDisplays, builtIn: builtIn)
            HUDDiag.note("brightness cursor=\(String(describing: cursorDisplay)) adjustable=\(brightnessDisplays.sorted()) builtIn=\(String(describing: builtIn)) target=\(String(describing: chosen))") // TEMP-HUD-DIAG
            guard let display = chosen else { return nil }
            return { steps in
                guard let current = DisplayBrightness.read(display) else { return nil }
                let target = HUDStep.next(from: current, direction: direction, steps: steps)
                guard DisplayBrightness.write(target, to: display) else { return nil }
                return HUDReading(kind: .brightness, value: target)
            }
        case .step(.keyboardBacklight, let direction):
            guard let keyboard else { return nil }
            return { [weak self] steps in
                let target = HUDStep.next(from: keyboard.read(), direction: direction, steps: steps)
                guard keyboard.write(target) else { return nil }
                if target > 0 { self?.lastBacklight = target }
                return HUDReading(kind: .keyboardBacklight, value: target)
            }
        case .toggleBacklight:
            guard let keyboard else { return nil }
            return { [weak self] _ in
                let current = keyboard.read()
                if current > 0 { self?.lastBacklight = current }
                let target = HUDStep.toggledBacklight(from: current, previous: self?.lastBacklight ?? 0)
                guard keyboard.write(target) else { return nil }
                return HUDReading(kind: .keyboardBacklight, value: target)
            }
        }
    }

    private func displayUnderCursor() -> CGDirectDisplayID? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }?.displayID
    }

    private func show(_ reading: HUDReading) {
        HUDDiag.note("hud published kind=\(reading.kind) value=\(reading.value) muted=\(reading.isMuted)") // TEMP-HUD-DIAG
        if reading.kind == .volume { volume.acknowledge(reading) }
        hideWork?.cancel()
        if hud != reading { hud = reading }
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds, execute: work)
    }
}
