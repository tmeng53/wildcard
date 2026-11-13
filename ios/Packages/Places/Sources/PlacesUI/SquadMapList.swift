#if os(iOS)
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import PlacesDomain
import SportsUI
import SwiftUI

/// The list under the map: 今天's posts, one member's posts, or 小队常去.
struct SquadMapList: View {
    let store: SquadMapStore
    let heads: AuthorHeads
    let openPlace: (Place) -> Void
    let openPost: (CheckInID) -> Void
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        List {
            switch (store.mode, store.member) {
            case (.today, let member?):
                Section {
                    ForEach(store.rows) { visit in
                        Button {
                            openPost(visit.id)
                        } label: {
                            MemberPostRow(visit: visit, store: store)
                        }
                        .accessibilityIdentifier("squadMap.memberPost")
                    }
                } header: {
                    HStack {
                        Text(verbatim: name(of: member))
                        Text(copy: "今天", bundle: .module)
                        Spacer()
                        Button {
                            withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { store.showSquad() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(copy: "关闭", bundle: .module))
                        .accessibilityIdentifier("squadMap.closeMember")
                    }
                }
            case (.today, nil):
                if store.rows.isEmpty {
                    nothing(Text(copy: "今天还没有带地点的动态", bundle: .module))
                }
                ForEach(store.rows) { visit in
                    Button {
                        withAnimation(.wildcard(Motion.change, reduceMotion: reduceMotion)) { store.show(visit.author) }
                    } label: {
                        TodayRow(
                            visit: visit, store: store, head: heads.player(for: store.characters[visit.author]?.look))
                    }
                    .accessibilityIdentifier("squadMap.row")
                }
            case (.often, _):
                Section {
                    if store.layout.oftenPlaces.isEmpty {
                        nothing(Text(copy: "还没有带地点的动态", bundle: .module))
                    }
                    ForEach(store.layout.oftenPlaces) { place in
                        Button {
                            openPlace(place.place)
                        } label: {
                            OftenRow(place: place)
                        }
                        .accessibilityIdentifier("squadMap.oftenRow")
                    }
                } header: {
                    Text(copy: "小队常去", bundle: .module)
                }
            }
        }
        .listStyle(.plain)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
    }

    /// What an empty list says: a spinner while the first read runs, that the network failed when
    /// it did, else `text`.
    @ViewBuilder private func nothing(_ text: Text) -> some View {
        switch store.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
        case .offline, .signedOut, .notInSquad:
            empty(Text(copy: "网络开小差了", bundle: .module))
        case .loaded:
            empty(text)
        }
    }

    private func empty(_ text: Text) -> some View {
        text
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .listRowSeparator(.hidden)
    }

    private func name(of member: MemberID) -> String {
        store.characters[member]?.nickname.text ?? String(copy: "队友", bundle: .module)
    }
}

/// 今天's row: who, what and where, and when.
private struct TodayRow: View {
    let visit: MapVisit
    let store: SquadMapStore
    let head: CharacterPlayer?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            MemberHead(player: head, size: 32)
                .greyed(!store.isInSquad(visit.author))
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: store.characters[visit.author]?.nickname.text ?? String(copy: "队友", bundle: .module))
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .lineLimit(1)
                Text(verbatim: "\(visit.doing) · \(store.layout.place(visit.key)?.place.name ?? "")")
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            Text(visit.createdAt.date, format: MapVisit.clock)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

/// One of a member's posts today: what, where and when.
private struct MemberPostRow: View {
    let visit: MapVisit
    let store: SquadMapStore
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: visit.activity?.symbol ?? visit.kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: visit.doing)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .lineLimit(1)
                Text(verbatim: store.layout.place(visit.key)?.place.name ?? "")
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
            }
            Spacer(minLength: Space.xs)
            Text(visit.createdAt.date, format: MapVisit.clock)
                .typeStyle(TypeRamp.footnote)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .monospacedDigit()
        }
        .contentShape(Rectangle())
    }
}

/// 小队常去's row: the place, what the squad did there, and how many times it went.
private struct OftenRow: View {
    let place: MapPlace
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: place.place.kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color(role: .bgSubtle, in: theme), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: place.place.name)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .lineLimit(1)
                if let line = done {
                    Text(verbatim: line)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Space.xs)
            HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
                Text(verbatim: "\(place.visits)")
                    .typeStyle(TypeRamp.headline)
                    .monospacedDigit()
                Text(copy: "次", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
        }
        .contentShape(Rectangle())
    }

    /// 「动感单车 · HIIT」 or 「健康餐」: its sports, most first, then its meals by kind.
    private var done: String? {
        var parts = place.sports.prefix(2).map(\.activity.localizedName)
        if place.meals.healthyMeals > 0 { parts.append(String(copy: "健康餐", bundle: .module)) }
        if place.meals.cheatMeals > 0 { parts.append(String(copy: "坦白放纵餐", bundle: .module)) }
        return parts.isEmpty ? nil : parts.prefix(2).joined(separator: " · ")
    }
}

extension MapVisit {
    /// When it was posted, as the map and its list say it: 「18:42」.
    static var clock: Date.FormatStyle {
        Date.FormatStyle.dateTime.hour().minute().locale(AppLanguage.current.locale)
    }

    /// What the post was: a 训练's sport, else the meal's kind.
    var doing: String {
        if let activity { return activity.localizedName }
        return switch kind {
        case .healthyMeal: String(copy: "健康餐", bundle: .module)
        case .cheatMeal: String(copy: "坦白放纵餐", bundle: .module)
        case .trained, .disclaimer: String(copy: "训练", bundle: .module)
        }
    }
}

extension View {
    /// A teammate who left the squad: greyed.
    func greyed(_ greyed: Bool) -> some View {
        grayscale(greyed ? 1 : 0).opacity(greyed ? 0.5 : 1)
    }
}
#endif
