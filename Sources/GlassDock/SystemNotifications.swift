import Foundation

enum NotificationStyle: Int, Comparable {
    case info, warning, critical

    static func < (lhs: NotificationStyle, rhs: NotificationStyle) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct IslandNotification: Equatable, Identifiable {
    static let infoSeconds: TimeInterval = 2.6
    static let warningSeconds: TimeInterval = 3.2

    let id: String
    var symbol: String
    var title: String
    var subtitle: String?
    var style: NotificationStyle
    var duration: TimeInterval

    init(id: String, symbol: String, title: String, subtitle: String? = nil, style: NotificationStyle = .info) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.style = style
        duration = style == .info ? Self.infoSeconds : Self.warningSeconds
    }

    var announcement: String { [title, subtitle].compactMap { $0 }.joined(separator: ", ") }
}

struct NotificationQueue {
    static let maxPending = 3

    private(set) var current: IslandNotification?
    private(set) var pending: [IslandNotification] = []
    private(set) var isSuppressed = false
    private(set) var revision = 0

    mutating func post(_ notification: IslandNotification) {
        if current?.id == notification.id {
            current = notification
            revision += 1
            return
        }
        pending.removeAll { $0.id == notification.id }
        pending.insert(notification, at: pending.firstIndex { $0.style < notification.style } ?? pending.endIndex)
        trim()
        promote()
    }

    mutating func finishCurrent() {
        current = nil
        promote()
    }

    mutating func setSuppressed(_ suppressed: Bool) {
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        if suppressed, let resumed = current {
            current = nil
            pending.insert(resumed, at: pending.firstIndex { $0.style <= resumed.style } ?? pending.endIndex)
            trim()
        }
        promote()
    }

    mutating func reset() {
        current = nil
        pending = []
    }

    private mutating func promote() {
        guard !isSuppressed, current == nil, !pending.isEmpty else { return }
        current = pending.removeFirst()
        revision += 1
    }

    private mutating func trim() {
        while pending.count > Self.maxPending, let lowest = pending.last?.style,
              let oldest = pending.firstIndex(where: { $0.style == lowest }) {
            pending.remove(at: oldest)
        }
    }
}

enum BatteryAlert: Equatable {
    case low(threshold: Int, level: Int)
    case fullyCharged
}

struct BatteryAlertTracker {
    static let lowThresholds = [20, 10]

    private var previous: (level: Int, isPluggedIn: Bool)?
    private var firedLow = Set<Int>()
    private var fullyChargedShown = false

    mutating func observe(level: Int?, isPluggedIn: Bool) -> BatteryAlert? {
        guard let level else {
            previous = nil
            return nil
        }
        defer { previous = (level, isPluggedIn) }
        if isPluggedIn {
            firedLow = []
            return fullyChargedAlert(level)
        }
        fullyChargedShown = false
        let crossed = Self.lowThresholds.filter { level <= $0 && !firedLow.contains($0) }
        guard let lowest = crossed.min() else { return nil }
        firedLow.formUnion(crossed)
        return previous == nil ? nil : .low(threshold: lowest, level: level)
    }

    private mutating func fullyChargedAlert(_ level: Int) -> BatteryAlert? {
        guard level >= 100, !fullyChargedShown else { return nil }
        fullyChargedShown = true
        guard let previous, previous.isPluggedIn, previous.level < 100 else { return nil }
        return .fullyCharged
    }
}

enum WiFiState: Equatable {
    case off, disconnected, connected
}

struct WiFiTracker {
    private var last: WiFiState?

    mutating func observe(_ state: WiFiState) -> IslandNotification? {
        defer { last = state }
        guard let last, last != state else { return nil }
        return .wifi(state, from: last)
    }
}

struct BluetoothConnectionTracker {
    private var connected = Set<String>()

    mutating func seed(_ addresses: [String]) { connected = Set(addresses) }

    mutating func didConnect(_ address: String) -> Bool { connected.insert(address).inserted }

    mutating func didDisconnect(_ address: String) -> Bool { connected.remove(address) != nil }
}

enum BluetoothDeviceKind: Equatable {
    case airPods, airPodsPro, airPodsMax, headphones, speaker, car, keyboard, mouse, trackpad, gamepad, generic

    private static let audioMajor: UInt32 = 4
    private static let peripheralMajor: UInt32 = 5

    init(name: String, major: UInt32, minor: UInt32) {
        let lower = name.lowercased()
        if lower.contains("airpods max") {
            self = .airPodsMax
        } else if lower.contains("airpods pro") {
            self = .airPodsPro
        } else if lower.contains("airpods") {
            self = .airPods
        } else if lower.contains("trackpad") {
            self = .trackpad
        } else if major == Self.audioMajor {
            switch minor {
            case 5, 7: self = .speaker
            case 8: self = .car
            default: self = .headphones
            }
        } else if major == Self.peripheralMajor {
            switch (minor & 0x30, minor & 0x0F) {
            case (_, 1), (_, 2): self = .gamepad
            case (0x10, _), (0x30, _): self = .keyboard
            case (0x20, _): self = .mouse
            default: self = .generic
            }
        } else {
            self = .generic
        }
    }

    var symbol: String {
        switch self {
        case .airPods: return "airpods"
        case .airPodsPro: return "airpodspro"
        case .airPodsMax: return "airpodsmax"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker.fill"
        case .car: return "car.fill"
        case .keyboard: return "keyboard"
        case .mouse: return "computermouse.fill"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .gamepad: return "gamecontroller.fill"
        case .generic: return "dot.radiowaves.left.and.right"
        }
    }
}

extension IslandNotification {
    static func bluetooth(address: String, name: String, kind: BluetoothDeviceKind, isConnected: Bool) -> IslandNotification {
        IslandNotification(id: "bluetooth.\(address)", symbol: kind.symbol, title: name,
                           subtitle: isConnected ? "Connected" : "Disconnected")
    }

    static func wifi(_ state: WiFiState, from previous: WiFiState) -> IslandNotification {
        switch state {
        case .disconnected where previous == .off: return IslandNotification(id: "wifi", symbol: "wifi", title: "Wi-Fi on")
        case .connected: return IslandNotification(id: "wifi", symbol: "wifi", title: "Wi-Fi connected")
        case .disconnected: return IslandNotification(id: "wifi", symbol: "wifi.exclamationmark", title: "Wi-Fi disconnected")
        case .off: return IslandNotification(id: "wifi", symbol: "wifi.slash", title: "Wi-Fi off")
        }
    }

    static func battery(_ alert: BatteryAlert) -> IslandNotification {
        switch alert {
        case .low(let threshold, let level) where threshold <= 10:
            return IslandNotification(id: "battery.low", symbol: "battery.0percent", title: "Low battery",
                                      subtitle: "\(level)% remaining", style: .critical)
        case .low(_, let level):
            return IslandNotification(id: "battery.low", symbol: "battery.25percent", title: "Low battery",
                                      subtitle: "\(level)% remaining", style: .warning)
        case .fullyCharged:
            return IslandNotification(id: "battery.full", symbol: "battery.100percent.bolt", title: "Fully charged",
                                      subtitle: "100%")
        }
    }
}
