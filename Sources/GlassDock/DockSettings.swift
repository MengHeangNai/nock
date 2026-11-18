import Foundation
import Combine

final class DockSettings: ObservableObject {
    static let shared = DockSettings()

    private let store = UserDefaults.standard

    @Published var iconSize: Double { didSet { store.set(iconSize, forKey: Keys.iconSize) } }
    @Published var magnification: Bool { didSet { store.set(magnification, forKey: Keys.magnification) } }
    @Published var maxScale: Double { didSet { store.set(maxScale, forKey: Keys.maxScale) } }
    @Published var autoHide: Bool { didSet { store.set(autoHide, forKey: Keys.autoHide) } }
    @Published var dockDisplays: DockDisplayMode { didSet { store.set(dockDisplays.rawValue, forKey: Keys.dockDisplays) } }
    @Published var showRunningApps: Bool { didSet { store.set(showRunningApps, forKey: Keys.showRunningApps) } }
    @Published var showNowPlaying: Bool { didSet { store.set(showNowPlaying, forKey: Keys.showNowPlaying) } }
    @Published var showBattery: Bool { didSet { store.set(showBattery, forKey: Keys.showBattery) } }
    @Published var showClock: Bool { didSet { store.set(showClock, forKey: Keys.showClock) } }
    @Published var hideSystemDock: Bool { didSet { store.set(hideSystemDock, forKey: Keys.hideSystemDock) } }
    @Published var pinnedPaths: [String] { didSet { store.set(pinnedPaths, forKey: Keys.pinnedPaths) } }
    @Published var showLyrics: Bool { didSet { store.set(showLyrics, forKey: Keys.showLyrics) } }
    @Published var replaceSystemHUD: Bool { didSet { store.set(replaceSystemHUD, forKey: Keys.replaceSystemHUD) } }
    @Published var showSystemNotifications: Bool { didSet { store.set(showSystemNotifications, forKey: Keys.showSystemNotifications) } }
    @Published var notifyBluetooth: Bool { didSet { store.set(notifyBluetooth, forKey: Keys.notifyBluetooth) } }
    @Published var notifyWiFi: Bool { didSet { store.set(notifyWiFi, forKey: Keys.notifyWiFi) } }
    @Published var notifyBattery: Bool { didSet { store.set(notifyBattery, forKey: Keys.notifyBattery) } }
    @Published var claudeLimitsEnabled: Bool { didSet { store.set(claudeLimitsEnabled, forKey: Keys.claudeLimitsEnabled) } }
    @Published var hiddenIslandTabs: [String] { didSet { store.set(hiddenIslandTabs, forKey: Keys.hiddenIslandTabs) } }
    @Published var animateOpening: Bool { didSet { store.set(animateOpening, forKey: Keys.animateOpening) } }
    @Published var showIndicators: Bool { didSet { store.set(showIndicators, forKey: Keys.showIndicators) } }
    @Published var enableDock: Bool { didSet { store.set(enableDock, forKey: Keys.enableDock) } }
    @Published var enableIsland: Bool { didSet { store.set(enableIsland, forKey: Keys.enableIsland) } }
    @Published var islandWithoutNotch: IslandWithoutNotchMode { didSet { store.set(islandWithoutNotch.rawValue, forKey: Keys.islandWithoutNotch) } }
    @Published var hideIslandInFullScreen: Bool { didSet { store.set(hideIslandInFullScreen, forKey: Keys.hideIslandInFullScreen) } }
    @Published var islandFinish: IslandFinish { didSet { store.set(islandFinish.rawValue, forKey: Keys.islandFinish) } }
    @Published var islandShoulderCurve: Double {
        didSet {
            let clamped = Self.islandCurve(islandShoulderCurve)
            if clamped != islandShoulderCurve { islandShoulderCurve = clamped }
            store.set(islandShoulderCurve, forKey: Keys.islandShoulderCurve)
        }
    }
    @Published var islandCornerCurve: Double {
        didSet {
            let clamped = Self.islandCurve(islandCornerCurve)
            if clamped != islandCornerCurve { islandCornerCurve = clamped }
            store.set(islandCornerCurve, forKey: Keys.islandCornerCurve)
        }
    }
    @Published var showNotchPet: Bool { didSet { store.set(showNotchPet, forKey: Keys.showNotchPet) } }
    @Published var showAgentActivity: Bool { didSet { store.set(showAgentActivity, forKey: Keys.showAgentActivity) } }
    @Published var showVisualizer: Bool { didSet { store.set(showVisualizer, forKey: Keys.showVisualizer) } }
    @Published var visualizerStyle: VisualizerStyle { didSet { store.set(visualizerStyle.rawValue, forKey: Keys.visualizerStyle) } }
    @Published var lyricsMode: LyricsViewMode { didSet { store.set(lyricsMode.rawValue, forKey: Keys.lyricsMode) } }
    @Published var pipKeepLive: Bool { didSet { store.set(pipKeepLive, forKey: Keys.pipKeepLive) } }
    @Published var keyboardSoundsEnabled: Bool { didSet { store.set(keyboardSoundsEnabled, forKey: Keys.keyboardSoundsEnabled) } }
    @Published var keyboardSoundID: String { didSet { store.set(keyboardSoundID, forKey: Keys.keyboardSoundID) } }
    @Published var keyboardSoundVolume: Double { didSet { store.set(keyboardSoundVolume, forKey: Keys.keyboardSoundVolume) } }
    @Published var keyboardSoundPitchVariation: Bool { didSet { store.set(keyboardSoundPitchVariation, forKey: Keys.keyboardSoundPitchVariation) } }
    @Published var keyboardSoundMutesDuringMusic: Bool { didSet { store.set(keyboardSoundMutesDuringMusic, forKey: Keys.keyboardSoundMutesDuringMusic) } }
    @Published var mouseSoundID: String { didSet { store.set(mouseSoundID, forKey: Keys.mouseSoundID) } }
    @Published var mouseSoundVolume: Double { didSet { store.set(mouseSoundVolume, forKey: Keys.mouseSoundVolume) } }
    @Published var mouseScrollSounds: Bool { didSet { store.set(mouseScrollSounds, forKey: Keys.mouseScrollSounds) } }

