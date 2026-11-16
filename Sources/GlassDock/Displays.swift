import AppKit

extension NSScreen {
    /// The Core Graphics ID of this display. It stays the same while the display stays connected, so use it to match panels to screens.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

extension NSScreen {
    /// The display's UUID string, the identifier the WindowServer uses for its Spaces.
    var displayUUID: String? {
        CGDisplayCreateUUIDFromDisplayID(displayID).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }
}

extension NSScreen {
    /// The screens GlassDock puts its own windows on and offers as move targets: every screen except its hidden virtual display.
    static var physicalScreens: [NSScreen] {
        screens.filter { !HiddenDisplayIdentity.isHidden($0.displayID) }
    }

    /// This screen in Accessibility coordinates (origin top-left of the main display, y down).
    var area: DisplayArea {
        DisplayArea(cocoaFrame: frame, cocoaVisibleFrame: visibleFrame, primaryHeight: NSScreen.screens.first?.frame.height ?? frame.height)
    }
}

/// How GlassDock's hidden virtual display (the "keep live" screen for PiP source windows) tells itself apart from real displays.
enum HiddenDisplayIdentity {
    static let name = "GlassDock Hidden Screen"
    static let vendorID: UInt32 = 0x4744
    static let productID: UInt32 = 0x4B4C
    static let serialNumber: UInt32 = 1

    /// Whether a display with this vendor and model number is GlassDock's hidden virtual display.
    static func matches(vendorID: UInt32, productID: UInt32) -> Bool {
        vendorID == Self.vendorID && productID == Self.productID
    }

    /// Whether this display is GlassDock's hidden virtual display. Reads the vendor and model number macOS reports for it.
    static func isHidden(_ id: CGDirectDisplayID) -> Bool {
        matches(vendorID: CGDisplayVendorNumber(id), productID: CGDisplayModelNumber(id))
    }
}

/// Which displays get a Dock.
enum DockDisplayMode: String, CaseIterable, Identifiable {
    case allDisplays, mainDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allDisplays: return "All displays"
        case .mainDisplay: return "Main display only"
        }
    }

    /// The displays that get a Dock. Pass every connected display's ID with the main display (the one with the menu bar) first.
    func displayIDs(among ids: [CGDirectDisplayID]) -> [CGDirectDisplayID] {
        switch self {
        case .allDisplays: return ids
        case .mainDisplay: return Array(ids.prefix(1))
        }
    }
}

enum BrightnessTarget {
    /// The display a brightness key changes: the one under the cursor when macOS can dim it, otherwise the built-in panel, otherwise nil so the key goes to macOS. `adjustable` holds the displays whose brightness can be read and set.
    static func display(underCursor: CGDirectDisplayID?, adjustable: Set<CGDirectDisplayID>, builtIn: CGDirectDisplayID?) -> CGDirectDisplayID? {
        if let underCursor, adjustable.contains(underCursor) { return underCursor }
        if let builtIn, adjustable.contains(builtIn) { return builtIn }
        return nil
    }
}
