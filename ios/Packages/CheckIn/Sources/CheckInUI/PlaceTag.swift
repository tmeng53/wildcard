#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// Where a 训练 or a meal was, under its author on 动态 (Tracy, 2026-11-12): the place's kind's
/// icon and its name. A tap opens it in Apple Maps.
public struct PlaceTag: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.openURL) private var openURL
    private let place: Place

    public init(_ place: Place) {
        self.place = place
    }

    public var body: some View {
        Button {
            if let mapsLink { openURL(mapsLink) }
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
        .accessibilityHint(Text(copy: "在地图中打开", bundle: .module))
        .accessibilityIdentifier("post.place")
    }

    /// Apple Maps' link to the place: by Maps' own id when it has one, so Maps shows its card;
    /// else its name at its spot.
    var mapsLink: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/place")
        parts?.queryItems =
            if let id = place.appleID {
                [URLQueryItem(name: "place-id", value: id)]
            } else {
                [
                    URLQueryItem(name: "name", value: place.name),
                    URLQueryItem(name: "coordinate", value: "\(place.latitude),\(place.longitude)"),
                ]
            }
        return parts?.url
    }
}
#endif
