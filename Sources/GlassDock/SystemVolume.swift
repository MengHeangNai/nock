import AudioToolbox
import CoreAudio
import Foundation

struct VolumeHUDTracker {
    private var baseline: HUDReading?

    mutating func rebase(to reading: HUDReading?) {
        baseline = reading
    }

    mutating func observe(_ reading: HUDReading) -> Bool {
        let changed = baseline != nil && baseline != reading
        baseline = reading
        return changed
    }
}

/// Follows the default output device and reports volume changes made anywhere. Reads and writes happen in the static functions, so they can run off the main thread.
final class SystemVolumeMonitor {
    var onChange: ((HUDReading) -> Void)?

    private(set) var device = AudioObjectID(kAudioObjectUnknown)
    private(set) var canSetVolume = false
    private(set) var canSetMute = false

    private var tracker = VolumeHUDTracker()
    private var isRunning = false

    private lazy var deviceChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }
    private lazy var volumeChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.readChange() }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceChanged)
        attach()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceChanged)
        detach()
    }

    func acknowledge(_ reading: HUDReading) {
        tracker.rebase(to: reading)
    }

    private func attach() {
        detach()
        var output = AudioObjectID(kAudioObjectUnknown)
        if Self.read(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal,
                     from: AudioObjectID(kAudioObjectSystemObject), into: &output) {
            device = output
        }
        guard device != kAudioObjectUnknown else {
            tracker.rebase(to: nil)
            return
        }
        for selector in Self.watchedSelectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(device, &address, .main, volumeChanged)
        }
        canSetVolume = Self.isSettable(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, on: device)
        canSetMute = Self.isSettable(kAudioDevicePropertyMute, on: device)
        tracker.rebase(to: Self.reading(of: device))
    }

    private func detach() {
        guard device != kAudioObjectUnknown else { return }
        for selector in Self.watchedSelectors {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, volumeChanged)
        }
        device = AudioObjectID(kAudioObjectUnknown)
        canSetVolume = false
        canSetMute = false
    }

    private func readChange() {
        guard let reading = Self.reading(of: device), tracker.observe(reading) else { return }
        onChange?(reading)
    }

    static func reading(of device: AudioObjectID) -> HUDReading? {
        var scalar: Float32 = 0
        var muted: UInt32 = 0
        guard read(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, from: device, into: &scalar) else { return nil }
        _ = read(kAudioDevicePropertyMute, from: device, into: &muted)
        return HUDReading(kind: .volume, value: scalar, isMuted: muted != 0)
    }

    @discardableResult
    static func setVolume(_ scalar: Float, on device: AudioObjectID) -> Bool {
        var value = min(max(scalar, 0), 1)
        let didSet = write(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, value: &value, to: device)
        if didSet, isSettable(kAudioDevicePropertyMute, on: device) { setMuted(false, on: device) }
        return didSet
    }

    @discardableResult
    static func setMuted(_ muted: Bool, on device: AudioObjectID) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        return write(kAudioDevicePropertyMute, value: &value, to: device)
    }

    private static let watchedSelectors = [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute]

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func read<T>(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
                                from object: AudioObjectID, into value: inout T) -> Bool {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0) == noErr
        }
    }

    private static func write<T>(_ selector: AudioObjectPropertySelector, value: inout T, to object: AudioObjectID) -> Bool {
        var address = address(selector)
        return withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), $0) == noErr
        }
    }

    private static func isSettable(_ selector: AudioObjectPropertySelector, on object: AudioObjectID) -> Bool {
        var address = address(selector)
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }
}
