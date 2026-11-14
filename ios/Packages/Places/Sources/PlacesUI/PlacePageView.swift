#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import FeedUI
import MapKit
import PlacesDomain
import SportsUI
import SwiftUI

/// 地点页 (Tracy, 2026-11-12, layout D): the place's map across the top with 在地图中打开, and over
/// its foot a white business card: the place's icon, name, kind and address, its phone and website
/// from Maps, the squad's numbers (score first, then the star), its 运动 or 吃的 rows and the
/// squad's posts there as picture tiles. A place the squad never tagged shows the same card with
/// 「—」 and 0. Pushed on a tab's NavigationStack; `trailing` goes at the bar's right (收藏's
/// bookmark).
public struct PlacePageView<Trailing: View>: View {
    private let store: PlacePageStore
    private let today: LocalDay
    private let openPost: (CheckInID) -> Void
    private let trailing: Trailing
    @Environment(\.openURL) private var openURL
    @Environment(\.sceneTheme) private var theme

    /// - Parameters:
    ///   - today: the reader's today, which the posts' days are said from (今天, 周三).
    ///   - openPost: a tile was tapped: its post's own page.
    ///   - trailing: the bar's right, for 收藏's bookmark.
    public init(
        store: PlacePageStore, today: LocalDay, openPost: @escaping (CheckInID) -> Void,
        @ViewBuilder trailing: () -> Trailing
    ) {
        (self.store, self.today, self.openPost) = (store, today, openPost)
        self.trailing = trailing()
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PlaceMap(place: store.place, kind: store.kind)
                    .frame(height: Self.mapHeight)
                    .overlay(alignment: .bottomTrailing) { openInMaps }
                PlaceCard(store: store, today: today, openPost: openPost)
                    .padding(.top, -Self.sheetOverlap)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(role: .bgCanvas, in: theme))
        .pushedPage()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { trailing }
        }
        .refreshable { await store.load() }
        .task { await store.load() }
        .accessibilityIdentifier("place.page")
    }

    /// 在地图中打开: Apple Maps' own page of the place, the only way there from the app.
    private var openInMaps: some View {
        Button {
            if let link = store.place.mapsLink { openURL(link) }
        } label: {
            HStack(spacing: Space.xxs) {
                Text(copy: "在地图中打开", bundle: .module)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .typeStyle(TypeRamp.footnoteEmphasis)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.s)
            .frame(height: Sizing.compactControl - Space.xs)
            .background(.regularMaterial, in: Capsule())
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, Space.m)
        .padding(.bottom, Self.sheetOverlap + Space.xxs)
        .accessibilityIdentifier("place.openInMaps")
    }

    /// The map's height; the card rises `sheetOverlap` over its foot.
    private static var mapHeight: Double { 300 }
    private static var sheetOverlap: Double { 50 }
}

extension PlacePageView where Trailing == EmptyView {
    /// A page with nothing at the bar's right.
    public init(store: PlacePageStore, today: LocalDay, openPost: @escaping (CheckInID) -> Void) {
        self.init(store: store, today: today, openPost: openPost) { EmptyView() }
    }
}

/// The place on a still map, its pin a graphite disc with its kind's icon. The map takes no
/// touches: 在地图中打开 is for that.
private struct PlaceMap: View {
    let place: Place
    let kind: PlaceKind

