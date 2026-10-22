#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// A thin bar filled in ink on a subtle track. It never turns red and stops at full.
public struct ProgressBar: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let fraction: Double

    /// `fraction` is clamped to 0...1.
    public init(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
    }

    public var body: some View {
        Capsule()
            .fill(Color(role: .bgSubtle, in: theme))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(role: .fgDefault, in: theme))
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: Sizing.progress)
            .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: fraction)
            .accessibilityHidden(true)
    }
}
#endif
