import SwiftUI

#if os(iOS)
import UIKit

/// Wraps SwiftUI content in a real `UIScrollView` so pinch-to-zoom and panning
/// are the system's own, battle-tested implementation rather than hand-rolled
/// gesture math.
///
/// The scroll view's pan gesture is restricted to two fingers on purpose: a
/// single finger, and the Apple Pencil, stay completely free for drawing,
/// moving, and resizing boxes in the content underneath. Pinching to zoom
/// already needs two fingers, so nothing here competes with the drawing
/// surface — the two systems simply watch for a different number of touches.
struct ZoomableContainer<Content: View>: UIViewRepresentable {
    var minimumZoom: CGFloat = 1
    var maximumZoom: CGFloat = 8
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(hostingController: UIHostingController(rootView: content()))
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = minimumZoom
        scrollView.maximumZoomScale = maximumZoom
        // Clamp at the fit-to-screen size instead of rubber-banding past it;
        // that transient state has no well-defined "centered" frame to spring
        // back to here, so it is simplest to not let it occur at all.
        scrollView.bouncesZoom = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2

        let hosted = context.coordinator.hostingController.view!
        hosted.backgroundColor = .clear
        scrollView.addSubview(hosted)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content()

        let hosted = context.coordinator.hostingController.view!
        if hosted.frame.size != scrollView.bounds.size {
            hosted.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
            scrollView.contentSize = scrollView.bounds.size
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let hostingController: UIHostingController<Content>

        init(hostingController: UIHostingController<Content>) {
            self.hostingController = hostingController
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }
    }
}
#else
/// No trackpad pinch support wired up on macOS yet; show the content as-is.
struct ZoomableContainer<Content: View>: View {
    var minimumZoom: CGFloat = 1
    var maximumZoom: CGFloat = 8
    @ViewBuilder var content: () -> Content

    var body: some View { content() }
}
#endif
