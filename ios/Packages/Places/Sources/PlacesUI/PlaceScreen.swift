#if os(iOS)
import Contracts
import PlacesDomain
import SwiftUI

/// A place's page as a tab pushes it: makes the page's store once, the first time the page is
/// drawn, so going back and forth over it keeps what it read.
public struct PlaceScreen<Trailing: View>: View {
    @State private var store: PlacePageStore
    private let today: LocalDay
    private let openPost: (CheckInID) -> Void
    private let trailing: (Place) -> Trailing

    /// - Parameters:
    ///   - squad: the reader's squad, whose numbers it shows; nil when they are in none.
    ///   - trailing: the bar's right for this place (收藏's bookmark).
    public init(
        place: Place, squad: SquadID?, source: any PlaceSource, directory: any PlaceDirectory = MapKitDirectory(),
        today: LocalDay, openPost: @escaping (CheckInID) -> Void,
        @ViewBuilder trailing: @escaping (Place) -> Trailing
    ) {
        _store = State(
            initialValue: PlacePageStore(place: place, squad: squad, source: source, directory: directory))
        (self.today, self.openPost, self.trailing) = (today, openPost, trailing)
    }

    public var body: some View {
        PlacePageView(store: store, today: today, openPost: openPost) { trailing(store.place) }
    }
}

extension PlaceScreen where Trailing == EmptyView {
    public init(
        place: Place, squad: SquadID?, source: any PlaceSource, directory: any PlaceDirectory = MapKitDirectory(),
        today: LocalDay, openPost: @escaping (CheckInID) -> Void
    ) {
        self.init(
            place: place, squad: squad, source: source, directory: directory, today: today, openPost: openPost
        ) { _ in EmptyView() }
    }
}
#endif
