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

    /// The place's page on the member's squad; `openPost` pushes a tapped tile's post.
    func placePage(_ place: Place, openPost: @escaping (CheckInID) -> Void) -> some View {
        PlaceScreen(
            place: place, squad: today.squadID, source: places,
            today: LocalDay(at: LaunchOptions.now(), in: .autoupdatingCurrent), openPost: openPost
        )
        .environment(\.sceneTheme, today.scene)
    }
}
