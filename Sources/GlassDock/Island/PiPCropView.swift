import SwiftUI
import AppKit

final class PiPCropModel: ObservableObject {
    private static let handleTolerance: CGFloat = 8

    private struct Drag {
        let handle: PiPCropHandle?
        let start: CGPoint
        let base: CGRect
    }

    @Published var selection: CGRect?
    private var windowSize = CGSize.zero
    private var drag: Drag?
    private let onDone: (PiPCrop) -> Void
    private let onCancel: () -> Void

    init(onDone: @escaping (PiPCrop) -> Void, onCancel: @escaping () -> Void) {
        self.onDone = onDone
        self.onCancel = onCancel
    }

    func begin(selection: CGRect?, windowSize: CGSize) {
        self.selection = selection
        self.windowSize = windowSize
        drag = nil
    }

    func confirm() {
        guard let selection, let crop = PiPCrop(selection: selection, in: CGSize(width: 1, height: 1), windowSize: windowSize)
        else { return }
        onDone(crop)
    }

    func cancel() {
        onCancel()
    }

    func dragChanged(from start: CGPoint, to location: CGPoint, in size: CGSize) {
        if drag == nil {
            let base = selection.map { Self.viewRect($0, in: size) }
            drag = Drag(handle: base.flatMap { PiPCropHandle.handle(at: start, in: $0, tolerance: Self.handleTolerance) },
                        start: start, base: base ?? .zero)
        }
        guard let drag else { return }
        let minimum = PiPCrop.minimumSize(in: size, windowSize: windowSize)
        let moved = drag.handle?.dragged(drag.base, by: CGSize(width: location.x - drag.start.x, height: location.y - drag.start.y),
                                         within: size, minimumSize: minimum)
            ?? PiPCrop.drawnRect(from: drag.start, to: location, within: size, minimumSize: minimum)
        selection = CGRect(x: moved.minX / size.width, y: moved.minY / size.height,
                           width: moved.width / size.width, height: moved.height / size.height)
    }

    func dragEnded() {
        drag = nil
    }

    static func viewRect(_ selection: CGRect, in size: CGSize) -> CGRect {
        CGRect(x: selection.minX * size.width, y: selection.minY * size.height,
               width: selection.width * size.width, height: selection.height * size.height)
    }
}

struct PiPCropView: View {
    private static let dimOpacity = 0.55
    private static let handleSize: CGFloat = 8
    private static let buttonSpacing: CGFloat = 8

    @ObservedObject var model: PiPCropModel

    var body: some View {
        GeometryReader { proxy in
            let rect = model.selection.map { PiPCropModel.viewRect($0, in: proxy.size) }
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    if let rect { path.addRect(rect) }
                }
                .fill(Color.black.opacity(Self.dimOpacity), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { model.dragChanged(from: $0.startLocation, to: $0.location, in: proxy.size) }
                        .onEnded { _ in model.dragEnded() })
                if let rect {
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                    ForEach(PiPCropHandle.resizeHandles, id: \.self) { handle in
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: Self.handleSize, height: Self.handleSize)
                            .position(handle.anchor(in: rect))
                            .allowsHitTesting(false)
                    }
                } else {
                    Text("Drag to choose an area")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .allowsHitTesting(false)
                }
                PiPGripBar()
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                HStack(spacing: Self.buttonSpacing) {
                    cropButton("Cancel", fill: Color.white.opacity(0.18), action: model.cancel)
                    cropButton("Done", fill: Color.accentColor, action: model.confirm)
                        .disabled(model.selection == nil)
                }
                .padding(.bottom, Self.buttonSpacing)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func cropButton(_ title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(fill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

final class PiPCropHostingView: NSHostingView<PiPCropView> {
    override var needsPanelToBecomeKey: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
