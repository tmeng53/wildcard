#if canImport(SwiftUI)
import DesignSystem
import SwiftUI

/// Which page of a few is showing, as dots over a picture: the current one a stretched capsule
/// that flows to the next as the page turns, one shrinking while the other grows (the approved
/// motion mockup, 2026-11-24), in place of the system's page dots. Takes no taps.
public struct PageDots: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let count: Int
    private let page: Int

    public init(count: Int, page: Int) {
        self.count = count
        self.page = page
    }

    public var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(Color(role: .fgOnInk, in: theme).opacity(index == page ? 1 : Self.restOpacity))
                    .frame(width: index == page ? Self.currentWidth : Self.size, height: Self.size)
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: page)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A dot's diameter, and the gap between dots.
    private static let size = 6.0
    private static let gap = 6.0
    /// The current page's capsule, three dots wide.
    private static let currentWidth = 18.0
    private static let restOpacity = 0.5
}
#endif
