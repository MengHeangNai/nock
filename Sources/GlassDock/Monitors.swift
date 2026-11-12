import AppKit
import IOKit.ps

// MARK: - Battery

final class BatteryMonitor: ObservableObject {
    /// nil when the Mac has no internal battery.
    @Published private(set) var level: Int?
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var minutesRemaining: Int?
    @Published private(set) var minutesToFull: Int?
    @Published private(set) var cycleCount: Int?
    @Published private(set) var healthPercent: Int?
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var timer: Timer?

    init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.update() }

        // Update right away when the power source changes (cable plugged in or removed).
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().update()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    func update() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            level = nil
            return
        }
        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : nil
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            isPluggedIn = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let toEmpty = desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
            minutesRemaining = toEmpty > 0 ? toEmpty : nil
            minutesToFull = toFull > 0 ? toFull : nil
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            readBatteryHealth()
            return
        }
        level = nil
    }

    /// Cycle count and capacity compared with the battery's design capacity.
    private func readBatteryHealth() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> Int? {
            let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            return (value as? NSNumber)?.intValue
        }
        cycleCount = number("CycleCount")
        if let maximum = number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"),
           let design = number("DesignCapacity"), design > 0 {
            healthPercent = min(100, Int((Double(maximum) / Double(design) * 100).rounded()))
        }
    }

    static func symbol(for level: Int) -> String {
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}

// MARK: - macOS Dock visibility

/// Hides the built-in Dock (auto-hide with a very long reveal delay) and restores the user's original values.
enum SystemDock {
    private static let savedKey = "savedSystemDockState"

    static var isHiddenByGlassDock: Bool {
        UserDefaults.standard.dictionary(forKey: savedKey) != nil
    }

    static func hide() {
        if !isHiddenByGlassDock {
            let saved: [String: String] = [
                "autohide": run("/usr/bin/defaults", ["read", "com.apple.dock", "autohide"]) ?? "",
                "autohide-delay": run("/usr/bin/defaults", ["read", "com.apple.dock", "autohide-delay"]) ?? "",
            ]
            UserDefaults.standard.set(saved, forKey: savedKey)
        }
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", "true"])
        run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", "1000"])
        run("/usr/bin/killall", ["Dock"])
    }

    static func restore() {
        guard let saved = UserDefaults.standard.dictionary(forKey: savedKey) as? [String: String] else { return }
        if let value = saved["autohide"], !value.isEmpty {
            run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", value == "1" ? "true" : "false"])
        } else {
            run("/usr/bin/defaults", ["delete", "com.apple.dock", "autohide"])
        }
        if let value = saved["autohide-delay"], !value.isEmpty {
            run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide-delay", "-float", value])
        } else {
            run("/usr/bin/defaults", ["delete", "com.apple.dock", "autohide-delay"])
        }
        UserDefaults.standard.removeObject(forKey: savedKey)
        run("/usr/bin/killall", ["Dock"])
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
