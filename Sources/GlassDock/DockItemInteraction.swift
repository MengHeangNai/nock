import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Mouse handling

/// Handles clicks on a Dock item the way the macOS Dock does: the icon darkens while pressed,
/// a click opens it, and a right-click, Control-click or press-and-hold shows its menu above the icon.
struct DockItemMouse: NSViewRepresentable {
    var onPress: (Bool) -> Void
    var onClick: (NSEvent.ModifierFlags) -> Void
    var makeMenu: () -> [DockMenuEntry]
    var onMenu: (Bool) -> Void

    func makeNSView(context: Context) -> DockItemMouseView {
        let view = DockItemMouseView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: DockItemMouseView, context: Context) {
        view.onPress = onPress
        view.onClick = onClick
        view.makeMenu = makeMenu
        view.onMenu = onMenu
    }
}

final class DockItemMouseView: NSView {
    var onPress: ((Bool) -> Void)?
    var onClick: ((NSEvent.ModifierFlags) -> Void)?
    var makeMenu: (() -> [DockMenuEntry])?
    var onMenu: ((Bool) -> Void)?

    private var holdTimer: Timer?
    private var pressed = false
    private var menuShown = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showMenu()
            return
        }
        menuShown = false
        setPressed(true)
        let timer = Timer(timeInterval: 0.6, repeats: false) { [weak self] _ in self?.showMenu() }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        holdTimer = nil
        let wasPressed = pressed
        setPressed(false)
        guard wasPressed, !menuShown else { return }
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?(event.modifierFlags)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu()
    }

    private func setPressed(_ value: Bool) {
        guard value != pressed else { return }
        pressed = value
        onPress?(value)
    }

    /// Shows the menu above the icon. A second right-click on the same icon closes it instead.
    private func showMenu() {
        holdTimer?.invalidate()
        holdTimer = nil
        setPressed(false)
        menuShown = true
        let controller = DockMenuController.shared
        let owner = ObjectIdentifier(self)
        guard !controller.justClosed(owner: owner), let window,
              let entries = makeMenu?(), !entries.isEmpty else { return }
        let anchor = window.convertToScreen(convert(bounds, to: nil))
        let onMenu = onMenu
        onMenu?(true)
        controller.show(entries, anchor: anchor, owner: owner) { onMenu?(false) }
    }
}

// MARK: - Menu model

struct DockMenuItem: Identifiable {
    let id = UUID()
    var title: String
    var icon: NSImage?
    var checked = false
    var minimized = false
    var submenu: [DockMenuEntry]?
    /// Shown in place of this item while Option is held (for example Quit → Force Quit).
    var alternate: (title: String, action: () -> Void)?
    var action: (() -> Void)?
}

enum DockMenuEntry {
    case item(DockMenuItem)
    case separator
}

extension DockModel {
    /// The menu the macOS Dock shows for an app. Running: its windows, Options, Show All Windows,
    /// Hide and Quit. Not running: its recent documents, Options and Open.
    func menuEntries(for app: DockApp, open: @escaping () -> Void) -> [DockMenuEntry] {
        var entries: [DockMenuEntry] = []

        if let running = app.running {
            let windows = AppWindows.list(pid: running.processIdentifier)
            for window in windows {
                entries.append(.item(DockMenuItem(
                    title: window.title,
                    checked: !window.minimized && window.isMain && running.isActive,
                    minimized: window.minimized,
                    action: { AppWindows.bringForward(window, pid: running.processIdentifier) })))
            }
            if !windows.isEmpty { entries.append(.separator) }
        } else if let bundleID = app.bundleID {
            let documents = RecentDocuments.urls(bundleID: bundleID)
            for url in documents {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 32, height: 32)
                entries.append(.item(DockMenuItem(
                    title: FileManager.default.displayName(atPath: url.path), icon: icon,
                    action: { [weak self] in self?.openDocument(url, with: app) })))
            }
            if !documents.isEmpty { entries.append(.separator) }
        }

        if app.isFinder {
            entries.append(.item(DockMenuItem(title: "New Finder Window",
                                              action: { [weak self] in self?.newFinderWindow() })))
            entries.append(.separator)
        }

        let options: [DockMenuEntry] = [
            .item(DockMenuItem(title: "Keep in Dock", checked: app.isPinned,
                               action: { [weak self] in self?.togglePin(app) })),
            .separator,
            .item(DockMenuItem(title: "Show in Finder", action: { [weak self] in self?.reveal(app) })),
        ]
        entries.append(.item(DockMenuItem(title: "Options", submenu: options)))
        entries.append(.separator)

