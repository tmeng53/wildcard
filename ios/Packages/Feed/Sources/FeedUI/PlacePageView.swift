#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import MapKit
import SportsUI
import SwiftUI

extension EnvironmentValues {
    /// Opens a tagged place's page (地点页) over the page a post's place was tapped on; the app
    /// sets it where it can push one. Without it, a place opens Apple Maps.
    @Entry public var openPlace: (@MainActor (Place) -> Void)?
}

/// A tagged place's page (地点页, Tracy, 2026-11-13, the approved ② and ③): the place's name and
/// kind, a graphite card of what the squad did there (a place to train: 小队评分, 小队来过 N 次,
/// 来过的队友 N 人; a place to eat: its meals' 健康, 好吃 and 卡价比, and how often the squad came),
/// 在地图中打开 for Apple's own card, the member's own score of a place to train, what the squad
/// trained or ate there, and its posts, each opening its post. White, like 小队.
public struct PlacePageView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.openURL) private var openURL
    private let store: PlacePageStore
    private let model: FeedModel
    private let openPost: (CheckInID) -> Void
    /// The street Apple Maps gives the place, under its name.
    @State private var address: String?
    /// The member's taps on the stars, so the pick's haptic answers a tap and not a load.
    @State private var picks = 0

    public init(store: PlacePageStore, model: FeedModel, openPost: @escaping (CheckInID) -> Void) {
        self.store = store
        self.model = model
        self.openPost = openPost
    }

    /// The place's own icon circle, the design's.
    private static let iconCircle: CGFloat = 44
    /// The member's stars.
    private static let star: CGFloat = 32

    private var place: Place { store.page?.place ?? store.place }
    private var kind: PlaceKind { place.kind }

    /// A place to eat shows its meals' scores and no score of its own (Tracy, 2026-11-12): what
    /// Maps files as food, or, for a place Maps files as neither, one the squad ate at more than
    /// it trained at.
    private var isForEating: Bool {
        switch kind {
        case .food, .cafe, .market: true
        case .gym, .park, .beach, .sport: false
        case .shop, .other: (store.page?.meals.count ?? 0) > (store.page?.trainings ?? 0)
        }
    }

    public var body: some View {
        ZStack {
            Color(role: .bgCanvas, in: theme).ignoresSafeArea()
            switch store.phase {
            case .failed:
                StateView.offline(retryIdentifier: "place.retry") { Task { await store.load() } }
                    .padding(.horizontal, Space.pageMargin)
            case .loading, .shown:
                page
            }
        }
        .pushedPage(hidesTabBar: true)
        .barTitleOnScroll(Text(verbatim: place.name))
        .loadingCover(store.phase == .loading) {
            TicketSpinner(on: .light(.bgCanvas))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(role: .bgCanvas, in: theme))
        }
        .task { await store.load() }
        .task(id: place.appleID) { address = await Self.address(of: place) }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                header
                VStack(alignment: .leading, spacing: Space.xs) {
                    PlaceNumbers(page: store.page, isForEating: isForEating)
                    HStack {
                        if isForEating, let people = store.page?.people {
                            Text(copy: "\(people) 人来过", bundle: .module)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                        }
                        Spacer(minLength: Space.s)
                        mapsButton
                    }
                }
                if !isForEating { myScore }
                if let page = store.page {
                    if isForEating {
                        meals(page.meals)
                    } else if !page.sports.isEmpty {
                        sports(page.sports)
                    }
                    if !page.posts.isEmpty { posts(page.posts) }
                }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.xl)
        }
        .accessibilityIdentifier("place.page")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Image(systemName: kind.symbol)
                .font(.system(size: Sizing.icon, weight: .semibold))
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .frame(width: Self.iconCircle, height: Self.iconCircle)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: place.name)
                    .typeStyle(TypeRamp.title)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("place.title")
                subtitle
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
            }
        }
    }

    /// 健身房 · 897 Broadway: the kind, and the street once Maps gave it.
    private var subtitle: Text {
        guard let address else { return kind.name }
        return kind.name + Text(verbatim: " · \(address)")
    }

    private var mapsButton: some View {
        Button {
            if let link = place.mapsLink { openURL(link) }
        } label: {
            HStack(spacing: Space.xxs) {
                Text(copy: "在地图中打开", bundle: .module)
                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.smallIcon - 4, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place.maps")
    }

    // MARK: - 我的评分

    private var myScore: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(Text(copy: "我的评分", bundle: .module))
            StarRating(rating: store.myStars ?? 0, size: Self.star, spacing: Space.s) { stars in
                picks += 1
                Task { await store.rate(stars) }
            }
            .accessibilityIdentifier("place.myStars")
            if store.rateFailed { InlineFailure() }
        }
        .haptic(.pick, trigger: picks)
    }

    // MARK: - 运动, 吃的 and 动态

    private func sports(_ sports: [PlacePage.SportCount]) -> some View {
        let most = sports.map(\.count).max() ?? 1
        return VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(Text(copy: "运动", bundle: .module))
            ForEach(sports, id: \.activity.key) { sport in
                PlaceTallyRow(symbol: sport.activity.symbol, name: sport.activity.name, count: sport.count, most: most)
            }
        }
    }

    private func meals(_ meals: PlacePage.Meals) -> some View {
        let most = max(meals.healthyMeals, meals.cheatMeals, 1)
        return VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(Text(copy: "吃的", bundle: .module))
            ForEach([(CheckInKind.healthyMeal, meals.healthyMeals), (.cheatMeal, meals.cheatMeals)], id: \.0) {
                PlaceTallyRow(symbol: $0.0.symbol, name: $0.0.fullName, count: $0.1, most: most)
            }
        }
    }

    private func posts(_ posts: [PlaceVisit]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(Text(copy: "动态", bundle: .module))
                .padding(.bottom, Space.xs)
            ForEach(Array(posts.enumerated()), id: \.element.id) { index, visit in
                Button {
                    openPost(visit.checkIn)
                } label: {
                    PlaceVisitRow(visit: visit, model: model, showsDivider: index < posts.count - 1)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("place.post")
            }
        }
    }

    // MARK: - Apple Maps

    /// The street Apple Maps has for the place, in its short form; nil for a place Maps can't
    /// find or while offline.
    private static func address(of place: Place) async -> String? {
        guard let id = place.appleID else { return nil }
        let identifier: MKMapItem.Identifier? = MKMapItem.Identifier(rawValue: id)
        guard let identifier else { return nil }
        let item = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
        return item?.address?.shortAddress
    }
}
#endif
