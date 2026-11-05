#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// Where 我's buttons lead outside this package. The app decides.
public struct MeDestinations {
    public var editCharacter: () -> Void
    /// 出赛表, opened inside 我.
    public var schedule: () -> Void
    /// 商店街, opened inside 我 from its button.
    public var street: () -> Void
    /// Whether a piece came in that 商店街 hasn't shown yet: the dot on its button.
    public var streetHasNews: Bool
    /// The published policy pages.
    public var privacyPolicy: URL
    public var terms: URL

    public init(
        editCharacter: @escaping () -> Void, schedule: @escaping () -> Void,
        street: @escaping () -> Void = {}, streetHasNews: Bool = false, privacyPolicy: URL, terms: URL
    ) {
        self.editCharacter = editCharacter
        self.schedule = schedule
        self.street = street
        self.streetHasNews = streetHasNews
        self.privacyPolicy = privacyPolicy
        self.terms = terms
    }
}

/// 我: 换装, 商店街 and 设置 at the top right, the member's player card across the page (tap it
/// to turn it over), and under it the 出赛表 tile and the 我的动态 tile the app passes in, as wide
/// as the card. 设置 pushes the settings menu, and from there 注销账号, on the NavigationStack 我
/// is the root of. These pages keep out of the scene's colours: ink, graphite and white only.
public struct MeView<PostsTile: View>: View {
    @Bindable private var model: MeModel
    private let destinations: MeDestinations
    private let postsTile: PostsTile
    @State private var isSettingsOpen = false
    @Environment(\.sceneTheme) private var theme

    /// `postsTile` is 我的动态's tile, which the feed draws (`GlanceTile` with the newest posts).
    public init(model: MeModel, destinations: MeDestinations, @ViewBuilder postsTile: () -> PostsTile) {
        self.model = model
        self.destinations = destinations
        self.postsTile = postsTile()
    }

    public var body: some View {
        content
            .loadingCover(model.load == .loading) { MeLoading() }
            .navigationDestination(isPresented: $isSettingsOpen) {
                SettingsView(model: model, destinations: destinations)
                    .accentTone(.ink)
            }
            .task { await model.reload() }
    }

    /// 换装, 商店街 (with its dot while a piece waits there unseen) and 设置: the system's round
    /// header buttons, icons only.
    private var header: some View {
        HStack(spacing: Space.xs) {
            Spacer()
            HeaderButton(Text("换装", bundle: .module), systemImage: "tshirt", action: destinations.editCharacter)
                .accessibilityIdentifier("me.editCharacter")
            HeaderButton(Text("商店街", bundle: .module), systemImage: "bag", action: destinations.street)
                .overlay(alignment: .topTrailing) {
                    if destinations.streetHasNews {
                        Circle()
                            .fill(Color(role: .bgBrand, in: theme))
                            .overlay(Circle().stroke(Color(role: .bgCanvas, in: theme), lineWidth: 2))
                            .frame(width: Self.dot, height: Self.dot)
                            .accessibilityIdentifier("me.street.dot")
                    }
                }
                .accessibilityValue(destinations.streetHasNews ? Text("有新货", bundle: .module) : Text(verbatim: ""))
                .accessibilityIdentifier("me.street")
            HeaderButton(Text("设置", bundle: .module), systemImage: "gearshape") { isSettingsOpen = true }
                .accessibilityIdentifier("me.settings")
        }
    }

    /// The 商店街 dot.
    private static var dot: Double { 12 }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .loading:
            Color.clear
        case .failed:
            MeFailed { Task { await model.reload() } }
        case .loaded(let overview):
            ScrollView {
                VStack(spacing: Space.s) {
                    header
                    PlayerCard(
                        face: overview.card, equip: { title in Task { await model.equip(title) } }, hint: nil,
                        fillsWidth: true)
                    ScheduleTile(week: overview.week, glance: overview.weekGlance, open: destinations.schedule)
                    postsTile
                    if model.saveFailed {
                        SaveFailed()
                    }
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(role: .bgCanvas, in: theme))
            .refreshable { await model.reload() }
            .accessibilityIdentifier("me.page")
        }
    }
}

