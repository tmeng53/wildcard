#if os(iOS)
import AvatarUI
import CheckInDomain
import DesignSystem
import Contracts
import DesignSystemUI
import SportsUI
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
    /// The day whose 今日赛况 was last opened on this phone (`LocalDay`'s description): its tag
    /// shows a dot until then.
    @AppStorage("today.recapSeen") private var recapSeen = ""
    /// The day whose 今日赛况 box score is open in the card's place: left open past the day's
    /// end, it doesn't reopen by itself the next evening.
    @State private var openRecapDay: LocalDay?

    /// Opens the post my caption's bubble is from in 动态; nil while it is still waiting to go
    /// out, which opens 动态 at the top.
    private let openPost: (CheckIn?) -> Void

    public init(model: TodayModel, openPost: @escaping (CheckIn?) -> Void = { _ in }) {
        _model = State(initialValue: model)
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

            if case .composing(let kind) = model.step {
                ComposeView(model: model, kind: kind)
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
        .sheet(isPresented: isPickingPhotos) {
            PhotoStep(model: model)
                .environment(\.sceneTheme, theme)
                .accentTone(.brand)
        }
        // The one strong haptic of the payoff.
        .haptic(.checkIn, trigger: model.posts)
        // 拍一拍 landing: mine on a teammate, or a teammate's on me.
        .haptic(.poke, trigger: model.pats.landed)
        .haptic(.reaction, trigger: model.pats.landedOnMe)
        // The cord clicking the lights on; switching them off is quiet.
        .haptic(.lights, trigger: model.lightsPull) { _, pull in pull?.isOn == true }
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
                lightsOn: model.lightsOn, lightsPull: model.lightsPull, celebration: model.celebrations,
                pats: model.pats, canPat: model.canPat, tapMate: model.tapMate,
                patMate: model.patMate, arrival: model.arrival
            )
            .overlay { MyPayoff(model: model, openPost: openPost) }
            .blur(radius: model.isSceneDimmed ? Scrim.blurRadius : 0)
            .overlay(Color(Scrim.tint).opacity(model.isSceneDimmed ? Scrim.tintOpacity : 0))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if let home = model.home, let week = model.cardWeek, let day = home.mine?.day {
                    // Read again each minute, so 今日赛况 arrives at 21:00 with the app open.
                    TimelineView(.everyMinute) { _ in
                        topCard(home: home, week: week, day: day, recap: model.recap)
                            .overlay(alignment: .bottom) { lightCord }
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

            // A tapped teammate's bubble, over the card like the approved design's, laid out on
            // the scene's own stage.
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
                    CheckInBurst(
                        isOpen: $model.isBurstOpen, unavailable: model.unavailable, identifierPrefix: "today"
                    ) { kind in
                        model.pick(kind)
                    }
                    .padding(.bottom, Space.l)
                    .modifier(Arriving(arrival: model.arrival) { $0.buttonOffset(at: $1) })
                    // Room for the app's tab bar, which sits above this screen, measured from the
                    // screen's bottom edge as the design does.
                    Color.clear
                        .frame(height: Sizing.tabBar + Sizing.tabBarBottom)
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
                if let recap {
                    SquadCard(
                        squad: squad, mine: mine, page: $cardPage, avatar: { head($0) },
                        footer: {
                            RecapTag(recap: recap, isSeen: recapSeen == day.description) {
                                recapSeen = day.description
                                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) {
                                    openRecapDay = day
                                }
                            }
                        })
                } else {
                    SquadCard(squad: squad, mine: mine, page: $cardPage) { head($0) }
                }
            }
            .accessibilityIdentifier("today.card")
            .transition(.opacity)
        }
    }

    /// The pull cord hanging under the card at night (the approved 开灯), its centre 40 points
    /// from the screen's right edge; it follows the card as 今日赛况 makes it taller and fades out
    /// while the 打卡 burst is open.
    @ViewBuilder
    private var lightCord: some View {
        if model.phase == .night {
            let isOn = model.lightsOn
            PullCord(isOn ? Text("关灯", bundle: .module) : Text("开灯", bundle: .module), isOn: isOn) {
                model.pullCord(reduceMotion: reduceMotion)
            }
            .accessibilityIdentifier("today.lights")
            .padding(.trailing, Self.cordInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
            // Hangs from the card's bottom edge.
            .alignmentGuide(.bottom) { $0[.top] }
            .opacity(model.isBurstOpen ? 0 : 1)
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

/// Moves a piece of the home out of place while the squad drops onto a newly picked scene, by
/// the drop's own timeline (`DropIn`), its stage points taken as points; still under Reduce
/// Motion, and nothing once the squad has settled.
private struct Arriving: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let arrival: TodayModel.Arrival?
    let offset: (DropIn, Double) -> Double

    func body(content: Content) -> some View {
        // One TimelineView either way, so the card and 打卡 keep their state as the drop
        // starts and ends.
        let moving = arrival != nil && !reduceMotion
        TimelineView(.animation(minimumInterval: nil, paused: !moving)) { timeline in
            content.offset(y: moving ? arrival.map { offset($0.drop, $0.elapsed(at: timeline.date)) } ?? 0 : 0)
        }
    }
}

/// My payoff over my character, front and centre: the 「+1」 of a 练了 and the line in the bubble
/// on my head.
private struct MyPayoff: View {
    let model: TodayModel
    let openPost: (CheckIn?) -> Void

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / StageLayout.width
            let head = CGPoint(
                x: StageLayout.mySpot.x * unit,
                y: (StageLayout.mySpot.y - Self.headHeight * StageLayout.myScale) * unit)
            // Each piece hangs off a zero-height anchor placed on the head: the bubble and the
            // 「+1」 sit above it, centred.
            ZStack {
                Self.anchor(width: Self.bubbleWidth, at: head, alignment: .bottom) {
                    PayoffBubble(line: model.payoff?.line) { openPost(model.payoff?.post) }.fixedSize(
                        horizontal: false, vertical: true)
                }
                Self.anchor(width: 0, at: CGPoint(x: head.x, y: head.y - Space.l), alignment: .bottom) {
                    PlusOne(trigger: model.celebrations).fixedSize()
                }
            }
        }
    }

    private static func anchor(
        width: Double, at point: CGPoint, alignment: Alignment, @ViewBuilder content: () -> some View
    ) -> some View {
        Color.clear
            .frame(width: width, height: 0)
            .overlay(alignment: alignment, content: content)
            .position(point)
    }

    /// The widest the caption's bubble gets before it wraps.
    private static let bubbleWidth = 240.0

    /// How far above the feet the top of the head is, in the rig's points.
    private static let headHeight = 250.0
}

/// The caption in the character's speech bubble. Nothing until the first post with a line.
private struct PayoffBubble: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let line: String?
    let open: () -> Void

    var body: some View {
        if let line {
            SpeechBubble(Text(verbatim: line), kind: .info(title: nil), action: open)
                .transition(.speech(reduceMotion: reduceMotion))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("today.bubble")
        }
    }
}

#endif
