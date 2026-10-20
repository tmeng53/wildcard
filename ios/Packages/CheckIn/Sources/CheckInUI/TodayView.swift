#if os(iOS)
import AvatarUI
import CheckInDomain
import DesignSystem
import Contracts
import DesignSystemUI
import SwiftUI

/// The 今天 tab: the whole squad on its scene with the week's card on top, me front and centre,
/// and 打卡. Every check-in starts and ends here: the burst opens over the lightly blurred scene,
/// and after posting you stay on the scene for the payoff (the approved home, version 15).
public struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TodayModel
    /// The card's page, kept so the card reopens where it was left.
    @AppStorage("today.cardPage") private var cardPage: SquadCardPage = .squad

    public init(model: TodayModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        let theme = model.scene
        // The 请假条 composer and the compose page make room for the keyboard. The scene sits in
        // the background, so it neither sizes this stack nor moves with the keyboard: as a layer
        // of it, the scene, taller than what the keyboard leaves, would push the composer and the
        // page up under the status bar.
        ZStack {
            if model.step == .disclaimer {
                DisclaimerComposer(model: model)
                    .transition(.opacity)
            }

            if case .composing(let kind) = model.step {
                ComposeView(model: model, kind: kind)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            scene.ignoresSafeArea(.keyboard)
        }
        .environment(\.sceneTheme, theme)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: model.step)
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: model.home)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.payoff)
        .sheet(isPresented: isPickingPhotos) {
            PhotoStep(model: model)
                .environment(\.sceneTheme, theme)
        }
        // The one strong haptic of the payoff.
        .haptic(.checkIn, trigger: model.posts)
        .task { await model.load() }
        // Back in the app, possibly on a new day or after posts went out from another phone.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
    }

    /// The squad on its scene, the week's card, my payoff and the 打卡 burst.
    private var scene: some View {
        ZStack {
            SquadSceneView(
                cast: model.cast, myPlayer: model.player, myRing: model.myRing, phase: model.phase,
                celebration: model.celebrations
            )
            .overlay { MyPayoff(model: model) }
            .blur(radius: model.isSceneDimmed ? Scrim.blurRadius : 0)
            .overlay(Color(Scrim.tint).opacity(model.isSceneDimmed ? Scrim.tintOpacity : 0))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if let home = model.home, let week = model.cardWeek, let day = model.day {
                    SquadCard(
                        squad: SquadWeek(
                            name: home.squad.name, done: week.squad.trainedDays, goal: week.squad.plannedDays,
                            members: home.today.members.map { mate in
                                SquadMember(
                                    id: mate.member.description,
                                    status: StageStatus(
                                        training: mate.training, activity: nil, plannedRest: mate.plannedRest
                                    ).ring,
                                    accessibilityIdentifier: mate.member == home.member ? "today.myRing" : nil)
                            }),
                        mine: myWeek(home: home, day: day, week: week.mine),
                        page: $cardPage
                    ) { member in
                        Head(player: model.head(of: member.id))
                    }
                    .padding(.top, Space.xs)
                    .blur(radius: model.isBurstOpen ? Scrim.blurRadius : 0)
                    // Out of the way while the 请假条 composer is up.
                    .opacity(model.step == .disclaimer ? 0 : 1)
                    .offset(y: model.step == .disclaimer ? -Space.s : 0)
                    .accessibilityIdentifier("today.card")
                }
                Spacer()
            }

            if model.isBurstOpen {
                // A tap anywhere outside the capsules closes the burst.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.isBurstOpen = false }
                    }
                    .accessibilityHidden(true)
            }

            if model.step != .disclaimer {
                VStack {
                    Spacer()
                    CheckInBurst(
                        isOpen: $model.isBurstOpen, unavailable: model.unavailable, identifierPrefix: "today"
                    ) { kind in
                        model.pick(kind)
                    }
                    .padding(.bottom, Space.l)
                    TabBar(Self.tabs, selection: .constant(Tab.today))
                        .padding(.horizontal, Space.pageMargin)
                        .padding(.bottom, Sizing.tabBarBottom)
                        .blur(radius: model.isBurstOpen ? Scrim.blurRadius : 0)
                }
                .transition(.opacity)
            }
        }
    }

    /// The app's tabs, as the approved home draws them. Only 今天 is built so far, so the bar
    /// stays on it.
    private enum Tab: Hashable {
        case today, moments, schedule, profile
    }

    private static let tabs: [TabBarItem<Tab>] = [
        TabBarItem(
            id: .today, title: Text("今天", bundle: .module), systemImage: "house", accessibilityIdentifier: "tab.today"),
        TabBarItem(id: .moments, title: Text("名场面", bundle: .module), systemImage: "star"),
        TabBarItem(id: .schedule, title: Text("出赛表", bundle: .module), systemImage: "list.bullet.rectangle"),
        TabBarItem(id: .profile, title: Text("我", bundle: .module), systemImage: "person"),
    ]

    /// My week for the card's second page: this week's days, what I trained and my meals, with
    /// the counts the squad's today carries.
    private func myWeek(home: Home, day: LocalDay, week: WeekCount) -> DesignSystemUI.MyWeek {
        let record = home.week(on: day)
        return DesignSystemUI.MyWeek(
            summary: record.trained.map {
                String(localized: "\($0.activity.localizedName) \($0.days)", bundle: .module)
            }
            .joined(separator: " · "),
            done: week.trainedDays, planned: week.plannedDays,
            days: record.days.map {
                switch $0 {
                case .trained: .trained
                case .disclaimer: .excused
                case .restDay: .restDay
                case .open: .open
                }
            },
            today: record.today, healthyMeals: record.healthyMeals, cheatMeals: record.cheatMeals,
            lifetimeTrained: home.today.myWeek.lifetimeTrainedDays)
    }

    private var isPickingPhotos: Binding<Bool> {
        Binding {
            if case .pickingPhotos = model.step { true } else { false }
        } set: { isPresented in
            // Swiped down: the same as 取消.
            if !isPresented, case .pickingPhotos = model.step { model.cancel() }
        }
    }
}

