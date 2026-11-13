#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

extension View {
    /// The graphite dot on a header button's corner that says something new waits behind it (the
    /// bell on 动态, the gear on 小队 while someone asks to join), ringed in the page's white.
    public func newsDot(_ isShown: Bool) -> some View {
        overlay(alignment: .topTrailing) {
            if isShown {
                NewsDotMark()
                    .padding(NewsDotMetrics.ring)
                    .background(Circle().fill(Color(role: .bgCanvas, in: .gym)))
                    .offset(x: -NewsDotMetrics.dot / 2, y: NewsDotMetrics.dot / 2)
                    .transition(.opacity)
            }
        }
    }

    /// Whether the squad card's title wears the news dot after its name: the captain's squad has
    /// someone waiting to join. The app sets it over 今天.
    public func squadCardNews(_ isShown: Bool) -> some View {
        environment(\.squadCardNews, isShown)
    }
}

extension EnvironmentValues {
    @Entry var squadCardNews = false
}

/// The graphite news dot alone, for a place that sets it in line (after the squad card's name).
struct NewsDotMark: View {
    var body: some View {
        Circle()
            .fill(Color(role: .bgBrand, in: .gym))
            .frame(width: NewsDotMetrics.dot, height: NewsDotMetrics.dot)
            .accessibilityHidden(true)
    }
}

/// The dot, and the ring of the page's colour around it.
private enum NewsDotMetrics {
    static let dot: Double = 8
    static let ring: Double = 2
}
#endif
