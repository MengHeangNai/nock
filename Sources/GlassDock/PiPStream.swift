import AppKit
import CoreMedia
import ScreenCaptureKit

final class PiPStream: NSObject, SCStreamOutput, SCStreamDelegate {
    private static let framesPerSecond: Int32 = 30
    private static let queueDepth = 3
    private static let aspectSettleDelay: TimeInterval = 0.5

    private let filter: SCContentFilter
    private let configuration = SCStreamConfiguration()
    private let queue = DispatchQueue(label: "GlassDock.PiPStream", qos: .userInteractive)
    private let onFrame: (IOSurface) -> Void
    private let onAspect: (CGFloat) -> Void
    private let onBlank: (Bool) -> Void
    private let onBlackRegion: (Bool) -> Void
    private let onStop: () -> Void
    private var stream: SCStream?
    private var isStopping = false
    private var isBlank = false
    private var looksProtected = false
    private var blackProbeStreak = 0
    private var nextProbeAt = Date.distantPast
    private var aspect: CGFloat
    private var windowSize: CGSize
    private var windowOrigin: CGPoint
    private let displayOrigin: CGPoint?
    private var crop: PiPCrop?
    private let scale: CGFloat
    private var settledAt = Date.distantPast

    init(window: SCWindow, display: SCDisplay?, windowFrame: CGRect, scale: CGFloat, crop: PiPCrop?,
         onFrame: @escaping (IOSurface) -> Void, onAspect: @escaping (CGFloat) -> Void, onBlank: @escaping (Bool) -> Void,
         onBlackRegion: @escaping (Bool) -> Void, onStop: @escaping () -> Void) {
        filter = display.map { SCContentFilter(display: $0, including: [window]) }
            ?? SCContentFilter(desktopIndependentWindow: window)
        displayOrigin = display?.frame.origin
        self.onFrame = onFrame
        self.onAspect = onAspect
        self.onBlank = onBlank
        self.onBlackRegion = onBlackRegion
        self.onStop = onStop
        windowSize = windowFrame.size
        windowOrigin = windowFrame.origin
        self.scale = scale
        self.crop = crop
        aspect = PiPGeometry.aspect(of: windowFrame.size) ?? 1
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
        configuration.queueDepth = Self.queueDepth
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureResolution = .best
        if #available(macOS 15, *) { configuration.captureDynamicRange = .SDR }
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        if #available(macOS 14.2, *) { configuration.includeChildWindows = true }
        super.init()
        applyCapture()
    }

    func start() async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        try await stream.startCapture()
    }

    func update(windowFrame: CGRect, crop: PiPCrop?) {
        queue.async { [self] in
            windowSize = windowFrame.size
            windowOrigin = windowFrame.origin
            self.crop = crop
            aspect = PiPGeometry.aspect(of: windowSize) ?? aspect
            applyCapture()
            Task { [configuration, stream] in try? await stream?.updateConfiguration(configuration) }
        }
    }

    func stop() {
        isStopping = true
        let stream = stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !isStopping else { return }
            onStop()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = (CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                                    as? [[SCStreamFrameInfo: Any]])?.first,
              let rawStatus = attachments[.status] as? Int, let status = SCFrameStatus(rawValue: rawStatus)
        else { return }
        if status == .stopped {
            DispatchQueue.main.async { [weak self] in
                guard let self, !isStopping else { return }
                onStop()
            }
            return
        }
        if status == .blank || status == .suspended {
            reportBlank(true)
            return
        }
        guard let buffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue(),
              PiPSourceState.isValidFrame(status: status, surfaceSize: CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface)),
                                          expectedWidth: configuration.width) else { return }
        reportBlank(false)
        probeForBlackRegion(surface)
        DispatchQueue.main.async { [weak self] in
            guard let self, !isStopping else { return }
            onFrame(surface)
        }
        followContentAspect(attachments, stream: stream)
    }

    private func applyCapture() {
        if let displayOrigin {
            let shown = CGRect(x: windowOrigin.x - displayOrigin.x, y: windowOrigin.y - displayOrigin.y,
                               width: windowSize.width, height: windowSize.height)
            configuration.sourceRect = crop?.frame(in: shown) ?? shown
        } else {
            configuration.sourceRect = crop?.sourceRect(in: windowSize) ?? .zero
        }
        let pixels = crop?.captureSize(in: windowSize, scale: scale)
            ?? PiPGeometry.captureSize(windowSize: windowSize, scale: scale)
        configuration.width = Int(pixels.width)
        configuration.height = Int(pixels.height)
    }

    private func reportBlank(_ blank: Bool) {
        guard blank != isBlank else { return }
        isBlank = blank
        DispatchQueue.main.async { [weak self] in
            guard let self, !isStopping else { return }
            onBlank(blank)
        }
    }

    private func probeForBlackRegion(_ surface: IOSurface) {
        let now = Date()
        guard now >= nextProbeAt, let samples = PiPFrameProbe.samples(of: surface) else { return }
        nextProbeAt = now.addingTimeInterval(PiPFrameProbe.probeInterval)
        blackProbeStreak = PiPFrameProbe.looksLikeProtectedVideo(samples: samples) ? blackProbeStreak + 1 : 0
        let isProtected = blackProbeStreak >= PiPFrameProbe.sustainedProbes
        guard isProtected != looksProtected else { return }
        looksProtected = isProtected
        DispatchQueue.main.async { [weak self] in
            guard let self, !isStopping else { return }
            onBlackRegion(isProtected)
        }
    }

    private func followContentAspect(_ attachments: [SCStreamFrameInfo: Any], stream: SCStream) {
        guard crop == nil, displayOrigin == nil, Date() >= settledAt,
              let rectInfo = attachments[.contentRect],
              let content = CGRect(dictionaryRepresentation: rectInfo as! CFDictionary),
              let contentAspect = PiPGeometry.aspect(of: content.size),
              PiPGeometry.hasAspectChanged(from: aspect, to: contentAspect) else { return }
        aspect = contentAspect
        settledAt = Date().addingTimeInterval(Self.aspectSettleDelay)
        configuration.height = Int((CGFloat(configuration.width) / contentAspect).rounded())
        Task { [configuration] in try? await stream.updateConfiguration(configuration) }
        DispatchQueue.main.async { [weak self] in
            guard let self, !isStopping else { return }
            onAspect(contentAspect)
        }
    }
}
