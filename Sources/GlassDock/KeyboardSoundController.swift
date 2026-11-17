import AppKit
import AVFoundation
import Carbon.HIToolbox
import Combine

enum KeyboardSoundProfile: String, CaseIterable, Identifiable {
    case clicky, tactile, thock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clicky: return "Clicky"
        case .tactile: return "Tactile"
        case .thock: return "Thock"
        }
    }

    func recipe(for sound: KeyboardSound) -> KeyboardSoundRecipe {
        let base: KeyboardSoundRecipe
        switch self {
        case .clicky:
            base = KeyboardSoundRecipe(toneHz: 2600, toneDecay: 0.010, noiseCutoffHz: 9000, noiseDecay: 0.006, noiseMix: 0.7, gain: 1)
        case .tactile:
            base = KeyboardSoundRecipe(toneHz: 1300, toneDecay: 0.016, noiseCutoffHz: 4500, noiseDecay: 0.008, noiseMix: 0.5, gain: 1)
        case .thock:
            base = KeyboardSoundRecipe(toneHz: 420, toneDecay: 0.022, noiseCutoffHz: 1600, noiseDecay: 0.012, noiseMix: 0.35, gain: 1)
        }
        switch sound {
        case .down: return base
        case .wideDown: return base.scaled(pitch: 0.7, decay: 1.5, gain: 1)
        case .up: return base.scaled(pitch: 1.35, decay: 0.6, gain: 0.45)
        case .mouseClick: return base.scaled(pitch: 1.8, decay: 0.4, gain: 0.5)
        }
    }
}

enum KeyboardSound: CaseIterable {
    case down, wideDown, up, mouseClick
}

enum MouseSoundProfile: String, CaseIterable, Identifiable {
    case soft, crisp, hollow

    static let offID = "off"
    static let matchKeyboardID = "matchKeyboard"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soft: return "Soft"
        case .crisp: return "Crisp"
        case .hollow: return "Hollow"
        }
    }

    func recipe(for sound: MouseSound) -> KeyboardSoundRecipe {
        let base: KeyboardSoundRecipe
        switch self {
        case .soft:
            base = KeyboardSoundRecipe(toneHz: 3200, toneDecay: 0.004, noiseCutoffHz: 7000, noiseDecay: 0.003, noiseMix: 0.6, gain: 0.7)
        case .crisp:
            base = KeyboardSoundRecipe(toneHz: 4800, toneDecay: 0.006, noiseCutoffHz: 12_000, noiseDecay: 0.004, noiseMix: 0.65, gain: 0.9)
        case .hollow:
            base = KeyboardSoundRecipe(toneHz: 1800, toneDecay: 0.008, noiseCutoffHz: 4000, noiseDecay: 0.005, noiseMix: 0.5, gain: 0.8)
        }
        switch sound {
        case .click: return base
        case .release, .rightRelease, .middleRelease: return base.scaled(pitch: 1.2, decay: 0.7, gain: 0.55)
        case .right, .middle: return base.scaled(pitch: 0.9, decay: 1, gain: 0.95)
        case .scroll: return base.scaled(pitch: 1.5, decay: 0.35, gain: 0.3)
        }
    }
}

enum MouseSound: String, CaseIterable {
    case click, release, right, rightRelease, middle, middleRelease, scroll

    var keyboardSound: KeyboardSound {
        switch self {
        case .click, .right, .middle: return .mouseClick
        case .release, .rightRelease, .middleRelease, .scroll: return .up
        }
    }
}

struct KeyboardSoundRecipe {
    static let seconds = 0.12
    static let peak = 0.8

    let toneHz: Double
    let toneDecay: Double
    let noiseCutoffHz: Double
    let noiseDecay: Double
    let noiseMix: Double
    let gain: Double

    func scaled(pitch: Double, decay: Double, gain: Double) -> KeyboardSoundRecipe {
        KeyboardSoundRecipe(toneHz: toneHz * pitch, toneDecay: toneDecay * decay,
                            noiseCutoffHz: noiseCutoffHz * pitch, noiseDecay: noiseDecay * decay,
                            noiseMix: noiseMix, gain: self.gain * gain)
    }

    func samples(sampleRate: Double) -> [Float] {
        let count = Int(sampleRate * Self.seconds)
        let fadeStart = count * 4 / 5
        let smoothing = 1 - exp(-2 * .pi * noiseCutoffHz / sampleRate)
        var noise = 0.0
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let time = Double(index) / sampleRate
            noise += smoothing * (Double.random(in: -1...1) - noise)
            let transient = noise * exp(-time / noiseDecay)
            let ring = sin(2 * .pi * toneHz * time) * exp(-time / toneDecay)
            let fade = index < fadeStart ? 1 : Double(count - index) / Double(count - fadeStart)
            samples[index] = Float((noiseMix * transient + (1 - noiseMix) * ring) * fade)
        }
        guard let loudest = samples.map(abs).max(), loudest > 0 else { return samples }
        let scale = Float(Self.peak * gain) / loudest
        return samples.map { $0 * scale }
    }
}


