import SwiftUI
import AppKit

enum WidgetKind: String {
    case nowPlaying, battery, clock
}

enum DockElement: Identifiable {
    case app(DockApp)
    case divider(Int)
    case widget(WidgetKind)
    case trash

    var id: String {
        switch self {
        case .app(let app): return "app:" + app.id
        case .divider(let index): return "divider:\(index)"
        case .widget(let kind): return "widget:" + kind.rawValue
        case .trash: return "trash"
        }
    }

    var magnifies: Bool {
        switch self {
        case .app, .trash: return true
        case .divider, .widget: return false
        }
    }
}

struct DockLayout {
    let iconSize: CGFloat

    var spacing: CGFloat { (iconSize * 0.1).rounded() }
    var padding: CGFloat { (iconSize * 0.16).rounded() }
    var barHeight: CGFloat { iconSize + padding * 2 }
    var cornerRadius: CGFloat { barHeight * 0.34 }

    static let bottomMargin: CGFloat = 6
    static let labelSpace: CGFloat = 40

    func baseWidth(_ element: DockElement) -> CGFloat {
        switch element {
        case .app, .trash: return iconSize
        case .divider: return 1
        case .widget(.nowPlaying): return iconSize * 3.6
        case .widget(.battery): return iconSize * 1.1
        case .widget(.clock): return iconSize * 1.6
        }
    }

    static func windowHeight(iconSize: CGFloat, maxScale: CGFloat) -> CGFloat {
        let layout = DockLayout(iconSize: iconSize)
        return ceil(iconSize * maxScale + layout.padding * 2 + bottomMargin + labelSpace)
    }
}

/// Per-frame magnification result.
struct DockGeometry {
    var scales: [String: CGFloat] = [:]
    var hoveredID: String?
    var offsetX: CGFloat = 0

    /// Distances are measured against the un-magnified layout so magnification can't feed back
    /// into itself. The bar is then shifted so the spot under the cursor stays under the cursor.
    static func compute(elements: [DockElement], layout: DockLayout, containerWidth: CGFloat,
                        mouseX: CGFloat?, magnify: Bool, maxScale: CGFloat) -> DockGeometry {
        var result = DockGeometry()
        guard let mouseX, !elements.isEmpty else { return result }

        let widths = elements.map(layout.baseWidth)
        let baseTotal = widths.reduce(0, +) + layout.spacing * CGFloat(elements.count - 1) + layout.padding * 2
        let baseLeft = (containerWidth - baseTotal) / 2
        let range = layout.iconSize * 3

        var x = baseLeft + layout.padding
        var best = CGFloat.infinity
        for (index, element) in elements.enumerated() {
            let center = x + widths[index] / 2
            x += widths[index] + layout.spacing
            guard element.magnifies else { continue }
            let distance = abs(mouseX - center)
            if distance < best, distance <= (widths[index] + layout.spacing) / 2 {
                best = distance
                result.hoveredID = element.id
            }
            if magnify {
                let t = min(distance / range, 1)
                result.scales[element.id] = 1 + (maxScale - 1) * (cos(t * .pi) + 1) / 2
            }
        }
        guard magnify else { return result }

        var segments: [(base: CGFloat, live: CGFloat)] = [(layout.padding, layout.padding)]
        for (index, element) in elements.enumerated() {
            if index > 0 { segments.append((layout.spacing, layout.spacing)) }
            segments.append((widths[index], widths[index] * (result.scales[element.id] ?? 1)))
        }
        segments.append((layout.padding, layout.padding))

        let liveTotal = segments.reduce(0) { $0 + $1.live }
        let u = min(max(mouseX - baseLeft, 0), baseTotal)
        var baseAcc: CGFloat = 0
        var liveAcc: CGFloat = 0
        var uLive = liveTotal
        for segment in segments {
            if u <= baseAcc + segment.base {
                uLive = liveAcc + (segment.base > 0 ? (u - baseAcc) * segment.live / segment.base : 0)
                break
            }
            baseAcc += segment.base
            liveAcc += segment.live
        }
        result.offsetX = (mouseX - uLive) - (containerWidth - liveTotal) / 2
        return result
    }
}

