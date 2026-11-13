import CheckInUI
import Contracts
import FeedUI
import PlacesUI
import SwiftUI

/// 地点页: every place in the app opens it, pushed over the tab it was tapped on (Tracy,
/// 2026-11-12); Apple Maps opens only from its 在地图中打开.
extension MainTabs {
    /// Pushes the place's page on the tab in front: 动态's and 小队's stacks take it on top; on 我
    /// it goes over the post whose tag was tapped there, else it opens on 动态.
    func openPlace(_ place: Place) {
        switch selection {
        case .feed:
            feedPages.append(.place(place))
        case .today:
            todayPages.append(.place(place))
        case .profile:
            if post != nil {
                // From a post over a place, back to that place's own stack level.
                (profilePlace, profilePlacePost) = (place, nil)
            } else {
                selection = .feed
                feedPages.append(.place(place))
            }
        }
    }

    /// The place's page on the member's squad (动态's, while 今天 hasn't loaded: a launch into 动态
    /// or a push opens a tag before it); `openPost` pushes a tapped tile's post.
    func placePage(_ place: Place, openPost: @escaping (CheckInID) -> Void) -> some View {
        PlaceScreen(
            place: place, squad: today.squadID ?? feed.squad, source: places,
            today: LocalDay(at: LaunchOptions.now(), in: .autoupdatingCurrent), openPost: openPost
        )
        .environment(\.sceneTheme, today.scene)
    }
}

extension MainTabs {
    /// 地点页 from the compose page's place pill, pushed on the stack the compose page is on: 今天's,
    /// or the editing page's own over a post.
    var composePlacePage: PlacePageRoute {
        PlacePageRoute { place in
            AnyView(
                ComposedPlacePage(
                    place: place, page: { AnyView(placePage($0, openPost: $1)) }, post: { feed.page(of: $0) }))
        }
    }
}

/// The place opened from the compose page, with a tile's post pushed over it on the same stack, so
/// back returns to the place and then to the post being written.
private struct ComposedPlacePage: View {
    let place: Place
    let page: (Place, @escaping (CheckInID) -> Void) -> AnyView
    let post: (CheckInID) -> FeedModel
    @State private var opened: OpenedPost?

    var body: some View {
        page(place) { opened = OpenedPost(id: $0, model: post($0)) }
            .navigationDestination(item: $opened) { opened in
                PostDetailView(model: opened.model, post: opened.id) { self.opened = nil }
            }
    }
}