    let firstLaunchDate: Date

    private enum Keys {
        static let showSystemNotifications = "showSystemNotifications"
        static let notifyBluetooth = "notifyBluetooth"
        static let notifyWiFi = "notifyWiFi"
        static let notifyBattery = "notifyBattery"
        static let claudeLimitsEnabled = "claudeLimitsEnabled"
        static let hiddenIslandTabs = "hiddenIslandTabs"
        static let showLyrics = "showLyrics"
        static let replaceSystemHUD = "replaceSystemHUD"
        static let animateOpening = "animateOpening"
        static let showIndicators = "showIndicators"
        static let enableDock = "enableDock"
        static let enableIsland = "enableIsland"
        static let islandWithoutNotch = "islandWithoutNotch"
        static let hideIslandInFullScreen = "hideIslandInFullScreen"
        static let islandFinish = "islandFinish"
        static let islandShoulderCurve = "islandShoulderCurve"
        static let islandCornerCurve = "islandCornerCurve"
        static let showNotchPet = "showNotchPet"
        static let showAgentActivity = "showAgentActivity"
        static let showVisualizer = "showVisualizer"
        static let visualizerStyle = "visualizerStyle"
        static let lyricsMode = "lyricsMode"
        static let pipKeepLive = "pipKeepLive"
        static let keyboardSoundsEnabled = "keyboardSoundsEnabled"
        static let keyboardSoundID = "keyboardSoundProfile"
        static let keyboardSoundVolume = "keyboardSoundVolume"
        static let keyboardSoundPitchVariation = "keyboardSoundPitchVariation"
        static let keyboardSoundMouseClicks = "keyboardSoundMouseClicks"
        static let keyboardSoundMutesDuringMusic = "keyboardSoundMutesDuringMusic"
        static let mouseSoundID = "mouseSound"
        static let mouseSoundVolume = "mouseSoundVolume"
        static let mouseScrollSounds = "mouseScrollSounds"
        static let firstLaunchDate = "firstLaunchDate"
        static let iconSize = "iconSize"
        static let magnification = "magnification"
        static let maxScale = "maxScale"
        static let autoHide = "autoHide"
        static let dockDisplays = "dockDisplays"
        static let showRunningApps = "showRunningApps"
        static let showNowPlaying = "showNowPlaying"
        static let showBattery = "showBattery"
        static let showClock = "showClock"
        static let hideSystemDock = "hideSystemDock"
        static let pinnedPaths = "pinnedPaths"
    }

