#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// Where a 训练 or a meal was, under its author on 动态 (Tracy, 2026-11-12): the place's kind's
/// icon and its name. A tap opens its page (地点页, Tracy, 2026-11-13) when the caller gives one,
/// else Apple Maps.
public struct PlaceTag: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.openURL) private var openURL
    private let place: Place
    private let open: (() -> Void)?

    public init(_ place: Place, open: (() -> Void)? = nil) {
        self.place = place
        self.open = open
    }

    public var body: some View {
        Button {
            if let open {
                open()
            } else if let mapsLink = place.mapsLink {
                openURL(mapsLink)
            }
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
        // Its page says what it is; only a tap that leaves the app says where it goes.
        .accessibilityHint(open == nil ? Text(copy: "在地图中打开", bundle: .module) : Text(verbatim: ""))
        .accessibilityIdentifier("post.place")
    }
}

extension Place {
    /// Apple Maps' link to the place: by Maps' own id when it has one, so Maps shows its card
    /// (its stars and photos are there); else its name at its spot.
    public var mapsLink: URL? {
        var parts = URLComponents(string: "https://maps.apple.com/place")
        parts?.queryItems =
            if let id = appleID {
                [URLQueryItem(name: "place-id", value: id)]
            } else {
                [
                    URLQueryItem(name: "name", value: name),
                    URLQueryItem(name: "coordinate", value: "\(latitude),\(longitude)"),
                ]
            }
        return parts?.url
    }
}
#endif
