import Foundation

enum HUDKind: Equatable {
    case volume, brightness, keyboardBacklight
}

enum StepDirection: Equatable {
    case up, down
}

struct HUDReading: Equatable {
    var kind: HUDKind
    var value: Float
    var isMuted = false

    var level: Float { isMuted ? 0 : min(max(value, 0), 1) }

    var percent: Int { Int((level * 100).rounded()) }

    var label: String {
        switch kind {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .keyboardBacklight: return "Keyboard Brightness"
        }
    }

    /// The volume symbol fills in with `symbolValue`; the brightness symbols have no variable form, so they switch between a small and a large version.
    var symbol: String {
        switch kind {
        case .volume: return isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill"
        case .brightness: return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBacklight: return level < 0.5 ? "light.min" : "light.max"
        }
    }

    var symbolValue: Double { Double(level) }
}

enum MediaKey: Int, Equatable {
    case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    case illuminationUp = 21, illuminationDown = 22, illuminationToggle = 23
}

struct MediaKeyModifiers: OptionSet {
    let rawValue: Int
    static let shift = MediaKeyModifiers(rawValue: 1)
    static let option = MediaKeyModifiers(rawValue: 2)
    static let command = MediaKeyModifiers(rawValue: 4)
    static let control = MediaKeyModifiers(rawValue: 8)
}

enum MediaKeyAction: Equatable {
    case step(HUDKind, StepDirection)
    case toggleMute
    case toggleBacklight
}

extension MediaKey {
    var kind: HUDKind {
        switch self {
        case .soundUp, .soundDown, .mute: return .volume
        case .brightnessUp, .brightnessDown: return .brightness
        case .illuminationUp, .illuminationDown, .illuminationToggle: return .keyboardBacklight
        }
    }

    var action: MediaKeyAction {
        switch self {
        case .soundUp: return .step(.volume, .up)
        case .soundDown: return .step(.volume, .down)
        case .mute: return .toggleMute
        case .brightnessUp: return .step(.brightness, .up)
        case .brightnessDown: return .step(.brightness, .down)
        case .illuminationUp: return .step(.keyboardBacklight, .up)
        case .illuminationDown: return .step(.keyboardBacklight, .down)
        case .illuminationToggle: return .toggleBacklight
        }
    }
}

struct MediaKeyPress: Equatable {
    static let auxControlSubtype = 8

    let key: MediaKey
    let isDown: Bool
    let isRepeat: Bool
    let modifiers: MediaKeyModifiers

    init?(subtype: Int, data1: Int, modifiers: MediaKeyModifiers) {
        guard subtype == Self.auxControlSubtype,
              let key = MediaKey(rawValue: (data1 & 0xFFFF_0000) >> 16) else { return nil }
        let state = (data1 & 0xFF00) >> 8
        guard state == 0xA || state == 0xB else { return nil }
        self.key = key
        isDown = state == 0xA
        isRepeat = data1 & 0x1 == 1
        self.modifiers = modifiers
    }

    var isFineStep: Bool { modifiers.isSuperset(of: [.shift, .option]) }

    /// Option alone opens the matching System Settings pane, and Command or Control combine the key with other system actions.
    var isLeftToSystem: Bool {
        modifiers.contains(.command) || modifiers.contains(.control) || (modifiers.contains(.option) && !modifiers.contains(.shift))
    }
}

struct HeldMediaKeys {
    private var claimed = Set<MediaKey>()

    mutating func claim(_ press: MediaKeyPress, canHandle: Bool) -> Bool {
        guard press.isDown else { return claimed.remove(press.key) != nil }
        guard !press.isRepeat else { return claimed.contains(press.key) }
        if canHandle { claimed.insert(press.key) } else { claimed.remove(press.key) }
        return canHandle
    }
}

enum HUDStep {
    static let standard = 16
    static let fine = 64

    static func next(from value: Float, direction: StepDirection, steps: Int) -> Float {
        let count = Float(steps)
        let position = min(max(value, 0), 1) * count
        let target = direction == .up ? floor(position + 0.001) + 1 : ceil(position - 0.001) - 1
        return min(max(target / count, 0), 1)
    }

    static func toggledBacklight(from current: Float, previous: Float) -> Float {
        if current > 0 { return 0 }
        return previous > 0 ? previous : 0.5
    }
}

enum HUDAccess: Equatable {
    case settingOff, islandOff, needsAccessibility, tapRefused, replacing

    var isEnabled: Bool { self != .settingOff && self != .islandOff }

    /// Decides the state from the setting, the Island and Accessibility. `startTap` runs only when the setting and the Island are on and Accessibility is granted, so no key is consumed before that.
    static func resolve(replacesSystemHUD: Bool, isIslandShown: Bool, isTrusted: Bool, startTap: () -> Bool) -> HUDAccess {
        guard replacesSystemHUD else { return .settingOff }
        guard isIslandShown else { return .islandOff }
        guard isTrusted else { return .needsAccessibility }
        return startTap() ? .replacing : .tapRefused
    }
}