struct DockView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var settings: DockSettings
    @ObservedObject var state: DockState
    @ObservedObject var nowPlaying: NowPlayingMonitor
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        GeometryReader { proxy in
            let layout = DockLayout(iconSize: settings.iconSize)
            let elements = makeElements()
            let geometry = DockGeometry.compute(elements: elements, layout: layout,
                                                containerWidth: proxy.size.width, mouseX: state.mouseX,
                                                magnify: settings.magnification, maxScale: settings.maxScale)

            HStack(alignment: .bottom, spacing: layout.spacing) {
                ForEach(elements) { element in
                    elementView(element, layout: layout,
                                scale: geometry.scales[element.id] ?? 1,
                                showLabel: geometry.hoveredID == element.id && !state.menuOpen)
                }
            }
            .padding(layout.padding)
            .background(alignment: .bottom) {
                GlassBar(cornerRadius: layout.cornerRadius)
                    .frame(height: layout.barHeight)
                    .background(
                        GeometryReader { bar in
                            Color.clear.onChange(of: bar.frame(in: .global), initial: true) { _, frame in
                                state.barFrame = frame
                            }
                        }
                    )
            }
            .offset(x: geometry.offsetX,
                    y: state.revealed ? 0 : layout.barHeight + DockLayout.bottomMargin + 8)
            .padding(.bottom, DockLayout.bottomMargin)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.86), value: state.mouseX)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: state.revealed)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: elements.map(\.id))
        }
    }

    private func makeElements() -> [DockElement] {
        let pinned = model.apps.filter(\.isPinned)
        let others = model.apps.filter { !$0.isPinned }
        var result = pinned.map(DockElement.app)
        if !others.isEmpty {
            result.append(.divider(0))
            result += others.map(DockElement.app)
        }

        var widgets: [WidgetKind] = []
        if settings.showNowPlaying { widgets.append(.nowPlaying) }
        if settings.showBattery, battery.level != nil { widgets.append(.battery) }
        if settings.showClock { widgets.append(.clock) }
        if !widgets.isEmpty {
            result.append(.divider(1))
            result += widgets.map(DockElement.widget)
        }

        result.append(.divider(2))
        result.append(.trash)
        return result
    }

    @ViewBuilder
    private func elementView(_ element: DockElement, layout: DockLayout, scale: CGFloat, showLabel: Bool) -> some View {
        switch element {
        case .app(let app):
            AppIconView(app: app, size: layout.iconSize * scale,
                        dotOffset: layout.padding / 2 + 2, showLabel: showLabel,
                        showIndicator: settings.showIndicators, animateOpening: settings.animateOpening,
                        model: model, onMenu: setMenuOpen)
        case .trash:
            TrashIconView(size: layout.iconSize * scale, showLabel: showLabel, model: model,
                          onMenu: setMenuOpen)
        case .divider:
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 1, height: layout.iconSize * 0.7)
                .padding(.bottom, layout.iconSize * 0.15)
        case .widget(let kind):
            widget(kind, size: layout.iconSize)
                .frame(width: layout.baseWidth(element), height: layout.iconSize)
                .background(
                    RoundedRectangle(cornerRadius: layout.iconSize * 0.24, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
        }
    }

    private func setMenuOpen(_ open: Bool) {
        state.menuOpen = open
    }

    @ViewBuilder
    private func widget(_ kind: WidgetKind, size: CGFloat) -> some View {
        switch kind {
        case .nowPlaying: NowPlayingWidget(nowPlaying: nowPlaying, size: size)
        case .battery: BatteryWidget(battery: battery, size: size)
        case .clock: ClockWidget(size: size)
        }
    }
}

struct GlassBar: View {
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            shape.fill(Color.clear).glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        }
    }
}

struct DockLabel: ViewModifier {
    let text: String
    let visible: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if visible {
                let bubble = CalloutShape(radius: 7, arrow: CGSize(width: 14, height: 7), arrowX: nil)
                Text(text)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 11)
                    .padding(.top, 4)
                    .padding(.bottom, 4 + bubble.arrow.height)
                    .background(.regularMaterial, in: bubble)
                    .overlay(bubble.stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .offset(y: -36)
                    .allowsHitTesting(false)
            }
        }
    }
}

struct AppIconView: View {
    let app: DockApp
    let size: CGFloat
    let dotOffset: CGFloat
    let showLabel: Bool
    let showIndicator: Bool
    let animateOpening: Bool
    let model: DockModel
    let onMenu: (Bool) -> Void

    @State private var pressed = false
    @State private var launching = false
    @State private var bounceUp = false

    var body: some View {
        Image(nsImage: app.icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .brightness(pressed ? -0.3 : 0)
            .offset(y: bounceUp ? -size * 0.4 : 0)
            .overlay(alignment: .bottom) {
                if (app.isRunning || launching) && showIndicator {
                    Circle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(width: 4, height: 4)
                        .offset(y: dotOffset)
                }
            }
            .modifier(DockLabel(text: app.name, visible: showLabel))
            .overlay(
                DockItemMouse(onPress: { pressed = $0 },
                              onClick: click,
                              makeMenu: { model.menuEntries(for: app, open: launch) },
                              onMenu: onMenu)
            )
            .onChange(of: app.isRunning) { _, running in
                if running { launching = false }
            }
    }

    /// Click, Option-click (hide the others) and Command-click (show in Finder), as in the macOS Dock.
    private func click(_ modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            model.reveal(app)
        } else if modifiers.contains(.option) {
            if !app.isRunning { startBouncing() }
            model.openHidingOthers(app)
        } else {
            launch()
        }
    }

    private func launch() {
        if !app.isRunning { startBouncing() }
        model.open(app, failed: { launching = false })
    }

    /// Bounces until the app finishes launching (or 20 seconds pass), like the macOS Dock.
    private func startBouncing() {
        guard animateOpening, !launching else { return }
        launching = true
        bounce(remaining: 28)
    }

    private func bounce(remaining: Int) {
        guard launching, remaining > 0 else {
            launching = false
            return
        }
        withAnimation(.easeOut(duration: 0.28)) { bounceUp = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.easeIn(duration: 0.28)) { bounceUp = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                bounce(remaining: remaining - 1)
            }
        }
    }
}

struct TrashIconView: View {
    let size: CGFloat
    let showLabel: Bool
    let model: DockModel
    let onMenu: (Bool) -> Void

    @State private var pressed = false

    private static let icon: NSImage = {
        let image = NSImage(named: NSImage.trashEmptyName)
            ?? NSWorkspace.shared.icon(forFile: NSHomeDirectory() + "/.Trash")
        image.size = NSSize(width: 256, height: 256)
        return image
    }()

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .brightness(pressed ? -0.3 : 0)
            .modifier(DockLabel(text: "Trash", visible: showLabel))
            .overlay(
                DockItemMouse(onPress: { pressed = $0 },
                              onClick: { _ in model.openTrash() },
                              makeMenu: { model.trashMenuEntries() },
                              onMenu: onMenu)
            )
    }
}
