#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import Foundation
import OnboardingDomain
import SwiftUI

/// 上场, on the gym: the squad stands where home will put them and turns to
/// look, the new member runs in from the right kicking up dust, skids, jumps with one and a half
/// turns and lands on their spot as the camera jolts, a shockwave crosses the floor and the ring
/// closes with confetti. The teammates cheer one after another, nearest first, each with a
/// welcome line. Then home's card drops in, the new member's head pops into its last ring, the
/// week count turns over to include the new plan, the 打卡 button and the tab bar rise, and home
/// takes over where the entrance left off. A tap once the card is in goes home at once.
struct EntranceScreen<Tabs: View>: View {
    let model: SignUpModel
    /// The app's tabs around the screen, their bar hidden (false) until it rises with the 打卡
    /// button as on home.
    let tabs: (Bool, AnyView) -> Tabs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = EntranceStage()
    @State private var bubbleSizes: [Int: CGSize] = [:]
    @State private var cardPage = SquadCardPage.squad
    /// Where home's card reaches down the screen, in global points, measured before it drops in
    /// so the bubbles stay clear of it.
    @State private var cardBottom: Double?

    /// The gym, as for all of sign-up; home opens on it too until each squad picks its scene.
    private let scene = SceneTheme.gym

    var body: some View {
        tabs(stage.showsChrome, AnyView(screen))
            .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: stage.showsChrome)
    }

    private var screen: some View {
        ZStack {
            GeometryReader { proxy in
                let unit = proxy.size.width / StageLayout.width
                ZStack(alignment: .topLeading) {
                    TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
                        let time = stage.time(at: timeline.date, reduceMotion: reduceMotion)
                        let camera = EntranceMotion.camera(at: time)
                        ZStack(alignment: .topLeading) {
                            SceneArt(scene: scene, layer: .day)
                                .frame(width: proxy.size.width, height: SceneArt.designHeight * unit)
                            SpotEffects(time: time, puffs: stage.motion?.puffs ?? [], unit: unit)
                            ForEach(stage.backToFront, id: \.index) { placed in
                                if let player = placed.member.player {
                                    figure(
                                        player, at: placed.position, unit: unit, crop: nil,
                                        facing: placed.position.facing)
                                }
                            }
                            if let player = stage.newcomer?.player, stage.isRunning {
                                figure(
                                    player, at: StagePosition.mine, unit: unit, crop: EntranceStage.runway,
                                    facing: EntranceMotion.facing(at: time), anchorX: stage.runwayAnchor(at: time))
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .scaleEffect(
                            camera.zoom,
                            anchor: UnitPoint(x: 0.5, y: StageLayout.mySpot.y * unit / max(proxy.size.height, 1))
                        )
                        .offset(y: camera.shake * unit)
                    }
                    Confetti(
                        start: stage.landedAt,
                        origin: CGPoint(x: StageLayout.mySpot.x * unit, y: StageLayout.mySpot.y * unit), unit: unit
                    )
                    .allowsHitTesting(false)
                    bubbles(
                        script: stage.script(unit: unit), unit: unit, width: proxy.size.width,
                        ceiling: cardBottom.map { $0 - proxy.frame(in: .global).minY } ?? 0)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(Color(role: .bgSubtle, in: scene))
            .clipped()
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // Where the card will land, unseen, for the bubbles to keep clear of.
                    card
                        .hidden()
                        .accessibilityHidden(true)
                        .onGeometryChange(for: Double.self) {
                            $0.frame(in: .global).maxY
                        } action: {
                            cardBottom = $0
                        }
                    if stage.showsCard {
                        card
                            .accessibilityIdentifier("entrance.card")
                            .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.top, Space.xs)
                Spacer()
            }

            if stage.showsChrome {
                chrome
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.sceneTheme, scene)
        // Home's own turf from here: its card, 打卡 and rings wear the scene, as home does.
        .accentTone(.scene)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: stage.showsCard)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: stage.showsChrome)
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: stage.countFlipped)
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: stage.myHeadIn)
        .contentShape(Rectangle())
        .onTapGesture { if stage.showsCard { model.finishEntrance() } }
        .haptic(.land, trigger: stage.hasLanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("你上场了，队友们在欢迎你", bundle: .module))
        .accessibilityIdentifier("entrance")
        .task {
            guard let character = model.myCharacter else { return }
            await stage.play(newcomer: character, teammates: model.teammates, on: scene, reduceMotion: reduceMotion)
            model.finishEntrance()
        }
    }

    /// Home's card: the squad's week, the teammates' heads, and the new member's popping into the
    /// last ring.
    @ViewBuilder private var card: some View {
        if let joined = model.joined {
            let goal = model.squadGoal
            SquadCard(
                squad: SquadWeek(
                    name: joined.name, done: joined.weekDone, goal: stage.countFlipped ? goal.after : goal.before,
                    members: stage.cardMembers),
                mine: myWeek, page: $cardPage
            ) { member in
                if let player = stage.player(for: member) {
                    CharacterHead(player: player)
                }
            }
        }
    }

    /// The 打卡 button where home has it, on the tab bar; for show until home takes over.
    private var chrome: some View {
        VStack(spacing: 0) {
            Spacer()
            CheckInBurst(isOpen: .constant(false), identifierPrefix: "entrance") { _ in }
                .padding(.bottom, Space.l)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// My week as the card's second page shows it: the template just made, counted from today as
    /// the first week is, nothing done yet, and no day to pick.
    private var myWeek: DesignSystemUI.MyWeek {
        let days = model.week?.days ?? Array(repeating: .rest, count: WeeklyPlan.dayCount)
        return DesignSystemUI.MyWeek(
            summary: "", done: 0, planned: model.plannedThisWeek,
            days: days.map { $0 == .rest ? .restDay : .open }, today: model.daysGone,
            details: [])
    }

    /// A character with its feet at `position`, in stage points scaled by `unit`, drawn as home
    /// draws it. `crop`, in canvas points, draws more than the canvas, for the run-in across the
    /// stage. `facing` mirrors it about `anchorX`, its feet across the drawn area (0 to 1).
    private func figure(
        _ player: CharacterPlayer, at position: StagePosition, unit: Double, crop: CGRect?, facing: Double,
        anchorX: Double = 0.5
    ) -> some View {
        let area = crop ?? CGRect(x: 0, y: 0, width: EntranceStage.canvas.width, height: EntranceStage.canvas.height)
        let scale = position.scale * unit
        let size = CGSize(width: area.width * scale, height: area.height * scale)
        // Where the canvas's feet fall inside the drawn area, from its top left.
        let feet = CGPoint(
            x: (EntranceStage.canvasFeet.x - area.minX) * scale, y: (EntranceStage.canvasFeet.y - area.minY) * scale)
        return CharacterView(player: player, crop: crop)
            .frame(width: size.width, height: size.height)
            .scaleEffect(x: facing, y: 1, anchor: UnitPoint(x: anchorX, y: 0.5))
            .position(
                x: position.point.x * unit - feet.x + size.width / 2,
                y: position.point.y * unit - feet.y + size.height / 2
            )
            .allowsHitTesting(false)
    }

    /// Each speaker's line over their head, laid out once every bubble has been measured so none
    /// covers another or goes under the card below `ceiling`; each shows from its cheer for
    /// `EntranceScript.lineDuration`.
    private func bubbles(script: EntranceScript, unit: Double, width: Double, ceiling: Double) -> some View {
        let lines = stage.lines
        let sizes = lines.indices.compactMap {
            bubbleSizes[$0].map { (width: Double($0.width), height: Double($0.height)) }
        }
        let tips =
            sizes.count == lines.count
            ? script.bubbles(
                sizes: sizes, myHeight: EntranceStage.myHeight(unit: unit), width: width, ceiling: ceiling) : []
        return ZStack(alignment: .topLeading) {
            ForEach(lines.indices, id: \.self) { index in
                let bubble = SpeechBubble(Text(LocalizedStringKey(lines[index]), bundle: .module))
                    .fixedSize()
                if let tip = tips[safe: index], let size = bubbleSizes[index] {
                    ZStack {
                        if stage.speaking.contains(index) {
                            bubble.transition(.speech(reduceMotion: reduceMotion))
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .position(x: tip.x, y: tip.y - size.height / 2)
                    .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: stage.speaking)
                } else {
                    bubble
                        .hidden()
                        .onGeometryChange(for: CGSize.self) {
                            $0.size
                        } action: {
                            bubbleSizes[index] = $0
                        }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension Array {
    /// The element at `index`, or nil past the end.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
