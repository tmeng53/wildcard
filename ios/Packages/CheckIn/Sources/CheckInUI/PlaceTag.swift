#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import MapKit
import SwiftUI

/// Where a 训练 or a meal was, under its author on 动态 (Tracy, 2026-11-12): the place's kind's
/// icon and its name. A tap opens it in Apple Maps, by Maps' own id when the place has one.
public struct PlaceTag: View {
    @Environment(\.sceneTheme) private var theme
    private let place: Place

    public init(_ place: Place) {
        self.place = place
    }

    public var body: some View {
        Button {
            Task { await open() }
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

    private func open() async {
        let location = CLLocation(latitude: place.latitude, longitude: place.longitude)
        var item: MKMapItem?
        if let raw = place.appleID, let id = MKMapItem.Identifier(rawValue: raw) {
            item = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem
        }
        let shown = item ?? MKMapItem(location: location, address: nil)
        if item == nil { shown.name = place.name }
        shown.openInMaps()
    }
}
#endif