final class KeyboardSoundController: ObservableObject {
    private static let voiceCount = 8
    private static let ioBufferFrames: UInt32 = 128
    private static let accessCheckSeconds: TimeInterval = 2
    private static let pitchRange: ClosedRange<Float> = 0.94...1.06
    private static let wideKeyCodes: Set<Int> = [kVK_Space, kVK_Return, kVK_ANSI_KeypadEnter, kVK_Delete]
    private static let previewKeyCodes = [kVK_ANSI_G, kVK_ANSI_L, kVK_ANSI_A, kVK_ANSI_S, kVK_Space, kVK_Return]
    private static let mousePreviewSounds: [MouseSound] = [.click, .release, .right, .rightRelease, .scroll, .scroll, .scroll]
    private static let previewSpacing: TimeInterval = 0.09
    private static let previewTail: TimeInterval = 1
    private static let middleButtonNumber = 2
    static let scrollTickSeconds: TimeInterval = 0.05

    @Published private(set) var packs: [KeyboardSoundpack] = []
    @Published private(set) var mousePacks: [MouseSoundpack] = []

    private let settings: DockSettings
    private let nowPlaying: NowPlayingMonitor
    private let engine = AVAudioEngine()
    private let voices = (0..<voiceCount).map { _ in AVAudioPlayerNode() }
    private let pitches = (0..<voiceCount).map { _ in AVAudioUnitVarispeed() }
    private let builtIns: [KeyboardSoundProfile: [KeyboardSound: AVAudioPCMBuffer]]
    private let mouseBuiltIns: [MouseSoundProfile: [MouseSound: AVAudioPCMBuffer]]
    private var nextVoice = 0
    private var lastScrollTick: TimeInterval = 0
    private var monitors: [Any] = []
    private var accessTimer: Timer?
    private var previewStop: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    private var isActive: Bool {
        settings.keyboardSoundsEnabled || settings.mouseSoundID != MouseSoundProfile.offID
    }

    init(settings: DockSettings, nowPlaying: NowPlayingMonitor) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        let format = KeyboardSoundpack.format
        builtIns = Dictionary(uniqueKeysWithValues: KeyboardSoundProfile.allCases.map { profile in
            (profile, KeyboardSound.allCases.reduce(into: [:]) { buffers, sound in
                buffers[sound] = Self.pcmBuffer(profile.recipe(for: sound).samples(sampleRate: format.sampleRate), format: format)
            })
        })
        mouseBuiltIns = Dictionary(uniqueKeysWithValues: MouseSoundProfile.allCases.map { profile in
            (profile, MouseSound.allCases.reduce(into: [:]) { buffers, sound in
                buffers[sound] = Self.pcmBuffer(profile.recipe(for: sound).samples(sampleRate: format.sampleRate), format: format)
            })
        })
        voices.forEach(engine.attach)
        pitches.forEach(engine.attach)
        rescanPacks()