    private init() {
        store.register(defaults: [
            Keys.iconSize: 56.0,
            Keys.magnification: true,
            Keys.maxScale: 1.6,
            Keys.autoHide: false,
            Keys.showRunningApps: true,
            Keys.showNowPlaying: true,
            Keys.showBattery: true,
            Keys.showClock: true,
            Keys.hideSystemDock: false,
            Keys.enableDock: true,
            Keys.enableIsland: true,
            Keys.hideIslandInFullScreen: false,
            Keys.showNotchPet: true,
            Keys.showAgentActivity: true,
            Keys.showVisualizer: true,
            Keys.animateOpening: true,
            Keys.showIndicators: true,
            Keys.showLyrics: true,
            Keys.pipKeepLive: false,
            Keys.replaceSystemHUD: true,
            Keys.showSystemNotifications: true,
            Keys.notifyBluetooth: true,
            Keys.notifyWiFi: true,
            Keys.notifyBattery: true,
            Keys.keyboardSoundsEnabled: false,
            Keys.keyboardSoundVolume: 0.6,
            Keys.keyboardSoundPitchVariation: true,
            Keys.keyboardSoundMutesDuringMusic: true,
            Keys.mouseSoundVolume: 0.6,
            Keys.mouseScrollSounds: false,
        ])
        showLyrics = store.bool(forKey: Keys.showLyrics)
        pipKeepLive = store.bool(forKey: Keys.pipKeepLive)
        replaceSystemHUD = store.bool(forKey: Keys.replaceSystemHUD)
        showSystemNotifications = store.bool(forKey: Keys.showSystemNotifications)
        notifyBluetooth = store.bool(forKey: Keys.notifyBluetooth)
        notifyWiFi = store.bool(forKey: Keys.notifyWiFi)
        notifyBattery = store.bool(forKey: Keys.notifyBattery)
        hiddenIslandTabs = store.stringArray(forKey: Keys.hiddenIslandTabs) ?? []
        claudeLimitsEnabled = store.bool(forKey: Keys.claudeLimitsEnabled)
        animateOpening = store.bool(forKey: Keys.animateOpening)
        showIndicators = store.bool(forKey: Keys.showIndicators)
        enableDock = store.bool(forKey: Keys.enableDock)
        enableIsland = store.bool(forKey: Keys.enableIsland)
        islandWithoutNotch = store.string(forKey: Keys.islandWithoutNotch).flatMap(IslandWithoutNotchMode.init) ?? .alwaysShown
        hideIslandInFullScreen = store.bool(forKey: Keys.hideIslandInFullScreen)
        islandFinish = store.string(forKey: Keys.islandFinish).flatMap(IslandFinish.init) ?? .black
        islandShoulderCurve = Self.islandCurve(store.object(forKey: Keys.islandShoulderCurve) as? Double)
        islandCornerCurve = Self.islandCurve(store.object(forKey: Keys.islandCornerCurve) as? Double)
        showNotchPet = store.bool(forKey: Keys.showNotchPet)
        showAgentActivity = store.bool(forKey: Keys.showAgentActivity)
        showVisualizer = store.bool(forKey: Keys.showVisualizer)
        visualizerStyle = store.string(forKey: Keys.visualizerStyle).flatMap(VisualizerStyle.init) ?? .bars
        lyricsMode = store.string(forKey: Keys.lyricsMode).flatMap(LyricsViewMode.init) ?? .karaoke
        keyboardSoundsEnabled = store.bool(forKey: Keys.keyboardSoundsEnabled)
        keyboardSoundID = store.string(forKey: Keys.keyboardSoundID) ?? KeyboardSoundProfile.tactile.rawValue
        keyboardSoundVolume = store.double(forKey: Keys.keyboardSoundVolume)
        keyboardSoundPitchVariation = store.bool(forKey: Keys.keyboardSoundPitchVariation)
        keyboardSoundMutesDuringMusic = store.bool(forKey: Keys.keyboardSoundMutesDuringMusic)
        mouseSoundID = Self.mouseSoundID(in: store)
        mouseSoundVolume = store.double(forKey: Keys.mouseSoundVolume)
        mouseScrollSounds = store.bool(forKey: Keys.mouseScrollSounds)
        if let saved = store.object(forKey: Keys.firstLaunchDate) as? Date {
            firstLaunchDate = saved
        } else {
            firstLaunchDate = Date()
            store.set(firstLaunchDate, forKey: Keys.firstLaunchDate)
        }
        iconSize = store.double(forKey: Keys.iconSize)
        magnification = store.bool(forKey: Keys.magnification)
        maxScale = store.double(forKey: Keys.maxScale)
        autoHide = store.bool(forKey: Keys.autoHide)
        dockDisplays = store.string(forKey: Keys.dockDisplays).flatMap(DockDisplayMode.init) ?? .allDisplays
        showRunningApps = store.bool(forKey: Keys.showRunningApps)
        showNowPlaying = store.bool(forKey: Keys.showNowPlaying)
        showBattery = store.bool(forKey: Keys.showBattery)
        showClock = store.bool(forKey: Keys.showClock)
        hideSystemDock = store.bool(forKey: Keys.hideSystemDock)
        pinnedPaths = store.stringArray(forKey: Keys.pinnedPaths) ?? DockSettings.defaultPinnedPaths()
    }

