#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// One of the compose page's tiles full screen, opened from its row: a photo as it will be
/// posted, zoomable; the map or the chart large on ink, in the shapes 动态 gives them, the chart's
/// heart rate scrubbed by press-and-hold.
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
                        .aspectRatio(Self.mapAspect, contentMode: .fit)
                        .modifier(ViewerCard())
                        .accessibilityIdentifier("compose.viewer.map")
                }
            case .workout(.chart):
                if let series = model.workout?.series {
                    WorkoutChart(
                        series: series, activity: model.currentActivity, showsLabel: true,
                        startedAt: model.workout?.startedAt.date, shape: Self.chartAspect
                    )
                    .aspectRatio(Self.chartAspect, contentMode: .fit)
                    .modifier(ViewerCard())
                    .accessibilityIdentifier("compose.viewer.chart")
                }
            }
        }
    }

    /// The post's own shapes on 动态: a 358 × 230 map and a 358 × 180 chart.
    private static let mapAspect = 358.0 / 230
    private static let chartAspect = 358.0 / 180
}

/// The map or chart rounded as a card, across the screen with the page's margins.
private struct ViewerCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
