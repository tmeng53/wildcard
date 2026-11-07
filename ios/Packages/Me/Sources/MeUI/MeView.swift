#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import HealthUI
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
    /// A post opened from 训练记录's popover, over 我.
    public var openPost: (CheckInID) -> Void
    /// The published policy pages.
    public var privacyPolicy: URL
    public var terms: URL
    /// 预览注册, for admins only: sign-up from the open screen on a sample squad, saving nothing.
    /// Nil for everyone else, and 设置 shows no row for it.
    public var previewSignUp: (() -> Void)?
    /// Apple Health, for 设置 › Apple 健康; nil where the phone has none.
    public var health: HealthConnection?

    public init(
        editCharacter: @escaping () -> Void, schedule: @escaping () -> Void,
        street: @escaping () -> Void = {}, streetHasNews: Bool = false,
        openPost: @escaping (CheckInID) -> Void = { _ in }, privacyPolicy: URL, terms: URL,
        previewSignUp: (() -> Void)? = nil, health: HealthConnection? = nil
    ) {
        self.previewSignUp = previewSignUp
        self.health = health
        self.editCharacter = editCharacter
        self.schedule = schedule
        self.street = street
        self.streetHasNews = streetHasNews
        self.openPost = openPost
        self.privacyPolicy = privacyPolicy
        self.terms = terms
    }
}

/// 我: 换装, 商店街 and 设置 at the top right, the member's player card across the page (tap it
/// to turn it over), under it the 出赛表 tile and the 我的动态 tile the app passes in side by side,
/// and then 训练记录, the heatmap of the member's last weeks; all as wide as the card. 设置 pushes
/// the settings menu, and from there 注销账号, on the NavigationStack 我 is the root of. These
/// pages keep out of the scene's colours: ink, graphite and white only.
public struct MeView<PostsTile: View>: View {
    @Bindable private var model: MeModel
    private let destinations: MeDestinations
    private let postsTile: PostsTile
    /// 设置 is pushed; the app keeps it, so a notice that opens another place on 我 closes it.
    @Binding private var isSettingsOpen: Bool
    @Environment(\.sceneTheme) private var theme

    /// `postsTile` is 我的动态's tile, which the feed draws (`GlanceTile` with the newest posts).
    public init(
        model: MeModel, destinations: MeDestinations, isSettingsOpen: Binding<Bool>,
        @ViewBuilder postsTile: () -> PostsTile
    ) {
        self.model = model
        _isSettingsOpen = isSettingsOpen
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
                    HStack(spacing: Space.cardGap) {
                        ScheduleTile(glance: overview.weekGlance, open: destinations.schedule)
                        postsTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if let record = overview.record {
                        TrainingRecordView(
                            record: record, trainedDays: overview.counts.trainedDays,
                            openPost: destinations.openPost
                        )
                        .padding(.top, Space.s)
                    }
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

/// 出赛表 beside 我的动态 under the card: this week's number, 出赛表, the days left in the week
/// (这周还有 N 天) and a white 编辑 pill, opening it inside 我 to change the plan.
struct ScheduleTile: View {
    let glance: WeekGlance?
    let open: () -> Void

    var body: some View {
        GlanceTile(
            figure: Text(verbatim: glance.map { "W\($0.number)" } ?? "–"),
            figureStyle: TypeRamp.scoreWeek, title: Text("出赛表", bundle: .module),
            caption: glance?.daysLeft.map { Text("这周还有 \($0) 天", bundle: .module) }, action: open
        ) {
            GlanceAction(Text("编辑", bundle: .module), systemImage: "pencil")
        }
        .accessibilityIdentifier("me.schedule")
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
