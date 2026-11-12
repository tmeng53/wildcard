#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import HealthUI
import LocationDomain
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
    /// The App Store's 撰写评论 sheet for the app, which 意见反馈's 写评价 opens.
    public var writeReview: URL
    /// 预览注册, for admins only: sign-up from the open screen on a sample squad, saving nothing.
    /// Nil for everyone else, and 设置 shows no row for it.
    public var previewSignUp: (() -> Void)?
    /// Apple Health, for 设置 › Apple 健康; nil where the phone has none.
    public var health: HealthConnection?
    /// The phone's approximate location for the coach's weather, for 设置 › 位置; nil shows no row.
    public var location: LocationSharing?
    /// 设置 › 桌面小组件, how to put the home screen widgets on; nil shows no row.
    public var widgetGuide: AnyView?
    /// 设置 › 小队设置, the squad's own settings page, which 小队's gear opens too; nil shows no row.
    public var squadSettings: AnyView?
    /// What this phone saw of the member's badge board, for NEW, and the turns to it a notice
    /// asks for; nil shows no NEW.
    public var badgeMarks: BadgeMarks?

    public init(
        editCharacter: @escaping () -> Void, schedule: @escaping () -> Void,
        street: @escaping () -> Void = {}, streetHasNews: Bool = false,
        openPost: @escaping (CheckInID) -> Void = { _ in }, privacyPolicy: URL, terms: URL, writeReview: URL,
        previewSignUp: (() -> Void)? = nil, health: HealthConnection? = nil, location: LocationSharing? = nil,
        widgetGuide: AnyView? = nil, squadSettings: AnyView? = nil, badgeMarks: BadgeMarks? = nil
    ) {
        self.squadSettings = squadSettings
        self.badgeMarks = badgeMarks
        self.previewSignUp = previewSignUp
        self.widgetGuide = widgetGuide
        self.health = health
        self.location = location
        self.editCharacter = editCharacter
        self.schedule = schedule
        self.street = street
        self.streetHasNews = streetHasNews
        self.openPost = openPost
        self.privacyPolicy = privacyPolicy
        self.terms = terms
        self.writeReview = writeReview
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
    /// 外卡记录, pushed from 训练记录's 全部数据; a new model each time it opens.
    @State private var records: RecordsModel?
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
            .navigationDestination(
                isPresented: Binding(get: { records != nil }, set: { if !$0 { records = nil } })
            ) {
                if let records {
                    RecordsPage(model: records, character: model.overview?.character)
                        .pushedPage()
                }
            }
            .task { await model.reload() }
    }

    /// 换装, 商店街 (with its dot while a piece waits there unseen) and 设置: the system's round
    /// header buttons, icons only.
    private var header: some View {
        HStack(spacing: Space.xs) {
            Spacer()
            HeaderButton(Text(copy: "换装", bundle: .module), systemImage: "tshirt", action: destinations.editCharacter)
                .accessibilityIdentifier("me.editCharacter")
            HeaderButton(Text(copy: "商店街", bundle: .module), systemImage: "bag", action: destinations.street)
                .overlay(alignment: .topTrailing) {
                    if destinations.streetHasNews {
                        Circle()
                            .fill(Color(role: .bgBrand, in: theme))
                            .overlay(Circle().stroke(Color(role: .bgCanvas, in: theme), lineWidth: 2))
                            .frame(width: Self.dot, height: Self.dot)
                            .accessibilityIdentifier("me.street.dot")
                    }
                }
                .accessibilityValue(
                    destinations.streetHasNews ? Text(copy: "有新货", bundle: .module) : Text(verbatim: "")
                )
                .accessibilityIdentifier("me.street")
            HeaderButton(Text(copy: "设置", bundle: .module), systemImage: "gearshape") { isSettingsOpen = true }
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
                        face: overview.card, equip: { wearable in Task { await model.equip(wearable) } },
                        marks: destinations.badgeMarks, hint: nil,
                        fillsWidth: true)
                    HStack(spacing: Space.cardGap) {
                        ScheduleTile(glance: overview.weekGlance, open: destinations.schedule)
                        postsTile
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    if let record = overview.record {
                        TrainingRecordView(
                            record: record, trainedDays: overview.counts.trainedDays,
                            openPost: destinations.openPost, openRecords: { records = model.recordsModel() }
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
            figureStyle: TypeRamp.scoreWeek, title: Text(copy: "出赛表", bundle: .module),
            caption: glance?.daysLeft.map { Text(copy: "这周还有 \($0) 天", bundle: .module) }, action: open
        ) {
            GlanceAction(Text(copy: "编辑", bundle: .module), systemImage: "pencil")
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
        /// At the same desk writing in a notebook, stopping now and then to think (意见反馈).
        case writing
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
        .task(id: character) { await dress() }
    }

    /// Builds the art off the main actor, once per look and mood: the card's front is rebuilt on
    /// every flip, and a cached stage dresses as soon as it shows instead of after a parse.
    private func dress() async {
        guard let character else { return }
        let key = StageArt.Key(
            outfit: character.outfit, persona: character.persona, mood: mood, generation: StageArt.generation)
        let art: StageArt
        if let cached = StageArt.cache[key] {
            art = cached
        } else {
            guard let built = try? await Task.detached(operation: { try StageArt(key) }).value else {
                // Art that doesn't build leaves the stage empty; the rest of 我 still works.
                player = nil
                return
            }
            guard !Task.isCancelled else { return }
            StageArt.remember(built, for: key)
            art = built
        }
        do {
            if let player {
                try player.wear(art.figure, idle: art.idle)
            } else {
                player = try CharacterPlayer(figure: art.figure, idle: art.idle)
            }
        } catch {
            player = nil
        }
    }
}

/// A stage's parsed figure and idle, kept for the few looks 我 shows.
private struct StageArt: Sendable {
    struct Key: Hashable, Sendable {
        let outfit: Outfit
        let persona: Persona
        let mood: MeStage.Mood
        /// The downloaded art's generation, so a newer one is parsed again, not served stale.
        let generation: Int?
    }

    /// `ArtTree.downloaded` is swapped whole for each new generation, so its folder's file
    /// number changes with it; nil while nothing was downloaded.
    @MainActor static var generation: Int? {
        let folder = ArtTree.downloaded.path(percentEncoded: false)
        return (try? FileManager.default.attributesOfItem(atPath: folder))?[.systemFileNumber] as? Int
    }

    let figure: Figure
    let idle: Clip

    @MainActor static var cache: [Key: StageArt] = [:]

    @MainActor static func remember(_ art: StageArt, for key: Key) {
        // A handful of looks a session: an edit now and then, four moods.
        if cache.count >= 8 { cache.removeAll() }
        cache[key] = art
    }

    init(_ key: Key) throws(AvatarError) {
        let look =
            switch key.mood {
            case .typing: PlaceholderCharacter.atDesk(key.outfit)
            case .writing: PlaceholderCharacter.atDeskWriting(key.outfit)
            case .idle, .teary: key.outfit
            }
        figure = try PlaceholderCharacter.figure(wearing: look)
        switch key.mood {
        case .idle:
            // A held prop plays its move, looped at the persona's tempo.
            // `??` takes an untyped throwing closure, so it can't be used under typed throws.
            if let held = try PlaceholderCharacter.heldMove(wearing: key.outfit, persona: key.persona) {
                idle = held
            } else {
                idle = try PlaceholderCharacter.clip("idle", persona: key.persona)
            }
        case .typing: idle = try PlaceholderCharacter.typing(persona: key.persona)
        case .writing: idle = try PlaceholderCharacter.writing(persona: key.persona)
        case .teary: idle = try PlaceholderCharacter.teary(persona: key.persona)
        }
    }
}
#endif