        if let running = app.running {
            entries.append(.item(DockMenuItem(title: "Show All Windows",
                                              action: { [weak self] in self?.showAllWindows(app) })))
            let hideOthers: (title: String, action: () -> Void) = (
                title: "Hide Others", action: { [weak self] in self?.openHidingOthers(app) }
            )
            if running.isHidden {
                entries.append(.item(DockMenuItem(title: "Show", alternate: hideOthers,
                                                  action: { running.unhide() })))
            } else {
                entries.append(.item(DockMenuItem(title: "Hide", alternate: hideOthers,
                                                  action: { [weak self] in self?.hide(app) })))
            }
            if !app.isFinder {
                entries.append(.item(DockMenuItem(
                    title: "Quit",
                    alternate: (title: "Force Quit", action: { [weak self] in self?.forceQuit(app) }),
                    action: { [weak self] in self?.quit(app) })))
            }
        } else {
            entries.append(.item(DockMenuItem(title: "Open", action: open)))
        }
        return entries
    }

    func trashMenuEntries() -> [DockMenuEntry] {
        [.item(DockMenuItem(title: "Open", action: { [weak self] in self?.openTrash() }))]
    }
}

// MARK: - Menu window

/// Shows Dock menus in a borderless panel drawn like the macOS Dock's menus: a rounded bubble
/// with a pointer to the icon. GlassDock never becomes the active app, so a regular NSMenu can't
/// look like this, and hover, Option and outside clicks are tracked here instead.
final class DockMenuController {
    static let shared = DockMenuController()

    private var panel: DockMenuPanel?
    private var subPanel: DockMenuPanel?
    private var mainState: DockMenuState?
    private var subState: DockMenuState?
    private var owner: ObjectIdentifier?
    private var onClose: (() -> Void)?
    private var monitors: [Any] = []
    private var modifierTimer: Timer?
    private var lastClose: (owner: ObjectIdentifier, time: Date)?

    private static let margin: CGFloat = 6

    func show(_ entries: [DockMenuEntry], anchor: CGRect, owner: ObjectIdentifier,
              onClose: @escaping () -> Void) {
        close()
        self.owner = owner
        self.onClose = onClose

        let state = DockMenuState()
        mainState = state
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let bounds = screen?.frame ?? anchor.insetBy(dx: -1000, dy: -1000)

        let panel = DockMenuPanel()
        let host = FirstMouseHostingView(rootView: AnyView(
            DockMenuView(entries: entries, arrowX: 0, state: state, controller: self)))
        let size = host.fittingSize
        var x = anchor.midX - size.width / 2
        x = min(max(x, bounds.minX + Self.margin), bounds.maxX - Self.margin - size.width)
        host.rootView = AnyView(
            DockMenuView(entries: entries, arrowX: anchor.midX - x, state: state, controller: self))
        panel.contentView = host
        panel.setFrame(NSRect(x: x, y: anchor.maxY + 2, width: size.width, height: size.height), display: true)
        present(panel)
        self.panel = panel

        startTracking()
    }

    /// True right after this owner's menu was closed by a click, so that click doesn't reopen it.
    func justClosed(owner: ObjectIdentifier) -> Bool {
        guard let lastClose, lastClose.owner == owner else { return false }
        return Date().timeIntervalSince(lastClose.time) < 0.3
    }

    func close() {
        guard panel != nil else { return }
        if let owner { lastClose = (owner, Date()) }
        hideSubmenu()
        panel?.orderOut(nil)
        panel = nil
        mainState = nil
        owner = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        modifierTimer?.invalidate()
        modifierTimer = nil
        let onClose = self.onClose
        self.onClose = nil
        onClose?()
    }

    fileprivate func select(_ item: DockMenuItem, in state: DockMenuState) {
        guard item.submenu == nil else { return }
        let action = state.optionDown ? (item.alternate?.action ?? item.action) : item.action
        close()
        action?()
    }

    fileprivate func hovered(_ item: DockMenuItem, in state: DockMenuState) {
        guard state === mainState else { return }
        if let submenu = item.submenu {
            if state.openSubmenu != item.id { showSubmenu(submenu, for: item, state: state) }
        } else {
            hideSubmenu()
        }
    }

