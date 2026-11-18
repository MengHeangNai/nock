import AppKit
import ApplicationServices

final class MenuBarGapsMonitor {
    private struct Display {
        let id: CGDirectDisplayID
        let frame: CGRect
        let notch: ClosedRange<CGFloat>
    }

    private static let messagingTimeout: Float = 0.1
    private static let extrasMenuBarAttribute = "AXExtrasMenuBar"

    private let queue = DispatchQueue(label: "GlassDock.MenuBarGaps", qos: .utility)
    private let onChange: ([CGDirectDisplayID: MenuBarGaps]) -> Void
    private var isMeasuring = false
    private var isPending = false
    private var needsAppScan = true
    private var statusItemOwners: [pid_t] = []

    init(onChange: @escaping ([CGDirectDisplayID: MenuBarGaps]) -> Void) {
        self.onChange = onChange
    }

    func refresh(rescanningApps: Bool = false) {
        needsAppScan = needsAppScan || rescanningApps
        guard !isMeasuring else {
            isPending = true
            return
        }
        isMeasuring = true
        let rescan = needsAppScan
        needsAppScan = false
        let pids = NSWorkspace.shared.runningApplications.map(\.processIdentifier)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let displays = Self.displaysWithMenuBar()
        let allDisplays = NSScreen.physicalScreens.map(\.area.frame)

        queue.async { [weak self] in
            guard let self else { return }
            var gaps: [CGDirectDisplayID: MenuBarGaps] = [:]
            if AXIsProcessTrusted() {
                let items = MenuBarItems(menus: frontmost.map(Self.menuFrames) ?? [],
                                         statusItems: self.statusItemFrames(pids: pids, rescan: rescan),
                                         displays: allDisplays)
                if !items.isEmpty {
                    for display in displays {
                        gaps[display.id] = items.gaps(beside: display.notch, on: display.frame)
                    }
                }
            }
            DispatchQueue.main.async { self.finish(gaps) }
        }
    }

    private func finish(_ gaps: [CGDirectDisplayID: MenuBarGaps]) {
        isMeasuring = false
        onChange(gaps)
        if isPending {
            isPending = false
            refresh()
        }
    }

    private func statusItemFrames(pids: [pid_t], rescan: Bool) -> [CGRect] {
        if !rescan, !statusItemOwners.isEmpty {
            return statusItemOwners.flatMap(Self.statusItemFrames)
        }
        let found = pids.map { ($0, Self.statusItemFrames(of: $0)) }.filter { !$0.1.isEmpty }
        statusItemOwners = found.map(\.0)
        return found.flatMap(\.1)
    }

    private static func displaysWithMenuBar() -> [Display] {
        let screens = NSScreen.screensHaveSeparateSpaces ? NSScreen.physicalScreens : Array(NSScreen.screens.prefix(1))
        return screens.map { screen in
            let metrics = IslandMetrics(screen: screen)
            let half = metrics.notchWidth / 2
            return Display(id: screen.displayID, frame: screen.area.frame,
                           notch: (metrics.centerX - half)...(metrics.centerX + half))
        }
    }

    private static func menuFrames(of pid: pid_t) -> [CGRect] {
        children(of: pid, bar: kAXMenuBarAttribute).compactMap(AXWindow.frame)
    }

    private static func statusItemFrames(of pid: pid_t) -> [CGRect] {
        children(of: pid, bar: extrasMenuBarAttribute).compactMap(AXWindow.frame)
    }

    private static func children(of pid: pid_t, bar attribute: String) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &barRef) == .success,
              let barRef, CFGetTypeID(barRef) == AXUIElementGetTypeID() else { return [] }
        let bar = barRef as! AXUIElement
        AXUIElementSetMessagingTimeout(bar, messagingTimeout)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return [] }
        children.forEach { AXUIElementSetMessagingTimeout($0, messagingTimeout) }
        return children
    }
}
