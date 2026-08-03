import SwiftUI

/// A transparent layer that reports one continuous drag at a time.
///
/// On iPad it reads raw touches so it can look at `UITouch.type`. That is the
/// only reliable way to ignore the palm resting on the glass while you draw
/// with the Pencil: a SwiftUI DragGesture cannot tell the two apart.
struct DrawingSurface: View {
    var pencilOnly: Bool
    var onBegan: (CGPoint) -> Void
    var onMoved: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onCancelled: () -> Void

    var body: some View {
        #if os(iOS)
        TouchRepresentable(pencilOnly: pencilOnly,
                           onBegan: onBegan,
                           onMoved: onMoved,
                           onEnded: onEnded,
                           onCancelled: onCancelled)
        #else
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if value.translation == .zero {
                            onBegan(value.startLocation)
                        } else {
                            onMoved(value.location)
                        }
                    }
                    .onEnded { value in onEnded(value.location) }
            )
        #endif
    }
}

#if os(iOS)
import UIKit

private struct TouchRepresentable: UIViewRepresentable {
    var pencilOnly: Bool
    var onBegan: (CGPoint) -> Void
    var onMoved: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onCancelled: () -> Void

    func makeUIView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        return view
    }

    func updateUIView(_ view: TouchCaptureView, context: Context) {
        view.pencilOnly = pencilOnly
        view.onBegan = onBegan
        view.onMoved = onMoved
        view.onEnded = onEnded
        view.onCancelled = onCancelled
    }
}

final class TouchCaptureView: UIView {
    var pencilOnly = true
    var onBegan: ((CGPoint) -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onEnded: ((CGPoint) -> Void)?
    var onCancelled: (() -> Void)?

    private var activeTouch: UITouch?

    private func accepts(_ touch: UITouch) -> Bool {
        pencilOnly ? touch.type == .pencil : (touch.type == .pencil || touch.type == .direct)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first(where: accepts) else { return }
        activeTouch = touch
        onBegan?(touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        onMoved?(active.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        onEnded?(active.location(in: self))
        activeTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeTouch, touches.contains(active) else { return }
        onCancelled?()
        activeTouch = nil
    }
}
#endif