        Publishers.CombineLatest(settings.$keyboardSoundsEnabled, settings.$mouseSoundID)
            .map { keyboardOn, mouseSoundID in keyboardOn || mouseSoundID != MouseSoundProfile.offID }
            .removeDuplicates()
            .sink { [weak self] active in active ? self?.start() : self?.stop() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: engine)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, isActive else { return }
                stop()
                start()
            }
            .store(in: &cancellables)
    }

    static func isScrollTick(_ event: NSEvent, lastTick: TimeInterval) -> Bool {
        event.momentumPhase.isEmpty
            && (event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0)
            && event.timestamp - lastTick >= scrollTickSeconds
    }

    func rescanPacks() {
        DispatchQueue.global(qos: .userInitiated).async {
            let scanned = KeyboardSoundpack.scan()
            let scannedMouse = MouseSoundpack.scan()
            DispatchQueue.main.async { [weak self] in
                self?.packs = scanned
                self?.mousePacks = scannedMouse
            }
        }
    }

    func preview(_ soundID: String) {
        playPreview(Self.previewKeyCodes.map { keyCode in
            buffer(for: Self.wideKeyCodes.contains(keyCode) ? .wideDown : .down, keyCode: keyCode, soundID: soundID)
        }, volume: settings.keyboardSoundVolume)
    }

    func previewMouse(_ soundID: String) {
        playPreview(Self.mousePreviewSounds.map { mouseBuffer(for: $0, soundID: soundID) }, volume: settings.mouseSoundVolume)
    }

    private func playPreview(_ buffers: [AVAudioPCMBuffer?], volume: Double) {
        guard startEngine() else { return }
        for (index, buffer) in buffers.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewSpacing * Double(index)) { [weak self] in
                self?.schedule(buffer, volume: volume)
            }
        }
        previewStop?.cancel()
        let stopIfInactive = DispatchWorkItem { [weak self] in
            guard let self, !isActive else { return }
            stopEngine()
        }
        previewStop = stopIfInactive
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewSpacing * Double(buffers.count) + Self.previewTail,
                                      execute: stopIfInactive)
    }

    private func start() {
        guard startEngine() else { return }
        installMonitors()
    }

    private func stop() {
        removeMonitors()
        stopEngine()
    }

    private func startEngine() -> Bool {
        if engine.isRunning { return true }
        if let unit = engine.outputNode.audioUnit {
            var frames = Self.ioBufferFrames
            AudioUnitSetProperty(unit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0,
                                 &frames, UInt32(MemoryLayout<UInt32>.size))
        }
        for (voice, pitch) in zip(voices, pitches) {
            engine.connect(voice, to: pitch, format: KeyboardSoundpack.format)
            engine.connect(pitch, to: engine.mainMixerNode, format: KeyboardSoundpack.format)
        }
        do {
            try engine.start()
        } catch {
            NSLog("GlassDock: keyboard sounds could not start audio: \(error.localizedDescription)")
            return false
        }
        voices.forEach { $0.play() }
        return true
    }

    private func stopEngine() {
        guard engine.isRunning else { return }
        voices.forEach { $0.stop() }
        engine.stop()
    }

    private static func pcmBuffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)
        return buffer
    }

    private func installMonitors() {
        let events: NSEvent.EventTypeMask = [.keyDown, .keyUp, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
                                             .otherMouseDown, .otherMouseUp, .scrollWheel]
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in self?.handle(event) },
            NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.handle(event)
                return event
            },
        ].compactMap { $0 }
        guard !AppWindows.isTrusted else { return }
        let timer = Timer(timeInterval: Self.accessCheckSeconds, repeats: true) { [weak self] _ in
            guard AppWindows.isTrusted else { return }
            self?.removeMonitors()
            self?.installMonitors()
        }
        RunLoop.main.add(timer, forMode: .common)
        accessTimer = timer
    }

    private func removeMonitors() {
        accessTimer?.invalidate()
        accessTimer = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    private func handle(_ event: NSEvent) {
        guard !(settings.keyboardSoundMutesDuringMusic && nowPlaying.isPlaying) else { return }
        let keyboardOn = settings.keyboardSoundsEnabled
        let mouseOn = settings.mouseSoundID != MouseSoundProfile.offID
        switch event.type {
        case .keyDown where keyboardOn && !event.isARepeat:
            let keyCode = Int(event.keyCode)
            playKey(Self.wideKeyCodes.contains(keyCode) ? .wideDown : .down, keyCode: keyCode)
        case .keyUp where keyboardOn:
            playKey(.up, keyCode: Int(event.keyCode))
        case .leftMouseDown where mouseOn:
            playMouse(.click)
        case .rightMouseDown where mouseOn:
            playMouse(.right)
        case .otherMouseDown where mouseOn && event.buttonNumber == Self.middleButtonNumber:
            playMouse(.middle)
        case .leftMouseUp where mouseOn:
            playMouse(.release)
        case .rightMouseUp where mouseOn:
            playMouse(.rightRelease)
        case .otherMouseUp where mouseOn && event.buttonNumber == Self.middleButtonNumber:
            playMouse(.middleRelease)
        case .scrollWheel where mouseOn && settings.mouseScrollSounds && Self.isScrollTick(event, lastTick: lastScrollTick):
            lastScrollTick = event.timestamp
            playMouse(.scroll)
        default:
            break
        }
    }

    private func playKey(_ sound: KeyboardSound, keyCode: Int) {
        schedule(buffer(for: sound, keyCode: keyCode, soundID: settings.keyboardSoundID), volume: settings.keyboardSoundVolume)
    }

    private func playMouse(_ sound: MouseSound) {
        schedule(mouseBuffer(for: sound, soundID: settings.mouseSoundID), volume: settings.mouseSoundVolume)
    }

    private func buffer(for sound: KeyboardSound, keyCode: Int?, soundID: String) -> AVAudioPCMBuffer? {
        if let pack = packs.first(where: { $0.id == soundID && $0.isAvailable }) {
            let keySound = pack.sound(forKeyCode: keyCode)
            return sound == .up ? keySound?.up : keySound?.down
        }
        return builtIns[KeyboardSoundProfile(rawValue: soundID) ?? .tactile]?[sound]
    }

    private func mouseBuffer(for sound: MouseSound, soundID: String) -> AVAudioPCMBuffer? {
        if soundID == MouseSoundProfile.matchKeyboardID {
            return buffer(for: sound.keyboardSound, keyCode: nil, soundID: settings.keyboardSoundID)
        }
        if let pack = mousePacks.first(where: { $0.id == soundID && $0.isAvailable }) {
            return pack.sounds[sound]
        }
        return mouseBuiltIns[MouseSoundProfile(rawValue: soundID) ?? .soft]?[sound]
    }

    private func schedule(_ buffer: AVAudioPCMBuffer?, volume: Double) {
        guard engine.isRunning, let buffer else { return }
        let index = nextVoice
        nextVoice = (nextVoice + 1) % voices.count
        voices[index].volume = Float(volume)
        pitches[index].rate = settings.keyboardSoundPitchVariation ? Float.random(in: Self.pitchRange) : 1
        voices[index].scheduleBuffer(buffer, at: nil, options: .interrupts)
    }
}
