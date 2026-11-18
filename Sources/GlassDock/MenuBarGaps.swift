import CoreGraphics

struct MenuBarGaps: Equatable {
    var left: CGFloat
    var right: CGFloat
}

struct MenuBarItems: Equatable {
    var menus: [CGRect]
    var statusItems: [CGRect]
    var displays: [CGRect]

    var isEmpty: Bool { menus.isEmpty && statusItems.isEmpty }

    func gaps(beside notch: ClosedRange<CGFloat>, on display: CGRect) -> MenuBarGaps {
        let center = (notch.lowerBound + notch.upperBound) / 2
        let menus = menus.compactMap { frame in
            source(of: frame).map { frame.offsetBy(dx: display.minX - $0.minX, dy: 0) }
        }
        let statusItems = statusItems.compactMap { frame in
            source(of: frame).map { frame.offsetBy(dx: display.maxX - $0.maxX, dy: 0) }
        }
        let shown = { (frame: CGRect) in
            frame.width > 0 && !(notch.contains(frame.minX) && notch.contains(frame.maxX))
        }
        let leftEdge = menus.filter { shown($0) && $0.midX < center }.map(\.maxX).max() ?? display.minX
        let rightEdge = (menus + statusItems).filter { shown($0) && $0.midX >= center }.map(\.minX).min() ?? display.maxX
        return MenuBarGaps(left: notch.lowerBound - leftEdge, right: rightEdge - notch.upperBound)
    }

    private func source(of frame: CGRect) -> CGRect? {
        displays.first { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }
    }
}
