#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// Where a 训练 or a meal was, under its author on 动态 (Tracy, 2026-11-12): the place's kind's
/// icon and its name. A tap opens the place's own page (地点页), every place's one way in; Apple
/// Maps opens only from there.
public struct PlaceTag: View {
    @Environment(\.sceneTheme) private var theme
    private let place: Place
    private let open: (Place) -> Void

    public init(_ place: Place, open: @escaping (Place) -> Void) {
        (self.place, self.open) = (place, open)
    }

    public var body: some View {
        Button {
            open(place)
        } label: {
            HStack(spacing: Space.xxs) {
                Image(systemName: place.kind.symbol)
                    .font(.system(size: Sizing.smallIcon - 3, weight: .semibold))
                    .accessibilityHidden(true)
                Text(verbatim: place.name)
                    .typeStyle(TypeRamp.footnote)
                    .lineLimit(1)
            }
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .frame(minHeight: Sizing.smallTag)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("post.place")
    }
}
#endif