    var body: some View {
        let spot = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        // The camera a little south of the place, so the pin sits clear of the card over the
        // map's foot.
        let center = CLLocationCoordinate2D(latitude: place.latitude - 0.0007, longitude: place.longitude)
        Map(initialPosition: .camera(MapCamera(centerCoordinate: center, distance: 1200))) {
            Annotation(place.name, coordinate: spot, anchor: .bottom) { PlacePin(symbol: kind.symbol) }
                .annotationTitles(.hidden)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A place's pin: a graphite disc in a white ring with its kind's icon, over a short point.
private struct PlacePin: View {
    let symbol: String

    var body: some View {
        VStack(spacing: -Space.xxs) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
                .frame(width: Sizing.control, height: Sizing.control)
                .background(Color(role: .bgBrand, in: .gym), in: Circle())
                .overlay(Circle().stroke(Color(role: .bgCanvas, in: .gym), lineWidth: 3))
            Triangle()
                .fill(Color(role: .bgBrand, in: .gym))
                .frame(width: 12, height: 10)
        }
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }
}

/// The white card over the map's foot.
private struct PlaceCard: View {
    let store: PlacePageStore
    let today: LocalDay
    let openPost: (CheckInID) -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        let numbers = store.numbers
        VStack(alignment: .leading, spacing: Space.m + Space.xxs / 2) {
            heading
            ContactCapsules(facts: store.facts)
            if store.showsSquad { squad(numbers) }
        }
        .padding(.horizontal, Space.m + Space.xxs)
        .padding(.top, Space.l)
        .padding(.bottom, Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Self.corner, topTrailingRadius: Self.corner, style: .continuous)
                .fill(Color(role: .bgCanvas, in: theme))
                .shadow(color: Color(role: .fgDefault, in: theme).opacity(0.06), radius: 10, y: -6)
        }
    }

    /// The squad's numbers, its rows and its posts there.
    @ViewBuilder
    private func squad(_ numbers: PlaceNumbers) -> some View {
        PlaceStats(cells: numbers.cells)
        Rectangle()
            .fill(Color(role: .borderDefault, in: theme))
            .frame(height: Sizing.hairline)
        if !numbers.rows.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionLabel(
                    numbers.face == .training
                        ? Text(copy: "运动", bundle: .module) : Text(copy: "吃的", bundle: .module))
                ForEach(numbers.rows, id: \.self) { row in PlaceRow(row: row) }
            }
        }
        if !store.posts.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                SectionLabel(Text(copy: "动态", bundle: .module))
                VisitGrid(store: store, today: today, openPost: openPost)
            }
        }
    }

    /// The kind's icon in a mist disc, the name, and the kind and address under it.
    private var heading: some View {
        HStack(spacing: Space.s) {
            Image(systemName: store.kind.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .frame(width: Sizing.control + Space.xxs, height: Sizing.control + Space.xxs)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs / 2) {
                Text(verbatim: store.place.name)
                    .typeStyle(TypeRamp.title)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("place.name")
                if let line = kindAndAddress {
                    Text(verbatim: line)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                }
            }
        }
    }

    /// 「健身房 · 897 Broadway」: what Maps calls its kind and its street, either alone.
    private var kindAndAddress: String? {
        let parts = [store.kind.localizedName, store.facts?.address].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static var corner: Double { 28 }
}

/// The place's phone and website from Maps as two white capsules side by side; only what Maps
/// has, and no row without either (Tracy, 2026-11-12: on every place's card). The phone number
/// always shows whole, and the website takes the room left (Tracy, 2026-11-14: a cut number is
/// no use).
private struct ContactCapsules: View {
    let facts: PlaceFacts?
    @Environment(\.openURL) private var openURL

    var body: some View {
        let phone = facts?.phone.flatMap { number in facts?.phoneURL.map { (number, $0) } }
        let site = facts?.websiteName.flatMap { name in facts?.website.map { (name, $0) } }
        if phone != nil || site != nil {
            HStack(spacing: Space.s) {
                if let phone {
                    ContactCapsule(symbol: "phone.fill", text: phone.0, whole: true, fills: site == nil) {
                        openURL(phone.1)
                    }
                    .accessibilityIdentifier("place.phone")
                }
                if let site {
                    ContactCapsule(symbol: "globe", text: site.0, whole: false, fills: true) { openURL(site.1) }
                        .accessibilityIdentifier("place.website")
                }
            }
        }
    }
}

