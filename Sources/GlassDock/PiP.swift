import AppKit
import Foundation
import CoreGraphics
import ScreenCaptureKit

enum PiPSizePreset: CaseIterable, Identifiable {
    case small, medium, large

    var id: Self { self }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var width: CGFloat {
        switch self {
        case .small: return 240
        case .medium: return 320
        case .large: return 480
        }
    }
}

enum PiPGeometry {
    static let defaultWidth = PiPSizePreset.medium.width
    static let minimumWidth: CGFloat = 160
    static let margin: CGFloat = 20
    static let cascadeStep: CGFloat = 28
    static let aspectTolerance: CGFloat = 0.01

    /// Width divided by height of a size, or nil when either side is not positive.
    static func aspect(of size: CGSize) -> CGFloat? {
        guard size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }

    /// Whether a new aspect differs enough from the current one (more than 1%) to resize the panel and the capture.
    static func hasAspectChanged(from current: CGFloat, to new: CGFloat) -> Bool {
        abs(new - current) / current > aspectTolerance
    }

    /// The panel size for a wanted width at the source's aspect: shrunk to fit inside `bounds`, never narrower than the minimum width.
    static func fittedSize(width: CGFloat, aspect: CGFloat, within bounds: CGSize) -> CGSize {
        var fitted = min(width, bounds.width)
        if fitted / aspect > bounds.height { fitted = bounds.height * aspect }
        fitted = max(fitted, minimumWidth)
        return CGSize(width: fitted.rounded(), height: (fitted / aspect).rounded())
    }

