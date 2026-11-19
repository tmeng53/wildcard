#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// One of the compose page's tiles full screen, opened from its row: a photo as it will be
/// posted, zoomable; the map or the chart large on ink, a tall card across the screen (the post's
/// own wide shape left them a strip in the middle, feedback #70), the chart's heart rate scrubbed
/// by press-and-hold.
struct ComposeViewerPage: View {
    let model: ComposeModel
    let index: Int
    let isShowing: Bool

    var body: some View {
        if model.tiles.indices.contains(index) {
            switch model.tiles[index] {
            case .photo(let photo):
                let load = model.loadPhoto
                ViewerPhoto(isShowing: isShowing) {
                    switch photo {
                    case .new(let prepared): return prepared.jpeg
                    case .saved(let ref): return await load(ref)
                    }
                }
                .accessibilityLabel(Text(copy: "第 \(index + 1) 张", bundle: .module))
            case .workout(.map):
                if let route = model.workout?.route {
                    WorkoutMap(route: route, activity: model.currentActivity)
                        .aspectRatio(Self.cardAspect, contentMode: .fit)
                        .modifier(ViewerCard())
                        .accessibilityIdentifier("compose.viewer.map")
                }
            case .workout(.chart):
                if let series = model.workout?.series {
                    WorkoutChart(
                        series: series, activity: model.currentActivity, showsLabel: true,
                        startedAt: model.workout?.startedAt.date, shape: Self.cardAspect
                    )
                    .aspectRatio(Self.cardAspect, contentMode: .fit)
                    .modifier(ViewerCard())
                    .accessibilityIdentifier("compose.viewer.chart")
                }
            }
        }
    }

    /// The map's and chart's card: 3:4, as tall as a portrait photo shows here.
    private static let cardAspect = 3.0 / 4
}

/// The map or chart rounded as a card, across the screen with the page's margins.
private struct ViewerCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Its own element holding the chart's or map's, so the page's identifier lands here
            // whatever the face names itself.
            .accessibilityElement(children: .contain)
    }
}
#endif