private struct ContactCapsule: View {
    let symbol: String
    let text: String
    /// Never cut: the capsule is as wide as its text.
    let whole: Bool
    /// Takes the width left in the row.
    let fills: Bool
    let action: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text(verbatim: text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: whole, vertical: false)
            }
            .typeStyle(TypeRamp.calloutEmphasis)
            .foregroundStyle(Color(role: .fgDefault, in: theme))
            .padding(.horizontal, Space.s)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: Sizing.control)
            .background(Color(role: .bgCanvas, in: theme), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The squad's numbers in a row, on white: each a big number with its unit, its label under it,
/// grey while it is 0.
private struct PlaceStats: View {
    let cells: [PlaceNumbers.Cell]
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: Space.xs) {
            ForEach(cells, id: \.self) { cell in
                VStack(alignment: .leading, spacing: Space.xs - 2) {
                    HStack(alignment: .center, spacing: 0) {
                        Text(verbatim: value(cell))
                            .typeStyle(TypeRamp.scoreCard)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        unit(cell)
                    }
                    .foregroundStyle(Color(role: isEmpty(cell) ? .fgSubtle : .fgDefault, in: theme))
                    label(cell)
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            // The page's grid has three columns; the third stays empty (Tracy, 2026-11-13).
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place.stats")
    }

    private func value(_ cell: PlaceNumbers.Cell) -> String {
        switch cell {
        case .visits(let count), .people(let count): String(count)
        }
    }

    private func isEmpty(_ cell: PlaceNumbers.Cell) -> Bool {
        switch cell {
        case .visits(let count), .people(let count): count == 0
        }
    }

    /// After the number: its unit.
    @ViewBuilder private func unit(_ cell: PlaceNumbers.Cell) -> some View {
        switch cell {
        case .visits:
            Text(copy: "次", bundle: .module).typeStyle(TypeRamp.footnoteEmphasis).padding(.leading, Space.xxs)
        case .people:
            Text(copy: "人", bundle: .module).typeStyle(TypeRamp.footnoteEmphasis).padding(.leading, Space.xxs)
        }
    }

    private func label(_ cell: PlaceNumbers.Cell) -> Text {
        switch cell {
        case .visits: Text(copy: "小队来过", bundle: .module)
        case .people: Text(copy: "来过的队友", bundle: .module)
        }
    }
}

/// A 运动 or 吃的 row: the 战报's sport row in graphite, counted in 次.
private struct PlaceRow: View {
    let row: PlaceNumbers.Row
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        switch row {
        case .sport(let activity, let count, let fraction):
            bar(activity.symbol, activity.cardName, count, fraction)
        case .healthyMeals(let count, let fraction):
            bar(CheckInKind.healthyMeal.symbol, Text(copy: "健康餐", bundle: .module), count, fraction)
        case .cheatMeals(let count, let fraction):
            bar(CheckInKind.cheatMeal.symbol, Text(copy: "坦白放纵餐", bundle: .module), count, fraction)
        }
    }

    private func bar(_ symbol: String, _ name: Text, _ count: Int, _ fraction: Double) -> some View {
        SportBarRow(
            symbol: symbol, name: name, count: count, unit: Text(copy: "次", bundle: .module), fraction: fraction,
            fill: Color(role: .bgBrand, in: theme), track: Color(role: .bgSubtle, in: theme))
    }
}

extension PlaceKind {
    /// What the card calls the kind, before the address; nil for a kind it doesn't name.
    var localizedName: String? {
        switch self {
        case .gym: String(copy: "健身房", bundle: .module)
        case .food: String(copy: "餐厅", bundle: .module)
        case .cafe: String(copy: "咖啡店", bundle: .module)
        case .market: String(copy: "超市", bundle: .module)
        case .shop: String(copy: "商店", bundle: .module)
        case .park: String(copy: "公园", bundle: .module)
        case .beach: String(copy: "海滩", bundle: .module)
        case .sport: String(copy: "运动场", bundle: .module)
        case .other: nil
        }
    }
}
#endif
