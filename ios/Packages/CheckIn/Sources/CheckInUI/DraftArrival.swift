#if os(iOS)
import DesignSystem
import DesignSystemUI
import SwiftUI

extension AnyTransition {
    /// A line on offer arriving after 编几句: rising as it fades in, `index` lines after the
    /// first (loader design A). While the writer works, the lines it will replace fade back to
    /// `Loading.waitingOpacity`.
    static func arrival(_ index: Int, reduceMotion: Bool) -> AnyTransition {
        let rise: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .offset(y: Loading.arrivalRise))
        return .asymmetric(
            insertion: rise.animation(.wildcard(Loading.arrival).delay(Double(index) * Loading.arrivalStagger)),
            removal: .opacity)
    }
}
#endif