/// My payoff over my character, front and centre: the 「+1」 of a 练了, the line in the bubble
/// on my head and the cover pinned beside it, like a polaroid: one figure, not three objects.
private struct MyPayoff: View {
    let model: TodayModel

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / StageLayout.width
            let head = CGPoint(
                x: StageLayout.mySpot.x * unit,
                y: (StageLayout.mySpot.y - Self.headHeight * StageLayout.myScale) * unit)
            ZStack(alignment: .topLeading) {
                PayoffBubble(line: model.payoff?.line)
                    .alignmentGuide(.top) { $0[.bottom] }
                    .alignmentGuide(.leading) { $0.width / 2 }
                    .offset(x: head.x, y: head.y)
                PinnedCover(cover: model.payoff?.cover)
                    .offset(x: head.x + Space.xl, y: head.y)
                PlusOne(trigger: model.celebrations)
                    .alignmentGuide(.top) { $0[.bottom] }
                    .alignmentGuide(.leading) { $0.width / 2 }
                    .offset(x: head.x, y: head.y - Space.l)
            }
        }
    }

    /// How far above the feet the top of the head is, in the rig's points.
    private static let headHeight = 250.0
}

/// A member's head in the card's ring.
private struct Head: View {
    let player: CharacterPlayer?

    var body: some View {
        if let player {
            CharacterCanvas(drawing: player.drawing, placements: player.restPlacements, crop: Self.face)
        }
    }

    /// The face on the rig's 240 by 320 canvas.
    private static let face = CGRect(x: 40, y: 74, width: 160, height: 160)
}

/// The caption in the character's speech bubble. Nothing until the first post with a line.
private struct PayoffBubble: View {
    /// The widest a bubble grows before its line wraps.
    private static let maxWidth: Double = 230

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let line: String?

    var body: some View {
        if let line {
            SpeechBubble(Text(verbatim: line))
                // A fixed-width frame centres the bubble; the text inside takes only the width it needs.
                .frame(width: Self.maxWidth)
                .transition(.speech(reduceMotion: reduceMotion))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.bubble")
        }
    }
}

/// The post's cover photo, pinned beside the character's head.
private struct PinnedCover: View {
    @Environment(\.sceneTheme) private var theme
    let cover: PreparedPhoto?

    var body: some View {
        if let cover {
            PhotoImage(photo: cover)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail - Space.xxs, style: .continuous))
                .padding(Space.xxs)
                .background(
                    Color(role: .bgCanvas, in: theme),
                    in: RoundedRectangle(cornerRadius: Radius.thumbnail, style: .continuous)
                )
                .rotationEffect(.degrees(8))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    TodayView(
        model: TodayModel(
            store: TodayStore(
                backend: InMemoryCheckInBackend.sampleSquad(now: .now), outbox: InMemoryOutbox(), now: { Date() },
                newID: { UUID() }),
            writer: DiceDisclaimerWriter()))
}
#endif