    private func showSubmenu(_ entries: [DockMenuEntry], for item: DockMenuItem, state: DockMenuState) {
        hideSubmenu()
        guard let panel, let row = state.rowFrames[item.id] else { return }
        state.openSubmenu = item.id
        let sub = DockMenuState()
        sub.optionDown = state.optionDown
        subState = sub

        let subPanel = DockMenuPanel()
        let host = FirstMouseHostingView(rootView: AnyView(
            DockMenuView(entries: entries, arrowX: nil, state: sub, controller: self)))
        subPanel.contentView = host
        let size = host.fittingSize
        let bounds = panel.screen?.frame ?? panel.frame.insetBy(dx: -1000, dy: -1000)
        var x = panel.frame.minX + row.maxX - 2
        if x + size.width > bounds.maxX - Self.margin {
            x = panel.frame.minX + row.minX - size.width + 2
        }
        let top = panel.frame.maxY - row.minY + DockMenuView.verticalPadding
        let y = max(top - size.height, bounds.minY + Self.margin)
        subPanel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        present(subPanel)
        self.subPanel = subPanel
    }

    private func hideSubmenu() {
        subPanel?.orderOut(nil)
        subPanel = nil
        subState = nil
        mainState?.openSubmenu = nil
    }

    private func present(_ panel: DockMenuPanel) {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.async { panel.invalidateShadow() }
    }

    private func startTracking() {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps close the menu. Escape works too once Accessibility is allowed.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: clicks.union(.keyDown), handler: { [weak self] event in
            if event.type == .keyDown {
                if event.keyCode == 53 { self?.close() }
            } else {
                self?.close()
            }
        }) {
            monitors.append(global)
        }
        // Clicks in GlassDock's own windows (the Dock bar, the island) close it and are used up,
        // like the macOS Dock, except a right-click, which goes on to open that item's menu.
        if let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            guard let self else { return event }
            if let window = event.window, window === self.panel || window === self.subPanel { return event }
            self.close()
            return event.type == .rightMouseDown ? event : nil
        }) {
            monitors.append(local)
        }

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            let option = NSEvent.modifierFlags.contains(.option)
            for state in [self?.mainState, self?.subState].compactMap({ $0 }) where state.optionDown != option {
                state.optionDown = option
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        modifierTimer = timer
    }
}

final class DockMenuPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DockMenuState: ObservableObject {
    @Published var hovered: UUID?
    @Published var optionDown = NSEvent.modifierFlags.contains(.option)
    @Published var openSubmenu: UUID?
    /// Row frames in window coordinates (top-left origin), used to place the submenu.
    var rowFrames: [UUID: CGRect] = [:]
}

// MARK: - Menu views

struct DockMenuView: View {
    let entries: [DockMenuEntry]
    /// Where the pointer meets the icon, from the left edge. Nil for a submenu, which has no pointer.
    let arrowX: CGFloat?
    @ObservedObject var state: DockMenuState
    let controller: DockMenuController

    static let verticalPadding: CGFloat = 6
    static let arrow = CGSize(width: 20, height: 10)

    var body: some View {
        let arrow = arrowX == nil ? CGSize.zero : Self.arrow
        let shape = CalloutShape(radius: 12, arrow: arrow, arrowX: arrowX)
        let showsMarks = entries.contains {
            if case .item(let item) = $0 { return item.checked || item.minimized }
            return false
        }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .separator:
                    Rectangle()
                        .fill(Color.primary.opacity(0.14))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                case .item(let item):
                    DockMenuRow(item: item, showsMarks: showsMarks, state: state, controller: controller)
                }
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .padding(.bottom, arrow.height)
        .fixedSize()
        .background(.regularMaterial, in: shape)
        .overlay(shape.stroke(Color.primary.opacity(0.16), lineWidth: 1))
    }
}

private struct DockMenuRow: View {
    let item: DockMenuItem
    let showsMarks: Bool
    @ObservedObject var state: DockMenuState
    let controller: DockMenuController