    static let islandCurveRange = 0.0...2.0
    static let defaultIslandCurve = 1.0

    static func islandCurve(_ value: Double?) -> Double {
        min(max(value ?? defaultIslandCurve, islandCurveRange.lowerBound), islandCurveRange.upperBound)
    }

    static func mouseSoundID(in store: UserDefaults) -> String {
        if let saved = store.string(forKey: Keys.mouseSoundID) { return saved }
        let migrated = store.bool(forKey: Keys.keyboardSoundMouseClicks) ? MouseSoundProfile.matchKeyboardID : MouseSoundProfile.offID
        store.set(migrated, forKey: Keys.mouseSoundID)
        store.removeObject(forKey: Keys.keyboardSoundMouseClicks)
        return migrated
    }

    static func defaultPinnedPaths() -> [String] {
        var paths = ["/System/Library/CoreServices/Finder.app"]
        let systemDockApps = systemDockAppPaths()
        if systemDockApps.isEmpty {
            paths += [
                "/Applications/Safari.app",
                "/System/Applications/Mail.app",
                "/System/Applications/Messages.app",
                "/System/Applications/Music.app",
                "/System/Applications/Calendar.app",
                "/System/Applications/Notes.app",
                "/System/Applications/System Settings.app",
            ]
        } else {
            paths += systemDockApps
        }
        var seen = Set<String>()
        return paths.filter { FileManager.default.fileExists(atPath: $0) && seen.insert($0).inserted }
    }

    private static func systemDockAppPaths() -> [String] {
        guard let tiles = UserDefaults(suiteName: "com.apple.dock")?.array(forKey: "persistent-apps") as? [[String: Any]] else {
            return []
        }
        return tiles.compactMap { tile in
            guard let tileData = tile["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let urlString = fileData["_CFURLString"] as? String else { return nil }
            if let url = URL(string: urlString), url.isFileURL {
                return url.standardizedFileURL.path
            }
            if urlString.hasPrefix("/") {
                return URL(fileURLWithPath: urlString).standardizedFileURL.path
            }
            return nil
        }
    }
}
