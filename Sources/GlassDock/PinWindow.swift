import Foundation
import CoreGraphics

/// One display in Accessibility coordinates: origin at the top-left of the main display, y growing downwards.
struct DisplayArea: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect

    /// Builds an area from an NSScreen's `frame` and `visibleFrame` (bottom-left origin). Pass the main display's height.
    init(cocoaFrame: CGRect, cocoaVisibleFrame: CGRect, primaryHeight: CGFloat) {
        frame = WindowGeometry.flipped(cocoaFrame, primaryHeight: primaryHeight)
        visibleFrame = WindowGeometry.flipped(cocoaVisibleFrame, primaryHeight: primaryHeight)
    }
}

enum WindowGeometry {
    /// The one place that converts between NSScreen coordinates (origin bottom-left of the main display, y up) and
    /// Accessibility / CGWindowList coordinates (origin top-left of the main display, y down). The flip is its own inverse,
    /// so it works in both directions. Pass the height of the main display (`NSScreen.screens[0]`).
    static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The index of the display that holds most of the window, or the nearest one when it is off every display.
    static func displayIndex(for window: CGRect, among areas: [DisplayArea]) -> Int? {
        guard !areas.isEmpty else { return nil }
        let overlaps = areas.map { overlapArea(window, $0.frame) }
        if let best = overlaps.max(), best > 0, let index = overlaps.firstIndex(of: best) { return index }
        let center = CGPoint(x: window.midX, y: window.midY)
        let distances = areas.map { hypot($0.frame.midX - center.x, $0.frame.midY - center.y) }
        return distances.firstIndex(of: distances.min() ?? 0)
    }

    /// The window's frame on another display, keeping its relative position and size, kept inside that display's visible area.
    static func moved(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return target }
        let width = min((window.width / source.width * target.width).rounded(), target.width)
        let height = min((window.height / source.height * target.height).rounded(), target.height)
        let x = target.minX + ((window.minX - source.minX) / source.width * target.width).rounded()
        let y = target.minY + ((window.minY - source.minY) / source.height * target.height).rounded()
        return CGRect(x: min(max(x, target.minX), target.maxX - width),
                      y: min(max(y, target.minY), target.maxY - height),
                      width: width, height: height)
    }

    private static func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = a.intersection(b)
        return overlap.isNull ? 0 : overlap.width * overlap.height
    }
}

enum SnapPreset: CaseIterable, Identifiable {
    case leftHalf, rightHalf, topLeft, topRight, bottomLeft, bottomRight, center, maximize

    var id: Self { self }

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .center: return "Center"
        case .maximize: return "Maximize"
        }
    }

    var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topLeft: return "rectangle.inset.topleading.filled"
        case .topRight: return "rectangle.inset.toptrailing.filled"
        case .bottomLeft: return "rectangle.inset.bottomleading.filled"
        case .bottomRight: return "rectangle.inset.bottomtrailing.filled"
        case .center: return "rectangle.center.inset.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        }
    }

    static let centerFraction: CGFloat = 0.6

    /// The window frame for this preset inside a display's visible frame (menu bar and Dock excluded), in Accessibility coordinates.
    func frame(in visible: CGRect) -> CGRect {
        let leftWidth = (visible.width / 2).rounded(.down)
        let topHeight = (visible.height / 2).rounded(.down)
        let rightX = visible.minX + leftWidth
        let bottomY = visible.minY + topHeight
        let rightWidth = visible.width - leftWidth
        let bottomHeight = visible.height - topHeight

        switch self {
        case .leftHalf: return CGRect(x: visible.minX, y: visible.minY, width: leftWidth, height: visible.height)
        case .rightHalf: return CGRect(x: rightX, y: visible.minY, width: rightWidth, height: visible.height)
        case .topLeft: return CGRect(x: visible.minX, y: visible.minY, width: leftWidth, height: topHeight)
        case .topRight: return CGRect(x: rightX, y: visible.minY, width: rightWidth, height: topHeight)
        case .bottomLeft: return CGRect(x: visible.minX, y: bottomY, width: leftWidth, height: bottomHeight)
        case .bottomRight: return CGRect(x: rightX, y: bottomY, width: rightWidth, height: bottomHeight)
        case .center:
            let width = (visible.width * Self.centerFraction).rounded()
            let height = (visible.height * Self.centerFraction).rounded()
            return CGRect(x: visible.minX + ((visible.width - width) / 2).rounded(),
                          y: visible.minY + ((visible.height - height) / 2).rounded(),
                          width: width, height: height)
        case .maximize: return visible
        }
    }
}

struct WindowCandidate: Equatable {
    let pid: Int32
    let layer: Int
    let frame: CGRect
}

