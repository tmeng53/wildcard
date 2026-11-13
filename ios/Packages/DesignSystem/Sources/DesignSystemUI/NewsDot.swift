#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

extension View {
    /// The graphite dot on a header button's corner that says something new waits behind it (the
    /// bell on 动态, the gear on 小队 while someone asks to join), ringed in the page's white.
    public func newsDot(_ isShown: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if isShown {
                Circle()
                    .fill(Color(role: .bgBrand, in: .gym))
                    .frame(width: NewsDotMetrics.dot, height: NewsDotMetrics.dot)
                    .padding(NewsDotMetrics.ring)
                    .background(Circle().fill(Color(role: .bgCanvas, in: .gym)))
                    .offset(x: -NewsDotMetrics.dot / 2, y: NewsDotMetrics.dot / 2)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The dot, and the ring of the page's colour around it.
private enum NewsDotMetrics {
    static let dot: Double = 8
    static let ring: Double = 2
}
#endif