/// 出赛表 under the card: this week's number, 出赛表 with 本周 x/y, and the week's seven days
/// (a white disc with a tick for a day with a 练了, a ring for a training day still to come or
/// gone by, a moon for a rest day, today's mark heavier), opening it inside 我. Without the days
/// it shows the count alone.
struct ScheduleTile: View {
    let week: WeekCount?
    let glance: WeekGlance?
    let open: () -> Void

    var body: some View {
        GlanceTile(
            figure: glance.map { Text(verbatim: "W\($0.number)") } ?? Text("出赛表", bundle: .module),
            figureStyle: glance == nil ? TypeRamp.headline : TypeRamp.scoreWeek,
            caption: caption, action: open
        ) {
            if let glance {
                GlanceWeekDays(
                    glance.days.map { day in
                        let status: WeekDayStatus =
                            switch day.mark {
                            case .trained: .trained(symbol: nil)
                            case .planned: .open
                            case .rest: .restDay
                            }
                        return GlanceWeekDays.Day(status: status, isToday: day.isToday)
                    }
                )
                .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("me.schedule")
    }

    /// 出赛表 · 3/5, or 出赛表 alone with no plan this week; 本周 3/5 when the week has no number.
    private var caption: Text {
        switch (glance, week) {
        case (.some, .some(let week)): Text("出赛表 · \(week.trainedDays)/\(week.plannedDays)", bundle: .module)
        case (.some, .none): Text("出赛表", bundle: .module)
        case (.none, .some(let week)): Text("本周 \(week.trainedDays)/\(week.plannedDays)", bundle: .module)
        case (.none, .none): Text(verbatim: "")
        }
    }
}

/// The last change didn't save; says so until the next one.
struct SaveFailed: View {
    var body: some View {
        InlineFailure()
            .accessibilityIdentifier("me.saveFailed")
    }
}

/// The member's character on a little floor shadow: its persona's idle on the card, typing at
/// its laptop on 设置, near tears on 注销账号, at its persona's pace. It changes clothes in
/// place when the character is edited.
struct MeStage: View {
    enum Mood {
        /// Standing and playing its persona's idle.
        case idle
        /// At a small desk behind a laptop, typing and peeking over the screen now and then.
        case typing
        /// Worried brows, a wobbly frown and tears rolling down.
        case teary
    }

    let character: MeCharacter?
    var mood = Mood.idle
    var size = CGSize(width: 160, height: 200)
    /// The shadow's colour, so it shows on the page and in the card's window alike.
    var floor: ColorRole = .bgSubtle
    @State private var player: CharacterPlayer?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color(role: floor, in: theme))
                .frame(width: size.width * 0.6, height: Space.xs)
            Group {
                if let player {
                    CharacterView(player: player)
                } else {
                    Color.clear
                }
            }
            .frame(width: size.width, height: size.height - Space.xxs)
            .padding(.bottom, Space.xxs)
        }
        .frame(width: size.width, height: size.height)
        .task(id: character) { dress() }
    }

    private func dress() {
        guard let character else { return }
        do {
            let look = mood == .typing ? PlaceholderCharacter.atDesk(character.outfit) : character.outfit
            let figure = try PlaceholderCharacter.figure(wearing: look)
            let idle: Clip
            switch mood {
            case .idle: idle = try PlaceholderCharacter.clip("idle", persona: character.persona)
            case .typing: idle = try PlaceholderCharacter.typing(persona: character.persona)
            case .teary: idle = try PlaceholderCharacter.teary(persona: character.persona)
            }
            if let player {
                try player.wear(figure, idle: idle)
            } else {
                player = try CharacterPlayer(figure: figure, idle: idle)
            }
        } catch {
            // Art that doesn't build leaves the stage empty; the rest of 我 still works.
            player = nil
        }
    }
}
#endif