    /// The panel frame after a resize to `width` at `aspect`: the same center, the size from `fittedSize`, moved the shortest
    /// way to lie inside `visible`. A panel the user dragged elsewhere is never put back at a default position.
    static func resizedFrame(_ frame: CGRect, toWidth width: CGFloat, aspect: CGFloat, within visible: CGRect) -> CGRect {
        let size = fittedSize(width: width, aspect: aspect, within: visible.size)
        return clamped(CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                              width: size.width, height: size.height), in: visible)
    }

    /// The capture size in pixels for a window of `windowSize` points on a display with the given backing scale (2 on Retina).
    static func captureSize(windowSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: (windowSize.width * scale).rounded(.up), height: (windowSize.height * scale).rounded(.up))
    }

    /// The frame moved the shortest way to lie inside `bounds` (or pinned to its bottom-left when larger).
    static func clamped(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(x: min(max(frame.minX, bounds.minX), max(bounds.maxX - frame.width, bounds.minX)),
               y: min(max(frame.minY, bounds.minY), max(bounds.maxY - frame.height, bounds.minY)),
               width: frame.width, height: frame.height)
    }

    /// The panel frame while a corner or edge is dragged to `point` (NSScreen coordinates; the position the dragged corner
    /// or edge should have). The aspect stays locked and the opposite corner (or the middle of the opposite edge) stays
    /// put; an edge drag changes one dimension, derives the other and keeps the perpendicular axis centered. The width is
    /// never below `minWidth` and the frame never leaves `bounds`.
    static func resized(frame: CGRect, anchor: PiPResizeAnchor, to point: CGPoint, aspect: CGFloat,
                        minWidth: CGFloat = minimumWidth, bounds: CGRect) -> CGRect {
        let fixedX = anchor.growsLeft ? frame.maxX : anchor.growsRight ? frame.minX : frame.midX
        let fixedY = anchor.growsDown ? frame.maxY : anchor.growsUp ? frame.minY : frame.midY
        var wanted: CGFloat = 0
        var room = CGFloat.greatestFiniteMagnitude
        if anchor.growsLeft || anchor.growsRight {
            wanted = max(wanted, anchor.growsRight ? point.x - fixedX : fixedX - point.x)
            room = min(room, anchor.growsRight ? bounds.maxX - fixedX : fixedX - bounds.minX)
        } else {
            room = min(room, 2 * min(frame.midX - bounds.minX, bounds.maxX - frame.midX))
        }
        if anchor.growsUp || anchor.growsDown {
            wanted = max(wanted, (anchor.growsUp ? point.y - fixedY : fixedY - point.y) * aspect)
            room = min(room, (anchor.growsUp ? bounds.maxY - fixedY : fixedY - bounds.minY) * aspect)
        } else {
            room = min(room, 2 * min(frame.midY - bounds.minY, bounds.maxY - frame.midY) * aspect)
        }
        let width = max(min(wanted, room), minWidth).rounded()
        let height = (width / aspect).rounded()
        return clamped(CGRect(x: anchor.growsLeft ? fixedX - width : anchor.growsRight ? fixedX : fixedX - width / 2,
                              y: anchor.growsDown ? fixedY - height : anchor.growsUp ? fixedY : fixedY - height / 2,
                              width: width, height: height), in: bounds)
    }

    /// The panel frame in NSScreen coordinates for the `cascade`-th open PiP: the bottom-right corner of the display's
    /// visible frame, each later PiP shifted up and left so they do not hide each other, always kept on that display.
    static func initialFrame(size: CGSize, in visibleFrame: CGRect, cascade: Int) -> CGRect {
        let shift = CGFloat(cascade) * cascadeStep
        return clamped(CGRect(x: visibleFrame.maxX - margin - size.width - shift,
                              y: visibleFrame.minY + margin + shift, width: size.width, height: size.height),
                       in: visibleFrame)
    }

    /// The global point (Accessibility and CGEvent coordinates, origin top-left of the main display, y down) of the real
    /// window that sits under a point of the panel. `panelPoint` is in the panel's own coordinates (origin bottom-left,
    /// y up) and `windowFrame` is the real window's current Accessibility frame, which may have a negative y on a display
    /// above the main one. With a `crop` the panel shows only that part of the window, so the point is mapped into the
    /// cropped area. Points, not pixels: a Retina scale does not change the mapping. Returns nil for an empty panel.
    static func globalPoint(forPanelPoint panelPoint: CGPoint, panelSize: CGSize, windowFrame: CGRect,
                            crop: PiPCrop? = nil) -> CGPoint? {
        guard panelSize.width > 0, panelSize.height > 0 else { return nil }
        let shown = crop?.frame(in: windowFrame) ?? windowFrame
        return CGPoint(x: shown.minX + panelPoint.x / panelSize.width * shown.width,
                       y: shown.minY + (panelSize.height - panelPoint.y) / panelSize.height * shown.height)
    }
}

enum PiPResizeAnchor: CaseIterable, Equatable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var growsLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var growsRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var growsUp: Bool { self == .topLeft || self == .top || self == .topRight }
    var growsDown: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    var isCorner: Bool { (growsLeft || growsRight) && (growsUp || growsDown) }

    /// The corner or edge middle of `frame` that this anchor drags.
    func point(on frame: CGRect) -> CGPoint {
        CGPoint(x: growsLeft ? frame.minX : growsRight ? frame.maxX : frame.midX,
                y: growsDown ? frame.minY : growsUp ? frame.maxY : frame.midY)
    }
}

enum PiPInteraction {
    enum Action: Equatable {
        case drag, controls, forward
        case resize(PiPResizeAnchor)
    }

    static let dragBarHeight: CGFloat = 22
    static let controlsBarHeight: CGFloat = 36
    static let cornerSize: CGFloat = 18
    static let topCornerSize: CGFloat = 10
    static let edgeWidth: CGFloat = 8

    /// The distances from the panel's top edge covered by the controls row, which sits under the drag bar.
    static var controlsRow: Range<CGFloat> { dragBarHeight..<(dragBarHeight + controlsBarHeight) }

