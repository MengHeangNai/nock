import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

final class PiPPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private let controls = PiPControlsState()
    private let input: PiPInput
    private let cropModel: PiPCropModel
    private let content: PiPContentView
    private var space = IslandSpace()
    private var opacityObserver: AnyCancellable?
    private var aspect: CGFloat

    init(frame: CGRect, aspect: CGFloat, target: PiPTarget, onClose: @escaping () -> Void,
         onShowWindow: @escaping () -> Void, onCrop: @escaping (PiPCropAction) -> Void) {
        self.aspect = aspect
        input = PiPInput(target: target)
        cropModel = PiPCropModel(onDone: { onCrop(.apply($0)) }, onCancel: { onCrop(.cancel) })
        content = PiPContentView(frame: CGRect(origin: .zero, size: frame.size), input: input,
                                 controls: controls, cropModel: cropModel, onShowWindow: onShowWindow)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = content

        let host = PiPControlsHostingView(rootView: PiPControlsView(state: controls, onClose: onClose,
                                                                    onShowWindow: onShowWindow,
                                                                    onCrop: onCrop) { [weak self] preset in
            self?.resize(toWidth: preset.width)
        })
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        content.install(controlsHost: host)
        let cropHost = PiPCropHostingView(rootView: PiPCropView(model: cropModel))
        cropHost.frame = CGRect(origin: .zero, size: frame.size)
        cropHost.autoresizingMask = [.width, .height]
        content.install(cropHost: cropHost)

        opacityObserver = controls.$opacity.sink { [weak self] in self?.alphaValue = $0 }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            switch PiPInteraction.action(at: content.convert(event.locationInWindow, from: nil),
                                         modifiers: event.modifierFlags, panelSize: content.bounds.size) {
            case .drag:
                performDrag(with: event)
                return
            case .resize(let anchor):
                trackResize(anchor, from: event)
                return
            case .controls, .forward:
                break
            }
        }
        super.sendEvent(event)
    }

    func present() {
        orderFrontRegardless()
        space?.add(self)
    }

    func dismiss() {
        space = nil
        close()
    }

    func show(_ surface: IOSurface) {
        content.show(surface)
    }

    func setSource(_ state: PiPSourceState) {
        content.setSource(state)
    }

    func updateAspect(_ newAspect: CGFloat) {
        guard input.crop == nil else { return }
        followAspect(newAspect)
    }

    func setCrop(_ crop: PiPCrop?, aspect cropAspect: CGFloat) {
        input.crop = crop
        controls.hasCrop = crop != nil
        content.setCropping(false)
        followAspect(cropAspect)
    }

    func beginCropping(selection: PiPCrop?, windowSize: CGSize, aspect fullAspect: CGFloat) {
        input.crop = nil
        controls.hasCrop = false
        cropModel.begin(selection: selection?.rect, windowSize: windowSize)
        content.setCropping(true)
        followAspect(fullAspect)
    }

    private func followAspect(_ newAspect: CGFloat) {
        guard PiPGeometry.hasAspectChanged(from: aspect, to: newAspect) else { return }
        aspect = newAspect
        resize(toWidth: frame.width)
    }

    private func trackResize(_ anchor: PiPResizeAnchor, from event: NSEvent) {
        let start = frame
        let bounds = (screen ?? NSScreen.main)?.visibleFrame ?? start
        let grabbed = anchor.point(on: start)
        let pressed = convertPoint(toScreen: event.locationInWindow)
        let offset = CGPoint(x: pressed.x - grabbed.x, y: pressed.y - grabbed.y)
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture,
                                         inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { break }
            let pointer = NSEvent.mouseLocation
            setFrame(PiPGeometry.resized(frame: start, anchor: anchor,
                                         to: CGPoint(x: pointer.x - offset.x, y: pointer.y - offset.y),
                                         aspect: aspect, bounds: bounds), display: true)
        }
    }

    private func resize(toWidth width: CGFloat) {
        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? frame
        setFrame(PiPGeometry.resizedFrame(frame, toWidth: width, aspect: aspect, within: visible), display: true)
    }
}

final class PiPContentView: NSView {
    private static let cornerRadius: CGFloat = 10
    private static let hideDelay: TimeInterval = 1.5
    private static let exitHideDelay: TimeInterval = 0.4
    private static let fadeDuration: TimeInterval = 0.25

