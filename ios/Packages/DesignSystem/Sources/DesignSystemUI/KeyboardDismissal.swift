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

    /// A tap here keeps the keyboard: for controls beside a field that add to what is being typed
    /// (the @ list, 「@毛头」, 回复's ×). Without it the tap would put the keyboard away
    /// (`dismissesKeyboardOnTapOutside`) while the control puts words in the field. Only for
    /// controls nothing is drawn over, since the tap is judged by where it landed when it began.
    /// `outset` widens the area past the frame, for a control tapped beyond it (a content shape).
    public func keepsKeyboard(outset: CGFloat = 0) -> some View {
        background(KeepsKeyboard().padding(-outset))
    }
}

/// Marks the area of a view a tap keeps the keyboard in; it takes no touches itself.
private struct KeepsKeyboard: UIViewRepresentable {
    func makeUIView(context: Context) -> Mark {
        let mark = Mark()
        mark.isUserInteractionEnabled = false
        return mark
    }

    func updateUIView(_ uiView: Mark, context: Context) {}

    final class Mark: UIView {}
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

    /// The text input that had the keyboard when the touch began.
    private weak var typing: UIView?

    func install(in window: UIWindow) {
        guard !(window.gestureRecognizers ?? []).contains(where: { $0.delegate === self }) else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delaysTouchesEnded = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
    }

    /// Waits for whatever else the tap does, then puts the keyboard away only if the same input
    /// still has it and the tap was clear of that input's padding. A tap that moved the typing
    /// to another field (a field's padding, or a button that opens one) keeps the keyboard.
    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        guard let window = tap.view as? UIWindow else { return }
        guard !kept else { return }
        tapAt = (window, tap.location(in: window), typing)
        perform(#selector(finishTap), with: nil, afterDelay: 0)
    }

    /// The tap waiting for the next turn of the run loop: its window, where it landed, and the
    /// input that had the keyboard when it began.
    private var tapAt: (window: UIWindow, point: CGPoint, typing: UIView?)?

    /// Whether the touch began on a `keepsKeyboard()` control: judged then, since the control
    /// may be gone once the tap is done (回复's × takes its own row away).
    private var kept = false

    @objc private func finishTap() {
        guard let (window, point, before) = tapAt else { return }
        tapAt = nil
        guard let now = Self.typing(in: window), now === before else { return }
        let field = now.convert(now.bounds, to: window).insetBy(dx: -Self.padding, dy: -Self.padding)
        guard !field.contains(point) else { return }
        window.endEditing(true)
    }

    /// Covers the padding the app's fields (`InputField`, `SearchField`) put around their text,
    /// which focuses the field when tapped.
    private static let padding: CGFloat = 24

    /// Whether `point` is on a view marked `keepsKeyboard()`.
    private static func keepsKeyboard(at point: CGPoint, in view: UIView) -> Bool {
        guard !view.isHidden, view.alpha > 0 else { return false }
        if view is KeepsKeyboard.Mark, let window = view.window,
            view.convert(view.bounds, to: window).contains(point)
        {
            return true
        }
        return view.subviews.contains { keepsKeyboard(at: point, in: $0) }
    }

    private static func typing(in view: UIView) -> UIView? {
        if view.isFirstResponder, view is UITextField || view is UITextView { return view }
        for each in view.subviews {
            if let found = typing(in: each) { return found }
        }
        return nil
    }

    /// Only while something is being typed, and not for a touch in a text input (SwiftUI's fields
    /// are UIKit's underneath), which keeps the keyboard for it, nor in an alert, whose own
    /// buttons put its field's keyboard away.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window = gestureRecognizer.view, let typing = Self.typing(in: window) else { return false }
        var view = touch.view
        while let each = view {
            if each is UITextField || each is UITextView || each.next is UIAlertController { return false }
            view = each.superview
        }
        self.typing = typing
        kept = Self.keepsKeyboard(at: touch.location(in: window), in: window)
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
