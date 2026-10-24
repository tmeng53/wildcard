#if os(iOS)
import SwiftUI
import UIKit

extension View {
    /// A tap anywhere outside a text field or text view puts the keyboard away, on every screen
    /// in this view's window. The app's root applies it once. The tap still reaches what was
    /// tapped, so a button pressed while typing both closes the keyboard and does its job, and a
    /// tap on another field moves the typing there.
    public func dismissesKeyboardOnTapOutside() -> some View {
        background(WindowTap())
    }
}

/// Finds the window it is drawn in and adds the tap to it, once per window.
private struct WindowTap: UIViewRepresentable {
    func makeUIView(context: Context) -> Finder { Finder() }
    func updateUIView(_ uiView: Finder, context: Context) {}

    final class Finder: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window { TapOutside.shared.install(in: window) }
        }
    }
}

/// The window's tap: the target and delegate of a recognizer that never cancels or delays the
/// touches it watches. A recognizer holds its target and delegate weakly, so this one lives as
/// long as the app.
@MainActor
private final class TapOutside: NSObject, UIGestureRecognizerDelegate {
    static let shared = TapOutside()

    func install(in window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === self }) else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        tap.view?.endEditing(true)
    }

    /// Not for a touch in a text input (SwiftUI's fields are UIKit's underneath), which keeps
    /// the keyboard for it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let each = view {
            if each is UITextField || each is UITextView { return false }
            view = each.superview
        }
        return true
    }

    /// Alongside every other gesture, so scrolls, buttons and drags work as before.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif
