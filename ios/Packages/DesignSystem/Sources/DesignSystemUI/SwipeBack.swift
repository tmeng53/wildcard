#if os(iOS)
import DesignSystem
import SwiftUI
import UIKit

extension View {
    /// A sign-up step, which has no navigation bar, also goes back to the step before on a swipe
    /// right from anywhere on it: the step follows the finger and goes back once it is past a
    /// third of the way across or flung, leaving from where the finger let go, else it springs
    /// back. Only a rightward, mostly horizontal drag starts it; a vertical scroll scrolls as
    /// before, and a sideways list that can still scroll back takes the drag first. Every other
    /// page that opens over another is pushed on a NavigationStack (`pushedPage`), whose swipe is
    /// the system's.
    public func swipesBack(isEnabled: Bool = true, perform back: @escaping () -> Void) -> some View {
        modifier(SwipeBack(isEnabled: isEnabled, back: back))
    }
}

private struct SwipeBack: ViewModifier {
    let isEnabled: Bool
    let back: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the page has followed the finger.
    @State private var offset = 0.0

    /// Past this share of the page's width, letting go goes back.
    private static let distance = 1.0 / 3
    /// A flick at this speed, in points a second, goes back from anywhere.
    private static let fling = 800.0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .gesture(
                SwipeBackPan(isEnabled: isEnabled) { moved in
                    offset = moved
                } ended: { moved, speed, width in
                    let goes = moved > width * Self.distance || (speed > Self.fling && moved > 0)
                    let settle = Animation.wildcard(Motion.page, reduceMotion: reduceMotion)
                    guard goes else {
                        withAnimation(settle) { offset = 0 }
                        return
                    }
                    // A step that goes leaves on its own transition from where the finger let go;
                    // snapping it back to 0 in the same change would jerk it left before it slides
                    // out. One that stays (sign-up busy saving) springs back a moment later.
                    withAnimation(settle) { back() }
                    Task { @MainActor in withAnimation(settle) { offset = 0 } }
                })
    }
}

/// The pan behind `swipesBack`: UIKit's, so it can start only on a rightward drag and yield to a
/// sideways list.
private struct SwipeBackPan: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let changed: (Double) -> Void
    let ended: (_ moved: Double, _ speed: Double, _ width: Double) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let moved = Double(max(recognizer.translation(in: recognizer.view).x, 0))
        let width = Double(recognizer.view?.bounds.width ?? 0)
        switch recognizer.state {
        case .changed:
            changed(moved)
        case .ended:
            ended(moved, Double(recognizer.velocity(in: recognizer.view).x), width)
        case .cancelled, .failed:
            // Interrupted (a call, the system taking the touch): the page springs back.
            ended(0, 0, width)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return velocity.x > 0 && abs(velocity.x) > abs(velocity.y)
        }

        /// A list that scrolls only up and down keeps scrolling alongside.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            guard let scroll = Self.scrollView(panning: other) else { return false }
            return scroll.contentSize.width <= scroll.bounds.width
        }

        /// A sideways list that can still scroll back scrolls first.
        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer, shouldRequireFailureOf other: UIGestureRecognizer
        ) -> Bool {
            guard let scroll = Self.scrollView(panning: other) else { return false }
            return scroll.contentOffset.x > -scroll.adjustedContentInset.left
        }

        private static func scrollView(panning recognizer: UIGestureRecognizer) -> UIScrollView? {
            guard let scroll = recognizer.view as? UIScrollView, recognizer === scroll.panGestureRecognizer
            else { return nil }
            return scroll
        }
    }
}
#endif
