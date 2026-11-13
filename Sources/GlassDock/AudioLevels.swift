import Accelerate
import AppKit
import Combine
import CoreAudio

/// Four band levels (0...1, low to high pitch) of the sound the Mac is playing, read through a Core Audio system tap.
/// Samples are analyzed in memory and never stored or sent anywhere.
final class AudioLevelMonitor: ObservableObject {
    static let bandCount = 4

    @Published private(set) var levels = [CGFloat](repeating: 0, count: AudioLevelMonitor.bandCount)
    /// True while the tap is running. Until then the bars keep their looping animation.
    @Published private(set) var isCapturing = false

    private let control = DispatchQueue(label: "GlassDock.AudioLevels.control")
    private let audioQueue = DispatchQueue(label: "GlassDock.AudioLevels.audio", qos: .userInteractive)
    private var capture: AnyObject?

    init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: nil) { [weak self] _ in
            self?.control.sync { self?.capture = nil }
        }
    }

    func start() {
        guard #available(macOS 14.2, *) else { return }
        control.async { [self] in
            guard capture == nil else { return }
            capture = SystemAudioTap(queue: audioQueue) { [weak self] levels in
                DispatchQueue.main.async { self?.levels = levels }
            }
            let isRunning = capture != nil
            DispatchQueue.main.async { self.isCapturing = isRunning }
        }
    }

    func stop() {
        control.async { [self] in
            capture = nil
            DispatchQueue.main.async {
                self.isCapturing = false
                self.levels = [CGFloat](repeating: 0, count: Self.bandCount)
            }
        }
    }
}

/// A private tap on everything the Mac plays, with the aggregate device that delivers its samples. Releases both when freed.
@available(macOS 14.2, *)
private final class SystemAudioTap {
    private static let publishRate = 30.0

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var timer: DispatchSourceTimer?
    private var analyzer: BandAnalyzer?

    /// Returns nil when the tap cannot be created, for example when the system audio permission is refused.
    init?(queue: DispatchQueue, publish: @escaping ([CGFloat]) -> Void) {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return nil }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "GlassDock Audio Levels",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              let sampleRate = Self.sampleRate(of: tapID) else {
            release()
            return nil
        }
        let analyzer = BandAnalyzer(sampleRate: sampleRate)
        self.analyzer = analyzer

        let created = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, _, _, _ in
            analyzer.collect(input)
        }
        guard created == noErr, AudioDeviceStart(aggregateID, procID) == noErr else {
            release()
            return nil
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1 / Self.publishRate)
        timer.setEventHandler {
            if let levels = analyzer.nextLevels() { publish(levels) }
        }
        timer.resume()
        self.timer = timer
    }

    deinit { release() }

    private func release() {
        timer?.cancel()
        timer = nil
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            self.procID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func sampleRate(of tap: AudioObjectID) -> Float? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr,
              format.mSampleRate > 0 else { return nil }
        return Float(format.mSampleRate)
    }
}

/// Turns incoming audio into smoothed band levels. Call both methods from the same serial queue.
private final class BandAnalyzer {
    private static let log2n = vDSP_Length(10)
    private static let size = 1 << Int(log2n)
    private static let bandEdgesHz: [Float] = [40, 250, 1000, 4000, 12000]
    // Highs carry less energy than bass, so they are lifted to move as much as the bass bar.
    private static let bandBoostDB: [Float] = [-6, 0, 8, 20]
    private static let floorDB: Float = -80
    private static let rangeDB: Float = 55
    private static let attack: Float = 0.7
    private static let release: Float = 0.2

    private let fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                                     count: BandAnalyzer.size, isHalfWindow: false)
    private let bins: [Range<Int>]
    private var recent = [Float](repeating: 0, count: BandAnalyzer.size)
    private var writeIndex = 0
    private var real = [Float](repeating: 0, count: BandAnalyzer.size / 2)
    private var imag = [Float](repeating: 0, count: BandAnalyzer.size / 2)
    private var power = [Float](repeating: 0, count: BandAnalyzer.size / 2)
    private var smoothed = [Float](repeating: 0, count: AudioLevelMonitor.bandCount)

    init(sampleRate: Float) {
        let top = Self.size / 2
        let edges = Self.bandEdgesHz.map { min(top, max(1, Int($0 * Float(Self.size) / sampleRate))) }
        bins = (0..<AudioLevelMonitor.bandCount).map { edges[$0]..<max(edges[$0] + 1, edges[$0 + 1]) }
    }

    deinit { vDSP_destroy_fftsetup(fft) }

    func collect(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, first.mNumberChannels > 0 else { return }
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * Int(first.mNumberChannels))
        let channels = buffers.reduce(0) { $0 + Int($1.mNumberChannels) }

        for frame in 0..<frames {
            var sum: Float = 0
            for buffer in buffers {
                guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let count = Int(buffer.mNumberChannels)
                for channel in 0..<count { sum += samples[frame * count + channel] }
            }
            recent[writeIndex] = sum / Float(channels)
            writeIndex = (writeIndex + 1) % Self.size
        }
    }

    func nextLevels() -> [CGFloat]? {
        let target = bandLevels()
        var changed = false
        for band in smoothed.indices {
            let previous = smoothed[band]
            let rate = target[band] > previous ? Self.attack : Self.release
            let value = previous + (target[band] - previous) * rate
            smoothed[band] = value < 0.01 ? 0 : value
            changed = changed || smoothed[band] != previous
        }
        return changed ? smoothed.map { CGFloat($0) } : nil
    }

    private func bandLevels() -> [Float] {
        let ordered = Array(recent[writeIndex...] + recent[..<writeIndex])
        let windowed = vDSP.multiply(ordered, window)
        let half = vDSP_Length(Self.size / 2)
        windowed.withUnsafeBufferPointer { samples in
            samples.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Int(half)) { complex in
                real.withUnsafeMutableBufferPointer { realp in
                    imag.withUnsafeMutableBufferPointer { imagp in
                        var split = DSPSplitComplex(realp: realp.baseAddress!, imagp: imagp.baseAddress!)
                        vDSP_ctoz(complex, 2, &split, 1, half)
                        vDSP_fft_zrip(fft, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvmags(&split, 1, &power, 1, half)
                    }
                }
            }
        }

        // A full-scale sine gives an amplitude of Size / 2 in the transform.
        let scale = 4 / Float(Self.size * Self.size)
        return bins.indices.map { band in
            let mean = vDSP.mean(power[bins[band]]) * scale
            let decibels = 10 * log10(max(mean, 1e-12)) + Self.bandBoostDB[band]
            return min(1, max(0, (decibels - Self.floorDB) / Self.rangeDB))
        }
    }
}