    private let input: PiPInput
    private let controls: PiPControlsState
    private let cropModel: PiPCropModel
    private let onShowWindow: () -> Void
    private let sourceModel = PiPSourceModel()
    private let pictureLayer = CALayer()
    private var controlsHost: NSView?
    private var cropHost: NSView?
    private var isCropping = false
    private var hideWork: DispatchWorkItem?
    private var forwardsLeftMouse = false
    private var showsResizeCursor = false

    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    init(frame: CGRect, input: PiPInput, controls: PiPControlsState, cropModel: PiPCropModel,
         onShowWindow: @escaping () -> Void) {
        self.input = input
        self.controls = controls
        self.cropModel = cropModel
        self.onShowWindow = onShowWindow
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        pictureLayer.contentsGravity = .resizeAspect
        layer?.addSublayer(pictureLayer)

        let unavailable = PiPUnavailableHostingView(model: sourceModel, onShowWindow: onShowWindow)
        unavailable.frame = bounds
        unavailable.autoresizingMask = [.width, .height]
        addSubview(unavailable)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func install(controlsHost host: NSView) {
        host.isHidden = true
        addSubview(host)
        controlsHost = host
    }

    func install(cropHost host: NSView) {
        host.isHidden = true
        addSubview(host)
        cropHost = host
    }

    func setCropping(_ cropping: Bool) {
        isCropping = cropping
        cropHost?.isHidden = !cropping
        guard cropping else { return }
        controlsHost?.isHidden = true
        controls.isVisible = false
        window?.makeKey()
        window?.makeFirstResponder(self)
    }

    func setSource(_ state: PiPSourceState) {
        if case .unavailable(let reason) = state {
            sourceModel.reason = reason
        } else {
            sourceModel.reason = nil
        }
    }

    func show(_ surface: IOSurface) {
        guard !isSourceUnavailable else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureLayer.contents = surface
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pictureLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        pictureLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways,
                                                 .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { showControls() }
    override func mouseExited(with event: NSEvent) {
        updateCursor(at: event.locationInWindow)
        scheduleHide(after: Self.exitHideDelay)
    }

    override func mouseMoved(with event: NSEvent) {
        showControls()
        updateCursor(at: event.locationInWindow)
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(at: event.locationInWindow) }

    override func mouseDown(with event: NSEvent) {
        guard !blocksInput else { return }
        if event.clickCount == 2 {
            onShowWindow()
            return
        }
        forwardsLeftMouse = true
        input.forwardMouse(event, in: self)
    }

    override func mouseDragged(with event: NSEvent) {
        if forwardsLeftMouse { input.forwardMouse(event, in: self) }
    }

    override func mouseUp(with event: NSEvent) {
        guard forwardsLeftMouse else { return }
        forwardsLeftMouse = false
        input.forwardMouse(event, in: self)
    }

    override func rightMouseDown(with event: NSEvent) { forwardMouseToSource(event) }
    override func rightMouseDragged(with event: NSEvent) { forwardMouseToSource(event) }
    override func rightMouseUp(with event: NSEvent) { forwardMouseToSource(event) }
    override func otherMouseDown(with event: NSEvent) { forwardMouseToSource(event) }
    override func otherMouseDragged(with event: NSEvent) { forwardMouseToSource(event) }
    override func otherMouseUp(with event: NSEvent) { forwardMouseToSource(event) }
    override func scrollWheel(with event: NSEvent) {
        guard !blocksInput else { return }
        input.forwardScroll(event, in: self)
    }

    override func keyDown(with event: NSEvent) {
        if isCropping {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: cropModel.confirm()
            case kVK_Escape: cropModel.cancel()
            default: break
            }
            return
        }
        guard !isSourceUnavailable else { return }
        input.forwardKey(event, isDown: true)
    }

    override func keyUp(with event: NSEvent) {
        guard !blocksInput else { return }
        input.forwardKey(event, isDown: false)
    }

    private func updateCursor(at windowPoint: NSPoint) {
        let action = PiPInteraction.action(at: convert(windowPoint, from: nil), modifiers: [], panelSize: bounds.size)
        if case .resize(let anchor) = action {
            anchor.cursor.set()
            showsResizeCursor = true
        } else if showsResizeCursor {
            NSCursor.arrow.set()
            showsResizeCursor = false
        }
    }

    private var isSourceUnavailable: Bool { sourceModel.reason != nil }
    private var blocksInput: Bool { isSourceUnavailable || isCropping }

    private func forwardMouseToSource(_ event: NSEvent) {
        guard !blocksInput else { return }
        input.forwardMouse(event, in: self)
    }

    private func showControls() {
        guard !isCropping else { return }
        controlsHost?.isHidden = false
        controls.isVisible = true
        scheduleHide(after: Self.hideDelay)
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hideControls() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func hideControls() {
        guard NSEvent.pressedMouseButtons == 0 else {
            scheduleHide(after: Self.hideDelay)
            return
        }
        controls.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration) { [weak self] in
            guard let self, !controls.isVisible else { return }
            controlsHost?.isHidden = true
        }
    }
}

private extension PiPResizeAnchor {
    var cursor: NSCursor {
        guard isCorner else { return growsLeft || growsRight ? .resizeLeftRight : .resizeUpDown }
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition = growsUp ? (growsLeft ? .topLeft : .topRight)
                                                                  : (growsLeft ? .bottomLeft : .bottomRight)
            return .frameResize(position: position, directions: .all)
        }
        return .crosshair
    }
}
