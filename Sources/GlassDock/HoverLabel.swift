import SwiftUI
import AppKit

extension View {
    /// Shows a small name label after the pointer rests on the view for a moment.
    ///
    /// Use this instead of `.help(_:)` in GlassDock's panels: macOS only shows standard tooltips in
    /// the active app, and GlassDock never becomes active.
    func hoverLabel(_ text: String, edge: VerticalEdge = .bottom, anchor: HorizontalAlignment = .center) -> some View {
        modifier(HoverLabelModifier(text: text, edge: edge, anchor: anchor))
    }
}

/// The label for a playback button's SF Symbol.
func playbackControlName(_ symbol: String) -> String {
    if symbol.hasPrefix("backward") { return "Previous" }
    if symbol.hasPrefix("forward") { return "Next" }
    if symbol.hasPrefix("pause") { return "Pause" }
    return "Play"
}

private struct HoverLabelModifier: ViewModifier {
    let text: String
    let edge: VerticalEdge
    let anchor: HorizontalAlignment

    @State private var hovering = false
    @State private var visible = false

    private var alignment: Alignment {
        switch (edge, anchor) {
        case (.top, .leading): return .topLeading
        case (.top, .trailing): return .topTrailing
        case (.top, _): return .top
        case (.bottom, .leading): return .bottomLeading
        case (.bottom, .trailing): return .bottomTrailing
        case (.bottom, _): return .bottom
        }
    }

    func body(content: Content) -> some View {
        content
            .background(
                HoverTracker { inside in
                    hovering = inside
                    if inside {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            if hovering { withAnimation(.easeOut(duration: 0.12)) { visible = true } }
                        }
                    } else {
                        withAnimation(.easeOut(duration: 0.1)) { visible = false }
                    }
                }
            )
            .overlay(alignment: alignment) {
                if visible {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(white: 0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                        .offset(y: edge == .top ? -30 : 30)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .zIndex(visible ? 10 : 0)
    }
}

/// Reports the pointer entering and leaving, even though GlassDock's windows are never active.
struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var inside = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
            // The pointer may already be here (for example when a tab opens under it).
            if let window {
                let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                setInside(bounds.contains(point))
            }
        }

        override func mouseEntered(with event: NSEvent) { setInside(true) }
        override func mouseExited(with event: NSEvent) { setInside(false) }

        // Catches the case where "entered" was missed because the panel was ignoring the mouse
        // at that moment (the island only accepts mouse events while the pointer is over it).
        override func mouseMoved(with event: NSEvent) {
            setInside(bounds.contains(convert(event.locationInWindow, from: nil)))
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { setInside(false) }
        }

        private func setInside(_ value: Bool) {
            guard value != inside else { return }
            inside = value
            onChange?(value)
        }

        // Never take clicks away from the button underneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
