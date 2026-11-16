import SwiftUI
import AppKit

final class PiPControlsState: ObservableObject {
    static let opacityRange: ClosedRange<Double> = 0.5...1

    @Published var isVisible = false
    @Published var opacity = 1.0
    @Published var hasCrop = false
}

struct PiPGripBar: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.55))
            .frame(width: 32, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: PiPInteraction.dragBarHeight)
            .accessibilityHidden(true)
    }
}

struct PiPCornerGrips: View {
    private static let length: CGFloat = 8
    private static let inset: CGFloat = 4

    var body: some View {
        ZStack {
            grip(.topLeading, flipX: false, flipY: false)
            grip(.topTrailing, flipX: true, flipY: false)
            grip(.bottomLeading, flipX: false, flipY: true)
            grip(.bottomTrailing, flipX: true, flipY: true)
        }
        .accessibilityHidden(true)
    }

    private func grip(_ alignment: Alignment, flipX: Bool, flipY: Bool) -> some View {
        PiPCornerGripShape()
            .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: Self.length, height: Self.length)
            .scaleEffect(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
            .padding(Self.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

struct PiPCornerGripShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

struct PiPControlsView: View {
    @ObservedObject var state: PiPControlsState
    let onClose: () -> Void
    let onShowWindow: () -> Void
    let onCrop: (PiPCropAction) -> Void
    let onSize: (PiPSizePreset) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                PiPGripBar()
                HStack(spacing: 8) {
                    iconButton("xmark", label: "Close", anchor: .leading, action: onClose)
                    Spacer(minLength: 4)
                    Slider(value: $state.opacity, in: PiPControlsState.opacityRange)
                        .controlSize(.mini)
                        .frame(minWidth: 24, idealWidth: 56, maxWidth: 56)
                        .hoverLabel("Opacity", anchor: .trailing)
                        .accessibilityLabel("Opacity")
                    sizeMenu
                    iconButton("crop", label: "Crop", anchor: .trailing) { onCrop(.begin) }
                    if state.hasCrop {
                        iconButton("arrow.counterclockwise", label: "Reset crop", anchor: .trailing) { onCrop(.reset) }
                    }
                    iconButton("arrow.up.forward.app", label: "Bring window back", anchor: .trailing, action: onShowWindow)
                }
                .padding(.horizontal, PiPInteraction.edgeWidth)
                .frame(height: PiPInteraction.controlsBarHeight)
            }
            .background(LinearGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0)],
                                       startPoint: .top, endPoint: .bottom))
            Spacer(minLength: 0)
        }
        .overlay { PiPCornerGrips() }
        .opacity(state.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: state.isVisible)
    }

    private var sizeMenu: some View {
        Menu {
            ForEach(PiPSizePreset.allCases) { preset in
                Button(preset.title) { onSize(preset) }
            }
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.white.opacity(0.85))
                .background(Color.black.opacity(0.35), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverLabel("Size", anchor: .trailing)
        .accessibilityLabel("Size")
    }

    private func iconButton(_ symbol: String, label: String, anchor: HorizontalAlignment,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.white.opacity(0.85))
                .background(Color.black.opacity(0.35), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .hoverLabel(label, anchor: anchor)
        .accessibilityLabel(label)
    }
}

final class PiPControlsHostingView: NSHostingView<PiPControlsView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let fromTop = isFlipped ? local.y : bounds.height - local.y
        return PiPInteraction.controlsRow.contains(fromTop) ? super.hitTest(point) : nil
    }
}
