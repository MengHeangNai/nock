import CoreGraphics

enum PiPCropAction {
    case begin, cancel, reset
    case apply(PiPCrop)
}

/// The part of the source window a PiP shows, as a fraction of the window (each value 0...1, origin top-left), so it
/// survives window resizes. A crop is never smaller than `minimumSourceSize` points in the window.
struct PiPCrop: Equatable {
    static let minimumSourceSize: CGFloat = 48

    let rect: CGRect

    /// The crop for a selection drawn over the whole window's picture shown at `viewSize` (origin top-left): kept inside the
    /// picture and grown to the minimum size. Returns nil when the picture or the window has no size.
    init?(selection: CGRect, in viewSize: CGSize, windowSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0, windowSize.width > 0, windowSize.height > 0 else { return nil }
        let minimum = Self.minimumSize(in: CGSize(width: 1, height: 1), windowSize: windowSize)
        let drawn = selection.standardized
        let width = min(max(drawn.width / viewSize.width, minimum.width), 1)
        let height = min(max(drawn.height / viewSize.height, minimum.height), 1)
        rect = CGRect(x: min(max(drawn.minX / viewSize.width, 0), 1 - width),
                      y: min(max(drawn.minY / viewSize.height, 0), 1 - height),
                      width: width, height: height)
    }

    /// The minimum selection size, in the units of a picture of `viewSize` that shows a window of `windowSize` points.
    /// Pass a positive window size.
    static func minimumSize(in viewSize: CGSize, windowSize: CGSize) -> CGSize {
        CGSize(width: min(minimumSourceSize / windowSize.width, 1) * viewSize.width,
               height: min(minimumSourceSize / windowSize.height, 1) * viewSize.height)
    }

    /// The rectangle a drag from `start` to `point` draws inside a picture of `bounds` (origin top-left): at least
    /// `minimumSize`, growing away from `start`, and kept inside the picture.
    static func drawnRect(from start: CGPoint, to point: CGPoint, within bounds: CGSize, minimumSize: CGSize) -> CGRect {
        let end = CGPoint(x: min(max(point.x, 0), bounds.width), y: min(max(point.y, 0), bounds.height))
        let width = min(max(abs(end.x - start.x), minimumSize.width), bounds.width)
        let height = min(max(abs(end.y - start.y), minimumSize.height), bounds.height)
        return PiPGeometry.clamped(CGRect(x: end.x < start.x ? start.x - width : start.x,
                                          y: end.y < start.y ? start.y - height : start.y,
                                          width: width, height: height),
                                   in: CGRect(origin: .zero, size: bounds))
    }

    /// The crop as a rectangle in the points of a window of `windowSize` (origin top-left): the `sourceRect` of the
    /// capture stream. The stream fills its whole output with it, so no destination rectangle is needed.
    func sourceRect(in windowSize: CGSize) -> CGRect {
        frame(in: CGRect(origin: .zero, size: windowSize))
    }

    /// The crop's rectangle inside a window's `windowFrame`, in the same coordinates as that frame.
    func frame(in windowFrame: CGRect) -> CGRect {
        CGRect(x: windowFrame.minX + rect.minX * windowFrame.width, y: windowFrame.minY + rect.minY * windowFrame.height,
               width: rect.width * windowFrame.width, height: rect.height * windowFrame.height)
    }

    /// Width divided by height of the cropped area of a window of `windowSize` points, or nil when it has no size.
    func aspect(in windowSize: CGSize) -> CGFloat? {
        PiPGeometry.aspect(of: sourceRect(in: windowSize).size)
    }

    /// The capture size in pixels of the cropped area of a window of `windowSize` points at the display's backing scale.
    func captureSize(in windowSize: CGSize, scale: CGFloat) -> CGSize {
        PiPGeometry.captureSize(windowSize: sourceRect(in: windowSize).size, scale: scale)
    }
}

/// A grab point of the crop selection: its eight resize handles (corners and edges) and the inside, which moves it.
enum PiPCropHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move

    static var resizeHandles: [PiPCropHandle] { allCases.filter { $0 != .move } }

    private var movesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
    private var movesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
    private var movesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
    private var movesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }

    /// The handle of `rect` under `point` (origin top-left): a corner or an edge within `tolerance` of the point, else
    /// `.move` inside the rectangle, else nil outside it.
    static func handle(at point: CGPoint, in rect: CGRect, tolerance: CGFloat) -> PiPCropHandle? {
        guard rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { return nil }
        let toLeft = abs(point.x - rect.minX), toRight = abs(point.x - rect.maxX)
        let toTop = abs(point.y - rect.minY), toBottom = abs(point.y - rect.maxY)
        let onLeft = toLeft <= tolerance && toLeft <= toRight, onRight = toRight <= tolerance && toRight < toLeft
        let onTop = toTop <= tolerance && toTop <= toBottom, onBottom = toBottom <= tolerance && toBottom < toTop
        switch (onLeft, onRight, onTop, onBottom) {
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .bottomLeft
        case (_, true, true, _): return .topRight
        case (_, true, _, true): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .top
        case (_, _, _, true): return .bottom
        default: return rect.contains(point) ? .move : nil
        }
    }

    /// Where the handle sits on `rect`: a corner, the middle of an edge, or the center for `.move`.
    func anchor(in rect: CGRect) -> CGPoint {
        CGPoint(x: movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX,
                y: movesTop ? rect.minY : movesBottom ? rect.maxY : rect.midY)
    }

    /// `rect` after this handle is dragged by `translation`: the moved edges follow the drag but stay inside `bounds` and
    /// keep the rectangle at least `minimumSize`; `.move` shifts the whole rectangle and keeps it inside `bounds`.
    func dragged(_ rect: CGRect, by translation: CGSize, within bounds: CGSize, minimumSize: CGSize) -> CGRect {
        if self == .move {
            return PiPGeometry.clamped(rect.offsetBy(dx: translation.width, dy: translation.height),
                                       in: CGRect(origin: .zero, size: bounds))
        }
        var (left, right, top, bottom) = (rect.minX, rect.maxX, rect.minY, rect.maxY)
        if movesLeft { left = min(max(left + translation.width, 0), right - minimumSize.width) }
        if movesRight { right = max(min(right + translation.width, bounds.width), left + minimumSize.width) }
        if movesTop { top = min(max(top + translation.height, 0), bottom - minimumSize.height) }
        if movesBottom { bottom = max(min(bottom + translation.height, bounds.height), top + minimumSize.height) }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}
