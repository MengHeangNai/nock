import AppKit

extension NSScreen {
    /// The Core Graphics ID of this display. It stays the same while the display stays connected, so use it to match panels to screens.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
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
