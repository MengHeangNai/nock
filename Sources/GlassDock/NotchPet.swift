import Foundation

enum PetMood: Equatable {
    case idle, sleeping, dancing, tired, happy

    static let sleepAfterIdleSeconds: TimeInterval = 120
    static let tiredBatteryLevel = 20

    static func decide(idleSeconds: TimeInterval, isMusicPlaying: Bool, batteryLevel: Int?,
                       isOnBattery: Bool, isCelebrating: Bool) -> PetMood {
        if isCelebrating { return .happy }
        if isMusicPlaying { return .dancing }
        if idleSeconds >= sleepAfterIdleSeconds { return .sleeping }
        if isOnBattery, let batteryLevel, batteryLevel <= tiredBatteryLevel { return .tired }
        return .idle
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: return "Notch pet"
        case .sleeping: return "Notch pet, sleeping"
        case .dancing: return "Notch pet, dancing"
        case .tired: return "Notch pet, tired"
        case .happy: return "Notch pet, happy"
        }
    }
}

enum PetStage: Equatable {
    case baby, young, grown

    static let youngAfterDays = 7
    static let grownAfterDays = 30

    init(firstLaunch: Date, now: Date, calendar: Calendar = .current) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstLaunch),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        if days >= Self.grownAfterDays {
            self = .grown
        } else if days >= Self.youngAfterDays {
            self = .young
        } else {
            self = .baby
        }
    }
}