enum WindowFilter {
    static let minimumSize = CGSize(width: 100, height: 60)

    /// True for an ordinary window of another app: layer 0 (not the menu bar, Dock or a floating panel) and not tiny.
    static func isNormal(_ window: WindowCandidate, ownPID: Int32) -> Bool {
        window.pid != ownPID
            && window.layer == 0
            && window.frame.width >= minimumSize.width
            && window.frame.height >= minimumSize.height
    }
}

enum PinPolicy {
    static let minimumRaiseInterval: TimeInterval = 0.1
    static let dragDistance: CGFloat = 4
    static let dragHoldDuration: TimeInterval = 0.4

    /// Whether a held mouse button is a drag and not a plain click: the pointer moved more than a few points since the
    /// press, or the button has been held a while. Pass nil for `heldFor` when no button is held.
    static func isDragging(heldFor: TimeInterval?, travel: CGFloat) -> Bool {
        guard let heldFor else { return false }
        return travel > dragDistance || heldFor > dragHoldDuration
    }

    /// Whether a re-raise may run now: not while the user is dragging (a plain click on another window must not delay
    /// it) or in GlassDock's own Island, and not again right after the last raise, so two pinned windows cannot fight.
    static func canRaise(secondsSinceLastRaise: TimeInterval?, mouseHeldFor: TimeInterval?, mouseTravel: CGFloat,
                         isIslandInUse: Bool) -> Bool {
        guard !isDragging(heldFor: mouseHeldFor, travel: mouseTravel), !isIslandInUse else { return false }
        return (secondsSinceLastRaise ?? .infinity) >= minimumRaiseInterval
    }

    /// Puts pinned windows first, in pin order (most recently pinned first), then the others in their given order.
    static func pinnedFirst<ID: Hashable>(_ ids: [ID], pinned: [ID]) -> [ID] {
        let present = Set(ids)
        let first = pinned.filter(present.contains)
        let firstSet = Set(first)
        return first + ids.filter { !firstSet.contains($0) }
    }

    /// The pinned windows to raise now, in the order to raise them. `zOrder` lists the on-screen normal windows front
    /// to back with the app (`owner`) of each; `pinned` lists pinned window IDs with the most recently pinned first,
    /// which must end up on top. A pinned window needs a raise when a window overlapping it is in front of it and either
    /// belongs to another app and is not pinned or was pinned earlier, or belongs to the same app and was pinned earlier.
    /// An unpinned window of the same app never counts, so a raise only happens when another app covers the window.
    /// Windows that are not on screen are ignored. Raising goes from the lowest priority up to the highest, so the most
    /// recently pinned window finishes on top.
    static func windowsToRaise<ID: Hashable>(zOrder: [(id: ID, owner: Int32, frame: CGRect)], pinned: [ID]) -> [ID] {
        let rank = Dictionary(pinned.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var lowestPriorityNeedingRaise: Int?
        for (position, entry) in zOrder.enumerated() {
            guard let entryRank = rank[entry.id] else { continue }
            let hidden = zOrder[..<position].contains { front in
                guard !front.frame.intersection(entry.frame).isEmpty else { return false }
                guard let frontRank = rank[front.id] else { return front.owner != entry.owner }
                return frontRank > entryRank
            }
            if hidden { lowestPriorityNeedingRaise = max(lowestPriorityNeedingRaise ?? entryRank, entryRank) }
        }
        guard let lowest = lowestPriorityNeedingRaise else { return [] }
        return pinned[...lowest].reversed().filter { id in zOrder.contains { $0.id == id } }
    }

    static let frameMatchTolerance: CGFloat = 3

    /// The on-screen window of `pid` that matches a window's Accessibility `frame`, for when the private lookup of a
    /// window's ID is missing. Only layer 0 windows not in `claimed` count, each edge may differ by a few points, and the
    /// closest match wins (the frontmost one on a tie). `windows` goes front to back.
    static func windowID(matching frame: CGRect, pid: Int32, among windows: [OnScreenWindow],
                         excluding claimed: Set<CGWindowID> = []) -> CGWindowID? {
        func distance(_ other: CGRect) -> CGFloat {
            max(abs(other.minX - frame.minX), abs(other.minY - frame.minY),
                abs(other.maxX - frame.maxX), abs(other.maxY - frame.maxY))
        }
        return windows
            .filter { $0.candidate.pid == pid && $0.candidate.layer == 0 && !claimed.contains($0.id)
                && distance($0.candidate.frame) <= frameMatchTolerance }
            .min { distance($0.candidate.frame) < distance($1.candidate.frame) }?.id
    }
}
