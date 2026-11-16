import AppKit
import ApplicationServices

final class PiPKeepLiveWindows {
    enum Outcome: Equatable {
        case kept
        case notKept(note: String?)
    }

    enum Reassert: Equatable {
        case unchanged, moved, gaveUp
    }

    private struct Entry {
        let element: AXUIElement
        let originalFrame: CGRect
        let originalDisplayID: CGDirectDisplayID?
        var limiter = PiPKeepLiveLimiter()
    }

    private static let placementDelay: UInt64 = 300_000_000

    private let host = VirtualDisplayHost.shared
    private var entries: [String: Entry] = [:]

    var keptIDs: Set<String> { Set(entries.keys) }

    func isKept(_ id: String) -> Bool {
        entries[id] != nil
    }

    func keep(_ window: OpenWindow, id: String, isEnabled: Bool, ownPID: pid_t) async -> Outcome {
        let element = window.element
        guard entries[id] == nil, let frame = AXWindow.frame(of: element) else { return .notKept(note: nil) }
        let hiddenFrame = host.screen?.area.frame
        let block = PiPKeepLive.block(
            isEnabled: isEnabled, isOwnApp: window.pid == ownPID,
            isFullScreen: window.isFullScreen || AXWindow.hasFullScreenFlag(element),
            isMinimized: AXWindow.isMinimized(element),
            isHidden: NSRunningApplication(processIdentifier: window.pid)?.isHidden ?? false,
            isPositionSettable: AXWindow.isPositionSettable(element),
            isOnHiddenDisplay: hiddenFrame.map { PiPKeepLive.isOn(frame, display: $0) } ?? false)
        if let block { return .notKept(note: block.note) }
        guard let screen = await host.acquire(for: id) else { return .notKept(note: PiPKeepLive.unavailableNote) }

        let area = screen.area
        let physical = NSScreen.physicalScreens
        let originalDisplayID = WindowGeometry.displayIndex(for: frame, among: physical.map(\.area)).map { physical[$0].displayID }
        place(PiPKeepLive.targetFrame(original: frame, in: area.visibleFrame), of: element, from: frame)
        try? await Task.sleep(nanoseconds: Self.placementDelay)
        guard let placed = AXWindow.frame(of: element), PiPKeepLive.isOn(placed, display: area.frame) else {
            place(frame, of: element, from: AXWindow.frame(of: element) ?? frame)
            host.release(id)
            return .notKept(note: PiPKeepLive.cannotKeepNote)
        }
        entries[id] = Entry(element: element, originalFrame: frame, originalDisplayID: originalDisplayID)
        return .kept
    }

    func restore(_ id: String) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        defer { host.release(id) }
        guard let frame = AXWindow.frame(of: entry.element), let hidden = host.screen?.area.frame,
              PiPKeepLive.isOn(frame, display: hidden) else { return }
        let physical = NSScreen.physicalScreens
        let originalDisplay = physical.first { $0.displayID == entry.originalDisplayID }?.area.frame
        let fallback = physical.first?.area.visibleFrame ?? entry.originalFrame
        place(PiPKeepLive.restoreFrame(original: entry.originalFrame, originalDisplay: originalDisplay, fallback: fallback),
              of: entry.element, from: frame)
    }

    func restoreAll() {
        Array(entries.keys).forEach(restore)
    }

    func reassert(_ id: String, now: Date = Date()) -> Reassert {
        guard var entry = entries[id], let frame = AXWindow.frame(of: entry.element), let area = host.screen?.area,
              !PiPKeepLive.isOn(frame, display: area.frame) else { return .unchanged }
        let action = entry.limiter.next(now: now)
        entries[id] = entry
        switch action {
        case .wait:
            return .unchanged
        case .move:
            place(PiPKeepLive.targetFrame(original: frame, in: area.visibleFrame), of: entry.element, from: frame)
            return .moved
        case .giveUp:
            entries[id] = nil
            host.release(id)
            return .gaveUp
        }
    }

    private func place(_ target: CGRect, of element: AXUIElement, from current: CGRect) {
        if target.size == current.size {
            AXWindow.setOrigin(target.origin, of: element)
        } else {
            AXWindow.setFrame(target, of: element)
        }
    }
}
