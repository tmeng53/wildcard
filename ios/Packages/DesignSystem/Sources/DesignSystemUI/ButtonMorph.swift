#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A panel growing out of the round button that opened it, and folding back into it as it closes
/// (the approved motion mockup, 2026-11-24): it starts as a capsule the button's size on the
/// button, and stretches to its own size and place as it moves, so one piece of glass reads as
/// turning into the next rather than a second one appearing. The panel animates with whatever
/// animation shows or hides it.
public struct ButtonMorph: Transition {
    /// From the panel's centre to the button's.
    private let shift: CGSize
    /// The button's size.
    private let button: CGSize

    /// - Parameters:
    ///   - button: the button's frame, in the space `panel` is in.
    ///   - panel: the panel's frame where it opens.
    public init(from button: CGRect, to panel: CGRect) {
        shift = CGSize(width: button.midX - panel.midX, height: button.midY - panel.midY)
        self.button = button.size
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        let open = phase.isIdentity
        content
            .mask {
                // Open, the mask reaches past the panel so its shadow shows.
                Capsule(style: .continuous)
                    .frame(width: open ? nil : button.width, height: open ? nil : button.height)
                    .padding(open ? -Self.shadowRoom : 0)
            }
            .offset(open ? .zero : shift)
            .opacity(open ? 1 : Self.closedOpacity)
    }

    /// How far the panel's shadow reaches past it.
    private static let shadowRoom = Space.xl
    /// The capsule fades a little as it folds into the button, which shows under it.
    private static let closedOpacity = 0.4
}
#endif
