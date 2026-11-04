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
    /// 我的动态: everything the member posted.
    public var myPosts: () -> Void
    /// 商店街, opened inside 我 from its shopfront.
    public var street: () -> Void
    /// Whether a piece came in that 商店街 hasn't shown yet: the shopfront's dot.
    public var streetHasNews: Bool
    /// The published policy pages.
    public var privacyPolicy: URL
    public var terms: URL

    public init(
        editCharacter: @escaping () -> Void, schedule: @escaping () -> Void, myPosts: @escaping () -> Void,
        street: @escaping () -> Void = {}, streetHasNews: Bool = false, privacyPolicy: URL, terms: URL
    ) {
        self.editCharacter = editCharacter
        self.schedule = schedule
        self.myPosts = myPosts
        self.street = street
        self.streetHasNews = streetHasNews
        self.privacyPolicy = privacyPolicy
        self.terms = terms
    }
}

/// 我: the member's player card (tap it to turn it over), the 出赛表 row, 我的动态 and 编辑外卡运动员, with a small 设置 button that opens the settings menu,
/// and from there 注销账号. Each page replaces the last in place. These pages keep out of the
/// scene's colours: ink and white only.
public struct MeView: View {
    @Bindable private var model: MeModel
    private let destinations: MeDestinations
    @State private var isSettingsOpen = false
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
                    .swipesBack(isEnabled: model.deletion != .deleting) { model.closeDeletion() }
                    .accentTone(.ink)
                    .transition(.move(edge: .trailing))
            } else if isSettingsOpen {
                SettingsView(model: model, destinations: destinations) { isSettingsOpen = false }
                    .accentTone(.ink)
                    .transition(.move(edge: .trailing))
            } else {
                content
                    .loadingCover(model.load == .loading) { MeLoading() }
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: model.isDeletionOpen)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: isSettingsOpen)
        .task { await model.reload() }
    }

    /// 我的动态 and 编辑外卡运动员: side by side, stacked where the words don't fit in a row.
    @ViewBuilder private var actions: some View {
        Button(action: destinations.myPosts) {
            Label {
                Text("我的动态", bundle: .module)
            } icon: {
                Image(systemName: "square.grid.2x2.fill")
            }
        }
        .buttonStyle(PrimaryButtonStyle(.regular))
        .accessibilityIdentifier("me.myPosts")
        Button(action: destinations.editCharacter) {
            Text("编辑外卡运动员", bundle: .module)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("me.editCharacter")
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .loading:
            Color.clear
        case .failed:
            MeFailed { Task { await model.reload() } }
        case .loaded(let overview):
            ScrollView {
                // Space.m between pieces, so the card, 出赛表 and the buttons all clear the tab bar
                // on the smallest phone without scrolling.
                VStack(spacing: Space.m) {
                    HStack(alignment: .top) {
                        Shopfront(hasNews: destinations.streetHasNews, open: destinations.street)
                        Spacer()
                        Button {
                            isSettingsOpen = true
                        } label: {
                            Text("设置", bundle: .module)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("me.settings")
                    }
                    PlayerCard(face: overview.card, equip: { title in Task { await model.equip(title) } })
                    ScheduleRow(week: overview.week, open: destinations.schedule)
                    VStack(spacing: Space.xs) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: Space.s) { actions }
                            VStack(spacing: Space.xs) { actions }
                        }
                        if model.saveFailed {
                            SaveFailed()
                        }
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

/// 商店街's door at the top left of 我, opposite 设置 (the approved wardrobe design, 2026-11-04): a
/// graphite and white shopfront over its name, with a dot while a piece waits there unseen.
struct Shopfront: View {
    let hasNews: Bool
    let open: () -> Void
    @Environment(\.sceneTheme) private var theme
    private let door = CGSize(width: 40, height: 38)
    private let dot: Double = 12

    var body: some View {
        Button(action: open) {
            VStack(spacing: Space.xxs / 2) {
                Canvas { context, size in draw(in: &context, size: size) }
                    .frame(width: door.width, height: door.height)
                    .overlay(alignment: .topTrailing) {
                        if hasNews {
                            Circle()
                                .fill(Color(role: .bgInk, in: theme))
                                .overlay(Circle().stroke(Color(role: .bgCanvas, in: theme), lineWidth: 2))
                                .frame(width: dot, height: dot)
                                .offset(x: Space.xxs, y: -Space.xxs)
                                .accessibilityIdentifier("me.street.dot")
                        }
                    }
                Text("商店街", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(hasNews ? Text("有新货", bundle: .module) : Text(verbatim: ""))
        .accessibilityIdentifier("me.street")
    }

    /// The shop in the design's 64 × 60 drawing: a white front, the graphite awning with its three
    /// white seams and scalloped edge, a graphite door and a window.
    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let ink = Color(role: .bgInk, in: theme)
        let white = Color(role: .bgCanvas, in: theme)
        let line = StrokeStyle(lineWidth: 2.5, lineCap: .round)
        context.scaleBy(x: size.width / 64, y: size.height / 60)
        let front = Path(roundedRect: CGRect(x: 10, y: 20, width: 44, height: 36), cornerRadius: 4)
        context.fill(front, with: .color(white))
        context.stroke(front, with: .color(ink), style: line)
        var awning = Path()
        awning.move(to: CGPoint(x: 6, y: 8))
        awning.addArc(
            center: CGPoint(x: 10, y: 8), radius: 4, startAngle: .degrees(180), endAngle: .degrees(270),
            clockwise: false)
        awning.addLine(to: CGPoint(x: 54, y: 4))
        awning.addArc(
            center: CGPoint(x: 54, y: 8), radius: 4, startAngle: .degrees(270), endAngle: .degrees(360),
            clockwise: false)
        awning.addLine(to: CGPoint(x: 58, y: 18))
        for center in [51.5, 38.5, 25.5, 12.5] {
            awning.addArc(
                center: CGPoint(x: center, y: 18), radius: 6.5, startAngle: .degrees(0), endAngle: .degrees(180),
                clockwise: false)
        }
        awning.closeSubpath()
        context.fill(awning, with: .color(ink))
        var seams = Path()
        for seam in [19.0, 32, 45] {
            seams.move(to: CGPoint(x: seam, y: 6))
            seams.addLine(to: CGPoint(x: seam, y: 18))
        }
        context.stroke(seams, with: .color(white), style: line)
        context.fill(Path(roundedRect: CGRect(x: 17, y: 32, width: 12, height: 24), cornerRadius: 2), with: .color(ink))
        context.stroke(
            Path(roundedRect: CGRect(x: 35, y: 32, width: 12, height: 10), cornerRadius: 2), with: .color(ink),
            style: line)
    }
}

/// 出赛表 under the card, with this week's count, opening it inside 我.
struct ScheduleRow: View {
    let week: WeekCount?
    let open: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button(action: open) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: Space.xxs / 2) {
                    Text("出赛表", bundle: .module)
                        .typeStyle(TypeRamp.headline)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                    if let week {
                        Text("本周 \(week.trainedDays)/\(week.plannedDays)", bundle: .module)
                            .typeStyle(TypeRamp.footnote)
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgSubtle, in: theme))
                    .accessibilityHidden(true)
            }
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
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
