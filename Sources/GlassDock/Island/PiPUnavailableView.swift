import SwiftUI
import AppKit

final class PiPSourceModel: ObservableObject {
    @Published var reason: PiPSourceState.Reason?
}

struct PiPUnavailableView: View {
    private static let dimOpacity = 0.55

    @ObservedObject var model: PiPSourceModel
    let onShowWindow: () -> Void

    var body: some View {
        ZStack {
            if let reason = model.reason {
                Color.black.opacity(Self.dimOpacity)
                Button(action: onShowWindow) {
                    VStack(spacing: 2) {
                        Label(reason.title, systemImage: reason.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("Show window")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(reason.title). Show window")
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.reason)
    }
}

final class PiPUnavailableHostingView: NSHostingView<PiPUnavailableView> {
    private let model: PiPSourceModel

    init(model: PiPSourceModel, onShowWindow: @escaping () -> Void) {
        self.model = model
        super.init(rootView: PiPUnavailableView(model: model, onShowWindow: onShowWindow))
    }

    @available(*, unavailable)
    required init(rootView: PiPUnavailableView) { fatalError() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        model.reason == nil ? nil : super.hitTest(point)
    }
}
