import Foundation
import CoreGraphics

/// The pure rules of "keep live": moving a PiP's source window onto the hidden virtual display so macOS never marks it
/// covered. All frames are in Accessibility coordinates (origin top-left of the main display, y down).
enum PiPKeepLive {
    static let unavailableNote = "Keep live is not available on this Mac"
    static let cannotKeepNote = "This window can't be kept live"
    static let gaveUpNote = "Keep live stopped: this app keeps moving its window back"

    enum Block: Equatable {
        case disabled, ownApp, fullScreen, minimized, hidden, notMovable, onHiddenDisplay

        /// What to tell the user when the window is not moved, or nil when nothing needs saying.
        var note: String? {
            switch self {
            case .disabled, .ownApp, .onHiddenDisplay: return nil
            case .fullScreen, .minimized, .hidden, .notMovable: return PiPKeepLive.cannotKeepNote
            }
        }
    }

    /// Why a window must not be moved to the hidden display, or nil when it can be.
    static func block(isEnabled: Bool, isOwnApp: Bool, isFullScreen: Bool, isMinimized: Bool, isHidden: Bool,
                      isPositionSettable: Bool, isOnHiddenDisplay: Bool) -> Block? {
        if !isEnabled { return .disabled }
        if isOwnApp { return .ownApp }
        if isFullScreen { return .fullScreen }
        if isMinimized { return .minimized }
        if isHidden { return .hidden }
        if !isPositionSettable { return .notMovable }
        if isOnHiddenDisplay { return .onHiddenDisplay }
        return nil
    }

    /// The frame for a window on the hidden display: the original size, shrunk to fit if larger, at the top-left corner of
    /// `display` (the display's visible frame, so it clears the menu bar).
    static func targetFrame(original: CGRect, in display: CGRect) -> CGRect {
        CGRect(x: display.minX, y: display.minY,
               width: min(original.width, display.width), height: min(original.height, display.height))
    }

    /// Whether the middle of a window frame lies on a display frame.
    static func isOn(_ frame: CGRect, display: CGRect) -> Bool {
        display.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// The frame to restore a window to. `originalDisplay` is the current frame of the display it came from, or nil when that
    /// display is gone; then the window keeps its size (shrunk to fit) and is moved inside `fallback`, the main display's visible frame.
    static func restoreFrame(original: CGRect, originalDisplay: CGRect?, fallback: CGRect) -> CGRect {
        if originalDisplay != nil { return original }
        let size = CGSize(width: min(original.width, fallback.width), height: min(original.height, fallback.height))
        return PiPGeometry.clamped(CGRect(origin: original.origin, size: size), in: fallback)
    }
}

/// Stops keep live from fighting an app that keeps moving its window off the hidden display: at most one move a second,
/// and give up after three moves in a row (moves more than `settleInterval` apart do not count as in a row).
struct PiPKeepLiveLimiter {
    enum Action: Equatable {
        case wait, move, giveUp
    }

    static let maxMoves = 3
    static let minInterval: TimeInterval = 1
    static let settleInterval: TimeInterval = 10

    private var moves = 0
    private var lastMove: Date?

    /// What to do now that the window is off the hidden display. A `.move` counts as a move.
    mutating func next(now: Date) -> Action {
        let since = lastMove.map { now.timeIntervalSince($0) }
        if let since, since >= Self.settleInterval { moves = 0 }
        if moves >= Self.maxMoves { return .giveUp }
        if let since, since < Self.minInterval { return .wait }
        moves += 1
        lastMove = now
        return .move
    }
}
