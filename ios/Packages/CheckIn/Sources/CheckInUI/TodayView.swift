#if os(iOS)
import AvatarUI
import CheckInDomain
import DesignSystem
import Contracts
import DesignSystemUI
import SportsUI
import SwiftUI

/// The 小队 tab (`.today`): the whole squad on its scene with the week's card on top, me front and centre,
/// and 打卡. Every check-in starts and ends here: the burst opens over the lightly blurred scene,
/// and after posting you stay on the scene for the payoff (the approved home, version 15).
public struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TodayModel
    /// The card's page, kept so the card reopens where it was left.
    @AppStorage("today.cardPage") private var cardPage: SquadCardPage = .squad
    /// Whether the card is folded into its capsule so the scene shows (folded until someone
    /// opens it, then as it was left).
    @AppStorage("today.cardCollapsed") private var isCardCollapsed = true
    /// The card and its capsule share one piece of glass, which morphs between them.
    @Namespace private var cardGlass
    /// The day picked on the card's second page; nil shows today. Leaving home forgets it: this
    /// view is made anew on coming back to the tab, and going to the background clears it.
    @State private var pickedDay: Int?
    /// How far above the screen's bottom edge the app's tab bar reaches, which 打卡 stands on:
    /// measured while the bar shows and kept while it hides, so 打卡 stays put when the burst opens.
    @State private var barRoom = Self.barRoomBeforeMeasured
    /// The day whose 今日赛况 was last opened on this phone (`LocalDay`'s description): its tag shows a dot until then.
    @AppStorage("today.recapSeen") private var recapSeen = ""
    /// The day whose 今日赛况 box score is open in the card's place: left open past the day's
    /// end, it doesn't reopen by itself the next evening.
    @State private var openRecapDay: LocalDay?

    /// Opens the post my caption's bubble is from in 动态; nil while it is still waiting to go
    /// out, which opens 动态 at the top.
    private let openPost: (CheckIn?) -> Void
    /// Opens 我的小队, from the squad's name on the card.
    private let openSquad: () -> Void

    public init(
        model: TodayModel, openSquad: @escaping () -> Void = {}, openPost: @escaping (CheckIn?) -> Void = { _ in }
    ) {
        _model = State(initialValue: model)
        self.openSquad = openSquad
        self.openPost = openPost
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
                    .accentTone(.brand)
                    .transition(.opacity)
            }

            if case .composing = model.step, let compose = model.compose {
                ComposeView(model: compose)
                    .accentTone(.brand)
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
        .modifier(HomeNotices(model: model))
        .modifier(HolidayOpening(model: model))
        // The one strong haptic of the payoff.
        .haptic(.checkIn, trigger: model.posts)
        // 拍一拍 landing: mine on a teammate, or a teammate's on me.
        .haptic(.poke, trigger: model.pats.landed)
        .haptic(.reaction, trigger: model.pats.landedOnMe)
        // The cord clicking the lights on; switching them off is quiet.
        .haptic(.lights, trigger: model.lightsPull) { _, pull in pull?.isOn == true }
        .onGeometryChange(for: Double.self) {
            $0.safeAreaInsets.bottom
        } action: { room in
            if model.showsTabBar { barRoom = room }
        }
        .task { await model.load() }
        .rereadsEachMinute(model)
        // Back in the app, possibly on a new day or after posts went out from another phone.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
            if phase == .background { pickedDay = nil }
        }
    }

    /// The squad on its scene, the week's card, my payoff and the 打卡 burst.
    private var scene: some View {
        ZStack {
            SquadSceneView(
                cast: model.cast, myPlayer: model.player, myRing: model.myRing,
                iSleep: model.myPose(at: .night) == .asleep, iHoldSign: model.myPose(at: .day) == .holdingSign,
                myDoze: model.myDoze, phase: model.phase,
                lightsOn: model.lightsOn, lightsPull: model.lightsPull, celebration: model.celebrations,
                pats: model.pats, together: model.together, canPat: model.canPat, tapMate: model.tapMate,
                tapMe: model.tapMe, patMate: model.patMate, arrival: model.arrival, tapCoach: model.tapCoach,
                coachHasNote: model.coachHasNote,
                tapVacancy: model.tapVacancy
            )
            .overlay { MyPayoff(model: model, openPost: openPost) }
            .blur(radius: model.isSceneDimmed ? Scrim.blurRadius : 0)
            .overlay(Color(Scrim.tint).opacity(model.isSceneDimmed ? Scrim.tintOpacity : 0))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if let home = model.home, let week = model.cardWeek, let day = home.mine?.day {
                    // Read again each minute, so 今日赛况 arrives at 21:00 with the app open.
                    TimelineView(.everyMinute) { _ in
                        VStack(spacing: Space.xs) {
                            topCard(home: home, week: week, day: day, recap: model.recap)
                            HealthHomeCard.Offer(model: model)
                        }
                        .overlay(alignment: .bottom) { lightCord(short: showsCapsule(day: day)) }
                    }
                    .padding(.top, Space.xs)
                    .modifier(Arriving(arrival: model.arrival) { $0.cardOffset(at: $1) })
                    .blur(radius: model.isBurstOpen ? Scrim.blurRadius : 0)
                    // Out of the way while the 请假条 composer is up.
                    .opacity(model.step == .disclaimer ? 0 : 1)
                    .offset(y: model.step == .disclaimer ? -Space.s : 0)
                }
                Spacer()
            }

            // A teammate's bubble when they pat me or join, over the card like the approved
            // design's, laid out on the scene's own stage.
            GeometryReader { proxy in
                PatOverlay(
                    layer: .bubble, cast: model.cast, pats: model.pats, unit: proxy.size.width / StageLayout.width,
                    canPat: model.canPat, pat: model.patMate)
            }
            .ignoresSafeArea()
            .opacity(model.step == .disclaimer ? 0 : 1)

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
                    checkInSpot
                        .padding(.bottom, Space.l)
                        .modifier(Arriving(arrival: model.arrival) { $0.buttonOffset(at: $1) })
                    // Room for the app's tab bar, which floats over this screen, measured from the
                    // screen's bottom edge.
                    Color.clear
                        .frame(height: barRoom)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.opacity)
            }
        }
    }

    /// The card at the top: the squad card, with the 今日赛况 tag as its last row from the evening
    /// on, or the evening's box score once the tag is tapped (the approved 今日赛况, version 4).
    @ViewBuilder
    private func topCard(
        home: Home, week: (squad: WeekCount, mine: WeekCount), day: LocalDay, recap: DayRecap?
    ) -> some View {
        GlassEffectContainer {
            squadCard(home: home, week: week, day: day, recap: recap)
        }
    }

    /// The capsule shows while the card is folded, and not while the box score takes its place.
    private func showsCapsule(day: LocalDay) -> Bool {
        isCardCollapsed && openRecapDay != day
    }

    @ViewBuilder
    private func squadCard(
        home: Home, week: (squad: WeekCount, mine: WeekCount), day: LocalDay, recap: DayRecap?
    ) -> some View {
        if let recap, openRecapDay == day {
            DayRecapCard(
                recap: recap, day: model.dayDate ?? .now, timeZone: home.timeZone, member: { model.recapMember($0) },
                close: { withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { openRecapDay = nil } }
            )
            .transition(.opacity)
        } else {
            let squad = SquadWeek(
                name: home.squad.name, done: week.squad.trainedDays, goal: week.squad.plannedDays,
                members: home.today.members.map { mate in
                    SquadMember(
                        id: mate.member.description,
                        status: StageStatus(training: mate.training, activity: nil, plannedRest: mate.plannedRest).ring,
                        isMe: mate.member == home.member,
                        accessibilityIdentifier: mate.member == home.member ? "today.myRing" : nil)
                })
            let mine = myWeek(home: home, day: day, week: week.mine)
            Group {
                if isCardCollapsed {
                    capsule(squad: squad, mine: mine, day: day, recap: recap)
                } else if let recap {
                    SquadCard(
                        squad: squad, mine: mine, page: $cardPage, pickedDay: $pickedDay, avatar: { head($0) },
                        footer: { recapTag(recap, day: day) }
                    )
                    .opensSquad(openSquad)
                    .collapses { foldCard(true) }
                    .morphs(cardMorph)
                } else {
                    SquadCard(squad: squad, mine: mine, page: $cardPage, pickedDay: $pickedDay) { head($0) }
                        .opensSquad(openSquad)
                        .collapses { foldCard(true) }
                        .morphs(cardMorph)
                }
            }
            .accessibilityIdentifier("today.card")
        }
    }

    /// The card folded: heads, the squad's score and my week. An unseen 今日赛况 hangs under its
    /// left end, out of its height so the cord still hangs from the capsule; once seen it shows
    /// in the open card alone.
    private func capsule(squad: SquadWeek, mine: DesignSystemUI.MyWeek, day: LocalDay, recap: DayRecap?) -> some View {
        SquadCapsule(
            squad: squad, mine: mine,
            heads: {
                HeadStack(
                    squad.members.map { model.head(of: $0.id) }, size: SquadCapsuleLayout.head, on: .bgCanvas,
                    limit: SquadCapsuleLayout.heads)
            },
            expand: { foldCard(false) }
        )
        .morphs(cardMorph)
        .overlay(alignment: .bottomLeading) {
            if let recap, recapSeen != day.description {
                recapTag(recap, day: day)
                    .padding(.leading, Space.pageMargin + Space.xs)
                    .offset(y: Sizing.tag + Space.xs)
                    .transition(.opacity)
            }
        }
        // One container, so `today.card` names it and not the capsule or the tag in it.
        .accessibilityElement(children: .contain)
    }

    /// The 今日赛况 tag, which opens the box score in the card's place.
    private func recapTag(_ recap: DayRecap, day: LocalDay) -> some View {
        RecapTag(recap: recap, isSeen: recapSeen == day.description) {
            recapSeen = day.description
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) {
                openRecapDay = day
            }
        }
    }

    /// Folds the card into its capsule, or opens it, the glass morphing between them.
    private func foldCard(_ folds: Bool) {
        withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { isCardCollapsed = folds }
    }

    private var cardMorph: GlassMorph { GlassMorph("today.card", in: cardGlass) }

    /// The tab bar's room until first measured (home opening as the squad drops in), with its gap.
    private static let barRoomBeforeMeasured: Double = 88

    /// The pull cord under the card at night (the approved 开灯), 40 points from the right edge,
    /// `short` under the folded capsule; it fades out while the 打卡 burst is open.
    @ViewBuilder
    private func lightCord(short: Bool) -> some View {
        if model.phase == .night {
            let isOn = model.lightsOn
            let chain = short ? PullCordMotion.shortLength : PullCordMotion.length
            PullCord(isOn ? Text("关灯", bundle: .module) : Text("开灯", bundle: .module), isOn: isOn, chain: chain) {
                model.pullCord(reduceMotion: reduceMotion)
            }
            .accessibilityIdentifier("today.lights")
            .padding(.trailing, Self.cordInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
            // Hangs from the card's bottom edge: the overlay puts its bottom there, so it moves
            // down by its own height (an offset moves its taps and VoiceOver frame with it).
            .offset(y: PullCord.frameSize(chain: chain).height)
            .opacity(model.isBurstOpen ? 0 : 1)
            .allowsHitTesting(!model.isBurstOpen)
            .accessibilityHidden(model.isBurstOpen)
            .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.isBurstOpen)
            .transition(.opacity)
        }
    }

    /// From the screen's right edge to the cord's frame: its centre sits 40 points in.
    private static let cordInset = 40 - PullCord.size.width / 2

    /// A teammate's head in the squad card's ring.
    @ViewBuilder
    private func head(_ member: SquadMember) -> some View {
        if let player = model.head(of: member.id) { CharacterHead(player: player) }
    }
}

