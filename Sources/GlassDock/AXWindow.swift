import AppKit
import ApplicationServices

struct OnScreenWindow {
    let id: CGWindowID
    let candidate: WindowCandidate
}

/// Reads and writes a window's frame and identity through the Accessibility API and CGWindowList.
enum AXWindow {
    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindow? = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow")
        .map { unsafeBitCast($0, to: GetWindow.self) }

    /// An ID that stays the same for the life of the window element.
    static func identifier(of element: AXUIElement, pid: pid_t) -> String {
        "\(pid)-\(CFHash(element))"
    }

    /// The window's frame in Accessibility coordinates (top-left origin), or nil when the window cannot be read.
    static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Whether the window reports itself as full screen (the `AXFullScreen` attribute).
    static func hasFullScreenFlag(_ element: AXUIElement) -> Bool {
        var flag: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &flag) == .success && flag as? Bool == true
    }

    /// Whether the window is minimized (the `AXMinimized` attribute); false when it cannot be read.
    static func isMinimized(_ element: AXUIElement) -> Bool {
        var flag: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &flag) == .success && flag as? Bool == true
    }

    /// Whether the window element still exists. Only a closed window answers `.invalidUIElement`; a hidden or minimized one
    /// still answers, and any other error (busy app, no Accessibility access) counts as existing.
    static func exists(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) != .invalidUIElement
    }

    /// Sets size, then position, then size again: a window moved to another display can clamp the first size.
    static func setFrame(_ frame: CGRect, of element: AXUIElement) {
        var size = frame.size
        var origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue)
    }

    /// Whether the app lets the window's position be set (the `AXPosition` attribute is settable).
    static func isPositionSettable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXPositionAttribute as CFString, &settable) == .success && settable.boolValue
    }

    /// Moves the window to `origin` without changing its size.
    static func setOrigin(_ origin: CGPoint, of element: AXUIElement) {
        var origin = origin
        guard let originValue = AXValueCreate(.cgPoint, &origin) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, originValue)
    }

    /// The CGWindowID of a window. Uses the private `_AXUIElementGetWindow` when present, otherwise the on-screen window
    /// of the same app with the same frame, ignoring IDs in `claimed` (windows already matched to other elements).
    static func windowID(of element: AXUIElement, pid: pid_t, excluding claimed: Set<CGWindowID> = []) -> CGWindowID? {
        var id: CGWindowID = 0
        if let getWindow, getWindow(element, &id) == .success, id != 0 { return id }
        guard let frame = frame(of: element) else { return nil }
        return PinPolicy.windowID(matching: frame, pid: pid, among: onScreenWindows(), excluding: claimed)
    }

    /// Makes the window's app frontmost (it takes keyboard focus) and raises that window above other apps' windows.
    /// Returns `.success`, or the error that stopped the app from coming forward or the window from being raised.
    static func bringForward(_ element: AXUIElement, pid: pid_t) -> AXError {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
        let frontmost = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        let activated = frontmost == .success || NSRunningApplication(processIdentifier: pid)?.activate() == true
        let raised = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        return activated ? raised : frontmost
    }

    /// Unhides the window's app, restores the window when it is minimized, then brings it forward.
    /// Returns the result of `bringForward`.
    static func restore(_ element: AXUIElement, pid: pid_t) -> AXError {
        NSRunningApplication(processIdentifier: pid)?.unhide()
        if isMinimized(element) {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        return bringForward(element, pid: pid)
    }

    /// Every on-screen window from the WindowServer, front to back, with its layer and frame in Accessibility coordinates.
    static func onScreenWindows() -> [OnScreenWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return OnScreenWindow(id: number, candidate: WindowCandidate(pid: pid, layer: layer, frame: frame))
        }
    }
}
