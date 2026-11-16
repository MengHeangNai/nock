import AppKit
import ApplicationServices

struct PiPTarget {
    let element: AXUIElement
    let pid: pid_t
    let windowID: CGWindowID
}

/// Sends a PiP panel's mouse, scroll and key events to the app that owns the real window, as CGEvents posted to its
/// process. Best effort: apps may ignore events that did not come from the hardware or arrive while they are in the background.
final class PiPInput {
    private static let lineScrollPixels: CGFloat = 10

    private let target: PiPTarget
    private var windowFrame: CGRect?
    var crop: PiPCrop?

    init(target: PiPTarget) {
        self.target = target
        AXUIElementSetMessagingTimeout(target.element, 0.2)
    }

    /// Posts a mouse button or drag event of `view`'s panel at the matching point of the real window.
    /// The window's frame is read again on each button press and reused until the next one.
    func forwardMouse(_ event: NSEvent, in view: NSView) {
        guard let (type, button) = Self.mouseKind(of: event.type, buttonNumber: event.buttonNumber) else { return }
        if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type) { windowFrame = nil }
        guard let point = globalPoint(of: event, in: view),
              let cgEvent = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        else { return }
        cgEvent.setIntegerValueField(.mouseEventClickState, value: Int64(event.clickCount))
        post(cgEvent, modifiers: event.modifierFlags)
    }

    func forwardScroll(_ event: NSEvent, in view: NSView) {
        windowFrame = nil
        let factor = event.hasPreciseScrollingDeltas ? 1 : Self.lineScrollPixels
        guard let point = globalPoint(of: event, in: view),
              let cgEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                    wheel1: Int32(event.scrollingDeltaY * factor),
                                    wheel2: Int32(event.scrollingDeltaX * factor), wheel3: 0)
        else { return }
        cgEvent.location = point
        post(cgEvent, modifiers: event.modifierFlags)
    }

    func forwardKey(_ event: NSEvent, isDown: Bool) {
        guard let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: event.keyCode, keyDown: isDown) else { return }
        if isDown, let characters = event.characters, !characters.isEmpty {
            var units = Array(characters.utf16)
            cgEvent.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        }
        post(cgEvent, modifiers: event.modifierFlags)
    }

    private func globalPoint(of event: NSEvent, in view: NSView) -> CGPoint? {
        if windowFrame == nil { windowFrame = AXWindow.frame(of: target.element) }
        guard let windowFrame else { return nil }
        return PiPGeometry.globalPoint(forPanelPoint: view.convert(event.locationInWindow, from: nil),
                                       panelSize: view.bounds.size, windowFrame: windowFrame, crop: crop)
    }

    private func post(_ event: CGEvent, modifiers: NSEvent.ModifierFlags) {
        event.flags = CGEventFlags(rawValue: UInt64(modifiers.intersection(.deviceIndependentFlagsMask).rawValue))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(target.windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(target.windowID))
        event.postToPid(target.pid)
    }

    private static func mouseKind(of type: NSEvent.EventType, buttonNumber: Int) -> (CGEventType, CGMouseButton)? {
        switch type {
        case .leftMouseDown: return (.leftMouseDown, .left)
        case .leftMouseUp: return (.leftMouseUp, .left)
        case .leftMouseDragged: return (.leftMouseDragged, .left)
        case .rightMouseDown: return (.rightMouseDown, .right)
        case .rightMouseUp: return (.rightMouseUp, .right)
        case .rightMouseDragged: return (.rightMouseDragged, .right)
        case .otherMouseDown: return (.otherMouseDown, CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center)
        case .otherMouseUp: return (.otherMouseUp, CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center)
        case .otherMouseDragged: return (.otherMouseDragged, CGMouseButton(rawValue: UInt32(buttonNumber)) ?? .center)
        default: return nil
        }
    }
}