/// Moves a piece of the home out of place while the squad drops onto a newly picked scene, by
/// the drop's own timeline (`DropIn`), its stage points taken as points; still under Reduce
/// Motion, and nothing once the squad has settled.
private struct Arriving: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let arrival: TodayModel.Arrival?
    let offset: (DropIn, Double) -> Double

    func body(content: Content) -> some View {
        // One TimelineView either way, so the card and 打卡 keep their state as the drop starts and ends.
        let moving = arrival != nil && !reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: !moving)) { timeline in
            content.offset(y: moving ? arrival.map { offset($0.drop, $0.elapsed(at: timeline.date)) } ?? 0 : 0)
        }
    }
}

extension TodayView {
    /// 打卡 and its burst, or, while my post goes out behind the scene, what became of it.
    fileprivate var checkInSpot: some View {
        Group {
            if let outgoing = model.outgoing {
                OutgoingPill(
                    outgoing: outgoing, progress: model.outgoingProgress, open: { openPost($0) },
                    dismiss: { model.dismissOutgoing() }
                )
                .frame(height: Sizing.primaryControl)
                .transition(.blurReplace)
            } else {
                CheckInBurst(
                    isOpen: $model.isBurstOpen, unavailable: model.unavailable, identifierPrefix: "today"
                ) { kind in
                    model.pick(kind)
                }
                .transition(.blurReplace)
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.outgoing == nil)
    }
}

#endif
