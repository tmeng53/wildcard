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

    /// Opens the post my caption's bubble is from: for now the 动态 tab, which will scroll to it
    /// once the feed is built.
    private let openPost: () -> Void

    public init(model: TodayModel, openPost: @escaping () -> Void = {}) {
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
        // 拍一拍 landing: mine on a teammate, or a teammate's on me.
        .haptic(.poke, trigger: model.pats.landed)
        .haptic(.reaction, trigger: model.pats.landedOnMe)
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
                celebration: model.celebrations, pats: model.pats, canPat: model.canPat, tapMate: model.tapMate,
                patMate: model.patMate
            )
            .overlay { MyPayoff(model: model, openPost: openPost) }
            .blur(radius: model.isSceneDimmed ? Scrim.blurRadius : 0)
            .overlay(Color(Scrim.tint).opacity(model.isSceneDimmed ? Scrim.tintOpacity : 0))
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if let home = model.home, let week = model.cardWeek, let day = home.mine?.day {
                    SquadCard(
                        squad: SquadWeek(
                            name: home.squad.name, done: week.squad.trainedDays, goal: week.squad.plannedDays,
                            members: home.today.members.map { mate in
                                SquadMember(
                                    id: mate.member.description,
                                    status: StageStatus(
                                        training: mate.training, activity: nil, plannedRest: mate.plannedRest
                                    ).ring,
                                    isMe: mate.member == home.member,
                                    accessibilityIdentifier: mate.member == home.member ? "today.myRing" : nil)
                            }),
                        mine: myWeek(home: home, day: day, week: week.mine),
                        page: $cardPage
                    ) { member in
                        if let player = model.head(of: member.id) { CharacterHead(player: player) }
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

/// My payoff over my character, front and centre: the 「+1」 of a 练了 and the line in the bubble
/// on my head.
private struct MyPayoff: View {
    let model: TodayModel
    let openPost: () -> Void

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
                    PayoffBubble(line: model.payoff?.line, open: openPost).fixedSize(horizontal: false, vertical: true)
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
