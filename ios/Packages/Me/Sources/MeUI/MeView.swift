#if canImport(SwiftUI)
import AvatarArt
import AvatarUI
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Where 我's rows lead outside the tab. The app decides: the squad and past 战报 open their
/// tabs until they have pages of their own.
public struct MeDestinations {
    public var squad: () -> Void
    public var pastRecaps: () -> Void
    public var editCharacter: () -> Void
    /// The published policy pages; a row shows only once its page is there.
    public var privacyPolicy: URL?
    public var terms: URL?

    public init(
        squad: @escaping () -> Void, pastRecaps: @escaping () -> Void, editCharacter: @escaping () -> Void,
        privacyPolicy: URL?, terms: URL?
    ) {
        self.squad = squad
        self.pastRecaps = pastRecaps
        self.editCharacter = editCharacter
        self.privacyPolicy = privacyPolicy
        self.terms = terms
    }
}

/// 我: the member's character (tap it to edit), how much they ever checked in, their squad, and
/// their settings, with signing out and deleting the account at the bottom.
public struct MeView: View {
    @Bindable private var model: MeModel
    private let destinations: MeDestinations
    @State private var isSigningOut = false
    @Environment(\.openURL) private var openURL
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: MeModel, destinations: MeDestinations) {
        self.model = model
        self.destinations = destinations
    }

    public var body: some View {
        ZStack {
            if model.isDeletionOpen {
                DeleteAccountView(model: model) { model.closeDeletion() }
                    .transition(.move(edge: .trailing))
            } else {
                content
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: model.isDeletionOpen)
        .task { await model.reload() }
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .loading:
            MeLoading()
        case .failed:
            MeFailed { Task { await model.reload() } }
        case .loaded(let overview):
            ScrollView {
                VStack(spacing: Space.l) {
                    header(overview)
                    LifetimeCard(counts: overview.counts)
                    rows(overview)
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.vertical, Space.l)
            }
            .scrollIndicators(.hidden)
            .background(Color(role: .bgCanvas, in: theme))
            .refreshable { await model.reload() }
            .accessibilityIdentifier("me.page")
        }
    }

    private func header(_ overview: MeOverview) -> some View {
        VStack(spacing: Space.xs) {
            Button(action: destinations.editCharacter) {
                MeStage(character: overview.character)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("编辑角色", bundle: .module))
            Text(overview.character.nickname)
                .typeStyle(TypeRamp.title)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
                .accessibilityIdentifier("me.nickname")
            Button(action: destinations.editCharacter) {
                Text("编辑角色", bundle: .module)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("me.editCharacter")
            if model.saveFailed {
                Text("网络开小差了，没存上", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .accessibilityIdentifier("me.saveFailed")
            }
        }
    }

    private func rows(_ overview: MeOverview) -> some View {
        VStack(spacing: Space.cardGap) {
            squadRows(overview)
            settingRows
            accountRows
        }
    }

    private func squadRows(_ overview: MeOverview) -> some View {
        VStack(spacing: 0) {
            if let squad = overview.squadName {
                ListRow(
                    Text("我的小队", bundle: .module), systemImage: "person.3", value: Text(squad),
                    action: destinations.squad
                )
                .accessibilityIdentifier("me.squad")
            }
            ListRow(
                Text("往期战报", bundle: .module), systemImage: "trophy", showsDivider: false,
                action: destinations.pastRecaps)
        }
        .card()
    }

    private var settingRows: some View {
        VStack(spacing: 0) {
            SwitchRow(
                Text("通知", bundle: .module), systemImage: "bell",
                isOn: Binding(
                    get: { model.dailyPushOn },
                    set: { isOn in Task { await model.setDailyPush(isOn) } })
            )
            .accessibilityIdentifier("me.notifications")
            ListRow(
                Text("语言", bundle: .module), systemImage: "globe",
                value: Text("language.current", bundle: .module),
                showsDivider: destinations.privacyPolicy != nil || destinations.terms != nil
            ) {
                // iOS keeps each app's language in Settings; the app follows it.
                if let settings = Self.appSettings { openURL(settings) }
            }
            if let privacy = destinations.privacyPolicy {
                ListRow(
                    Text("隐私政策", bundle: .module), systemImage: "hand.raised",
                    showsDivider: destinations.terms != nil
                ) { openURL(privacy) }
            }
            if let terms = destinations.terms {
                ListRow(Text("用户条款", bundle: .module), systemImage: "doc.text", showsDivider: false) {
                    openURL(terms)
                }
            }
        }
        .card()
    }

    private var accountRows: some View {
        VStack(spacing: 0) {
            ListRow(Text("退出登录", bundle: .module), systemImage: "rectangle.portrait.and.arrow.right") {
                isSigningOut = true
            }
            .accessibilityIdentifier("me.signOut")
            // The system's own confirm, as the design asks: signing out is one tap from undoable.
            .confirmationDialog(Text("退出登录？", bundle: .module), isPresented: $isSigningOut, titleVisibility: .visible) {
                Button(role: .destructive) {
                    Task { await model.signOut() }
                } label: {
                    Text("退出登录", bundle: .module)
                }
                .accessibilityIdentifier("me.signOut.confirm")
            }
            ListRow(Text("注销账号", bundle: .module), systemImage: "person.crop.circle.badge.xmark", showsDivider: false) {
                model.openDeletion()
            }
            .accessibilityIdentifier("me.deleteAccount")
        }
        .card()
    }
}

extension MeView {
    /// This app's page in the Settings app.
    @MainActor static var appSettings: URL? {
        #if canImport(UIKit)
        URL(string: UIApplication.openSettingsURLString)
        #else
        nil
        #endif
    }
}

/// The member's character on a little floor shadow, as large as the page's hero: typing at its
/// laptop on 我, near tears on 注销账号, at its persona's pace. It changes clothes in place when
/// the character is edited.
struct MeStage: View {
    enum Mood {
        /// At a small desk behind a laptop, typing and peeking over the screen now and then.
        case typing
        /// Worried brows, a wobbly frown and tears rolling down.
        case teary
    }

    let character: MeCharacter?
    var mood = Mood.typing
    @State private var player: CharacterPlayer?
    @Environment(\.sceneTheme) private var theme
    static let size = CGSize(width: 180, height: 240)

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color(role: .bgSubtle, in: theme))
                .frame(width: Self.size.width * 0.7, height: Space.s)
            Group {
                if let player {
                    CharacterView(player: player)
                } else {
                    Color.clear
                }
            }
            .frame(width: Self.size.width, height: Self.size.height - Space.xxs)
            .padding(.bottom, Space.xxs)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .contentShape(Rectangle())
        .task(id: character) { dress() }
    }

    private func dress() {
        guard let character else { return }
        do {
            let look = mood == .typing ? PlaceholderCharacter.atDesk(character.outfit) : character.outfit
            let figure = try PlaceholderCharacter.figure(wearing: look)
            let idle =
                try mood == .typing
                ? PlaceholderCharacter.typing(persona: character.persona)
                : PlaceholderCharacter.teary(persona: character.persona)
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

/// 一共练了 128 次, then the other kinds in a line. Scoreboard digits, as on the home card.
struct LifetimeCard: View {
    let counts: LifetimeCounts
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("一共练了", bundle: .module)
                .typeStyle(TypeRamp.label)
                .foregroundStyle(Color(role: .fgMuted, in: theme))
            HStack(alignment: .lastTextBaseline, spacing: Space.xxs) {
                Text(counts.trainedDays, format: .number)
                    .typeStyle(TypeRamp.scoreHero)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("me.trainedDays")
                Text("次", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
            }
            Text(
                "健康餐 \(counts.healthyMeals) · 放纵餐 \(counts.cheatMeals) · 请假条 \(counts.disclaimers)",
                bundle: .module
            )
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .accessibilityIdentifier("me.otherCounts")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}
#endif