    var body: some View {
        let title = state.optionDown ? (item.alternate?.title ?? item.title) : item.title
        let highlighted = state.hovered == item.id || state.openSubmenu == item.id

        HStack(spacing: 8) {
            if showsMarks {
                Group {
                    if item.checked {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold))
                    } else if item.minimized {
                        Image(systemName: "diamond.fill").font(.system(size: 7))
                    }
                }
                .frame(width: 12)
            }
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            }
            Text(title)
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 340, alignment: .leading)
            Spacer(minLength: 20)
            if item.submenu != nil {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
        }
        .foregroundStyle(highlighted ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .frame(minWidth: 170, maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlighted ? Color(nsColor: .controlAccentColor) : Color.clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                    state.rowFrames[item.id] = frame
                }
            }
        )
        .background(
            HoverTracker { inside in
                if inside {
                    state.hovered = item.id
                    controller.hovered(item, in: state)
                } else if state.hovered == item.id {
                    state.hovered = nil
                }
            }
        )
        .onTapGesture { controller.select(item, in: state) }
    }
}

/// A rounded rectangle with an optional pointer on its bottom edge, as on the Dock's labels and menus.
struct CalloutShape: Shape {
    var radius: CGFloat
    var arrow: CGSize
    /// The pointer's x position from the left edge; nil centers it.
    var arrowX: CGFloat?

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - arrow.height)
        let r = min(radius, body.height / 2, body.width / 2)
        let half = arrow.width / 2
        let tipX = min(max(rect.minX + (arrowX ?? rect.width / 2), body.minX + r + half), body.maxX - r - half)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                    tangent2End: CGPoint(x: body.maxX, y: body.minY + r), radius: r)
        path.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                    tangent2End: CGPoint(x: body.maxX - r, y: body.maxY), radius: r)
        if arrow.height > 0 {
            path.addLine(to: CGPoint(x: tipX + half, y: body.maxY))
            path.addQuadCurve(to: CGPoint(x: tipX, y: rect.maxY),
                              control: CGPoint(x: tipX + half * 0.35, y: body.maxY + arrow.height * 0.55))
            path.addQuadCurve(to: CGPoint(x: tipX - half, y: body.maxY),
                              control: CGPoint(x: tipX - half * 0.35, y: body.maxY + arrow.height * 0.55))
        }
        path.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                    tangent2End: CGPoint(x: body.minX, y: body.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                    tangent2End: CGPoint(x: body.minX + r, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }
}

// MARK: - Recent documents

/// Reads an app's recent documents from the list macOS keeps for it (the same list the Dock shows).
/// macOS protects that folder, so this needs Full Disk Access; without it the list is empty.
enum RecentDocuments {
    private static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments")

    static var isAccessible: Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil
    }

    static func urls(bundleID: String, limit: Int = 10) -> [URL] {
        for name in Set([bundleID.lowercased(), bundleID]) {
            for ext in ["sfl3", "sfl2"] {
                let file = folder.appendingPathComponent("\(name).\(ext)")
                if let data = try? Data(contentsOf: file) {
                    return parse(data, limit: limit)
                }
            }
        }
        return []
    }

    private static func parse(_ data: Data, limit: Int) -> [URL] {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return [] }
        unarchiver.requiresSecureCoding = false
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        let root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [String: Any]
        unarchiver.finishDecoding()
        guard let items = root?["items"] as? [Any] else { return [] }

        var result: [URL] = []
        for case let item as [String: Any] in items {
            guard let bookmark = item["Bookmark"] as? Data else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                                     relativeTo: nil, bookmarkDataIsStale: &stale),
                  FileManager.default.fileExists(atPath: url.path) else { continue }
            result.append(url)
            if result.count == limit { break }
        }
        return result
    }
}

// MARK: - Windows (Accessibility)

struct AppWindow {
    let element: AXUIElement
    let title: String
    let minimized: Bool
    let isMain: Bool
}

/// Lists and raises another app's windows. macOS only allows this with Accessibility permission;
/// without it the list is empty and the menu simply has no window section.
enum AppWindows {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the macOS prompt that leads to Privacy & Security → Accessibility.
    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func list(pid: pid_t) -> [AppWindow] {
        guard AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return [] }
        var mainRef: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &mainRef)

        return windows.compactMap { window in
            let subrole = string(window, kAXSubroleAttribute)
            guard subrole == nil || subrole == kAXStandardWindowSubrole else { return nil }
            guard let title = string(window, kAXTitleAttribute), !title.isEmpty else { return nil }
            var minimizedRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef)
            let isMain = mainRef.map { CFEqual($0, window) } ?? false
            return AppWindow(element: window, title: title,
                             minimized: (minimizedRef as? Bool) ?? false, isMain: isMain)
        }
    }

    static func bringForward(_ window: AppWindow, pid: pid_t) {
        let element = window.element
        if window.minimized {
            AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString,
                                     kCFBooleanTrue)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }
}