    /// What a left mouse press at `point` of the panel (origin bottom-left, y up) does, first match wins: `.resize` from
    /// a corner (18 points; only 10 at the top corners, which sit on the drag bar), `.controls` for the hover controls row
    /// (inset by the edge width so the left and right edges still resize), `.drag` for the top drag bar, `.resize` from the
    /// left, right and bottom edge (8 points; the top edge is the drag bar), `.drag` when Option is held anywhere on the
    /// picture, and `.forward` for the rest, which goes to the real window. Nothing of a `.drag` or `.resize` press is
    /// ever forwarded, and points outside the panel are `.forward`.
    static func action(at point: CGPoint, modifiers: NSEvent.ModifierFlags, panelSize: CGSize) -> Action {
        guard (0...panelSize.width).contains(point.x), (0...panelSize.height).contains(point.y) else { return .forward }
        let fromTop = panelSize.height - point.y
        let fromRight = panelSize.width - point.x
        if fromTop < topCornerSize {
            if point.x < topCornerSize { return .resize(.topLeft) }
            if fromRight < topCornerSize { return .resize(.topRight) }
        } else if point.y < cornerSize {
            if point.x < cornerSize { return .resize(.bottomLeft) }
            if fromRight < cornerSize { return .resize(.bottomRight) }
        }
        if controlsRow.contains(fromTop), point.x >= edgeWidth, fromRight >= edgeWidth { return .controls }
        if fromTop < dragBarHeight { return .drag }
        if point.x < edgeWidth { return .resize(.left) }
        if fromRight < edgeWidth { return .resize(.right) }
        if point.y < edgeWidth { return .resize(.bottom) }
        return modifiers.contains(.option) ? .drag : .forward
    }
}

enum PiPEligibility {
    enum Block: Equatable {
        case ownApp, minimized, fullScreen

        var reason: String {
            switch self {
            case .ownApp: return "GlassDock's own windows can't be shown in Picture in Picture"
            case .minimized: return "A minimized window can't be shown in Picture in Picture"
            case .fullScreen: return "A full-screen window can't be shown in Picture in Picture"
            }
        }
    }

    /// Why a window cannot get a PiP, or nil when it can.
    static func block(isMinimized: Bool, isFullScreen: Bool, pid: Int32, ownPID: Int32) -> Block? {
        if pid == ownPID { return .ownApp }
        if isMinimized { return .minimized }
        if isFullScreen { return .fullScreen }
        return nil
    }
}

enum PiPSourceState: Equatable {
    enum Reason: Equatable {
        case hidden, minimized, notVisible

        var title: String {
            switch self {
            case .hidden: return "Window hidden"
            case .minimized: return "Window minimized"
            case .notVisible: return "Window not visible"
            }
        }

        var symbol: String {
            switch self {
            case .hidden: return "eye.slash"
            case .minimized: return "minus.rectangle"
            case .notVisible: return "rectangle.slash"
            }
        }
    }

    case live
    case unavailable(Reason)

    static let checkInterval: TimeInterval = 0.5
    static let blankTolerance: TimeInterval = 0.5
    static let frameWidthTolerance = 2

    /// Whether the real window can be captured now. A hidden app wins over a minimized window. Blank or suspended frames
    /// for longer than the tolerance also count as not visible; idle frames (a static window) never do, so pass only the
    /// time since the stream first reported blank or suspended. A window on another Space stays live: the PiP keeps
    /// its last picture.
    static func decide(appHidden: Bool, minimized: Bool, secondsOfBlankFrames: TimeInterval) -> PiPSourceState {
        if appHidden { return .unavailable(.hidden) }
        if minimized { return .unavailable(.minimized) }
        if secondsOfBlankFrames > blankTolerance { return .unavailable(.notVisible) }
        return .live
    }

    /// Whether a captured frame may replace the picture: a complete frame whose surface has a size and the capture width
    /// (within a couple of pixels; the width of the cropped area while a crop is active). Idle, blank, suspended and
    /// stopped frames never do, so the last good picture stays.
    static func isValidFrame(status: SCFrameStatus, surfaceSize: CGSize, expectedWidth: Int) -> Bool {
        status == .complete && surfaceSize.width > 0 && surfaceSize.height > 0
            && abs(Int(surfaceSize.width) - expectedWidth) <= frameWidthTolerance
    }
}
