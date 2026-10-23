#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SwiftUI

/// 上场: on sign-up's brand floor, the teammates turn to look, the new member runs in from the right,
/// jumps and lands on the empty spot in front, the ring under them closes with a burst of
/// confetti, and the teammates cheer one after another, nearest first, each with a welcome line.
/// Then the squad's card drops in and its week count turns over to include the new plan, and
/// home takes over. A tap once the card is in goes home at once.
struct EntranceScreen: View {
    let model: SignUpModel
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = EntranceStage()
    @State private var bubbleSizes: [Int: CGSize] = [:]
    @State private var cardPage = SquadCardPage.squad

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / EntranceStage.designWidth
            let script = stage.script(unit: unit)
            ZStack(alignment: .topLeading) {
                BrandFloor(theme: theme)
                    .frame(height: proxy.size.height * (1 - EntranceStage.floorTop))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                LandingRing(isClosed: stage.hasLanded, reduceMotion: reduceMotion)
                    .frame(width: EntranceStage.ringWidth * unit, height: EntranceStage.ringHeight * unit)
                    .position(x: script.spot.x, y: script.spot.y)
                ForEach(Array(stage.teammates.enumerated()), id: \.offset) { index, member in
                    if let player = member.player, let spot = stage.teammateSpots[safe: index] {
                        figure(player, at: spot, unit: unit, crop: nil)
                    }
                }
                if let player = stage.newcomer?.player {
                    figure(player, at: EntranceStage.mySpot, unit: unit, crop: EntranceStage.runway)
                        .opacity(stage.isRunning ? 1 : 0)
                }
                Confetti(start: stage.landedAt, origin: CGPoint(x: script.spot.x, y: script.spot.y), unit: unit)
                    .allowsHitTesting(false)
                bubbles(script: script, unit: unit, width: proxy.size.width)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .overlay(alignment: .top) {
            if stage.showsCard, let joined = model.joined {
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
                .padding(.top, Space.xs)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityIdentifier("entrance.card")
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: stage.showsCard)
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: stage.countFlipped)
        .background(Color(role: .bgBrandPage, in: theme).ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { if stage.showsCard { model.finishEntrance() } }
        .haptic(.land, trigger: stage.hasLanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("你上场了，队友们在欢迎你", bundle: .module))
        .accessibilityIdentifier("entrance")
        .task {
            guard let character = model.myCharacter else { return }
            await stage.play(newcomer: character, teammates: model.teammates, reduceMotion: reduceMotion)
            model.finishEntrance()
        }
    }

    /// My week as the card's second page shows it: the plan just made, nothing done yet.
    private var myWeek: DesignSystemUI.MyWeek {
        let days = model.week?.days ?? Array(repeating: .rest, count: WeeklyPlan.dayCount)
        return DesignSystemUI.MyWeek(
            summary: "", done: 0, planned: model.week?.trainingDays ?? 0,
            days: days.map { $0 == .rest ? .restDay : .open }, today: model.daysGone, healthyMeals: 0,
            cheatMeals: 0, lifetimeTrained: 0)
    }

    /// A character with its feet at `spot`, in design points scaled by `unit`. `crop`, in canvas
    /// points, draws more than the canvas, for the run-in across the stage.
    private func figure(_ player: CharacterPlayer, at spot: EntranceStage.Spot, unit: Double, crop: CGRect?)
        -> some View
    {
        let area = crop ?? CGRect(x: 0, y: 0, width: EntranceStage.canvas.width, height: EntranceStage.canvas.height)
        let scale = spot.scale * unit
        let size = CGSize(width: area.width * scale, height: area.height * scale)
        // Where the canvas's feet fall inside the drawn area, from its top left.
        let feet = CGPoint(
            x: (EntranceStage.canvasFeet.x - area.minX) * scale, y: (EntranceStage.canvasFeet.y - area.minY) * scale)
        return CharacterView(player: player, crop: crop)
            .frame(width: size.width, height: size.height)
            .position(x: spot.feet.x * unit - feet.x + size.width / 2, y: spot.feet.y * unit - feet.y + size.height / 2)
            .allowsHitTesting(false)
    }

    /// Each speaker's line over their head, laid out once every bubble has been measured so none
    /// covers another; each shows from its cheer for `EntranceScript.lineDuration`.
    private func bubbles(script: EntranceScript, unit: Double, width: Double) -> some View {
        let lines = stage.lines
        let sizes = lines.indices.compactMap {
            bubbleSizes[$0].map { (width: Double($0.width), height: Double($0.height)) }
        }
        let tips =
            sizes.count == lines.count
            ? script.bubbles(sizes: sizes, myHeight: EntranceStage.myHeight(unit: unit), width: width) : []
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

/// Who is on the stage and what has happened so far, from the clock.
@MainActor @Observable
final class EntranceStage {
    struct Spot {
        /// Where the feet stand, in design points.
        let feet: Point
        /// The canvas's points per design point.
        let scale: Double
    }

    /// The design's points, on a 390-point-wide screen.
    static let designWidth = 390.0
    static let floorTop = 0.66
    /// The new member's spot: front and center.
    static let mySpot = Spot(feet: Point(x: 195, y: 676), scale: 0.28)
    /// Teammates in the order they joined: the front row either side of the spot, then the back.
    static let spots = [
        Spot(feet: Point(x: 115, y: 626), scale: 0.2469), Spot(feet: Point(x: 275, y: 626), scale: 0.2469),
        Spot(feet: Point(x: 35, y: 626), scale: 0.2469), Spot(feet: Point(x: 355, y: 626), scale: 0.2469),
        Spot(feet: Point(x: 155, y: 566), scale: 0.2336), Spot(feet: Point(x: 235, y: 566), scale: 0.2336),
        Spot(feet: Point(x: 75, y: 566), scale: 0.2336),
    ]
    /// The character's canvas and where its feet stand in it.
    static let canvas = CGSize(width: 240, height: 320)
    static let canvasFeet = CGPoint(x: 120, y: 316.8)
    /// The area the entrance clip crosses, in canvas points: from 911 to the right of the spot
    /// to a little left of it, and up over the top of the jump.
    static let runway = CGRect(x: -60, y: -380, width: 1280, height: 710)
    /// How tall a line's tail stands over the feet, in canvas points: just above the head.
    static let headHeight = 292.0
    /// The ring under the spot, in design points.
    static let ringWidth = 60.0
    static let ringHeight = 20.0

    private(set) var newcomer: CastMember?
    private(set) var teammates: [CastMember] = []
    private(set) var teammateSpots: [Spot] = []
    /// One welcome line per speaker, String Catalog keys: the new member's first.
    private(set) var lines: [String] = []
    private(set) var isRunning = false
    private(set) var hasLanded = false
    private(set) var landedAt: Date?
    /// The lines up now, by index into `lines`.
    private(set) var speaking: Set<Int> = []
    private(set) var showsCard = false
    private(set) var countFlipped = false

    /// The new member's head over their feet, in screen points, for the bubble's tail.
    static func myHeight(unit: Double) -> Double {
        headHeight * mySpot.scale * unit
    }

    /// The script in screen points for a screen `unit` points per design point wide. When things
    /// happen doesn't depend on the screen's size.
    func script(unit: Double) -> EntranceScript {
        EntranceScript(
            spot: Point(x: Self.mySpot.feet.x * unit, y: Self.mySpot.feet.y * unit),
            teammates: teammateSpots.map {
                EntranceScript.Teammate(
                    feet: Point(x: $0.feet.x * unit, y: $0.feet.y * unit),
                    height: Self.headHeight * $0.scale * unit)
            })
    }

    /// Builds everyone, then plays the moment through to its end. With Reduce Motion it shows how
    /// it ends, with every line up, for the time it takes to read them.
    func play(newcomer member: CastMember, teammates squad: [CastMember], reduceMotion: Bool) async {
        let shown = Array(squad.prefix(Self.spots.count))
        let newcomer = CastMember(outfit: member.look, persona: member.persona)
        self.newcomer = newcomer
        teammates = shown
        teammateSpots = Array(Self.spots.prefix(shown.count))
        var generator = SystemRandomNumberGenerator()
        lines = WelcomeLines.pick(for: [.newcomer] + shown.map { .teammate($0.persona) }, using: &generator)
        await newcomer.load(idle: !reduceMotion)
        for teammate in shown { await teammate.load(idle: !reduceMotion) }
        let script = script(unit: 1)
        if reduceMotion {
            isRunning = true
            hasLanded = true
            speaking = Set(lines.indices)
            showsCard = true
            countFlipped = true
            await wait(until: EntranceScript.lineDuration, from: .now)
            return
        }
        let start = Date.now
        var events: [(time: Double, run: () -> Void)] = [
            (EntranceScript.run, { [weak self] in self?.run(newcomer) }),
            (EntranceScript.land, { [weak self] in self?.land() }),
            (
                script.myLine,
                { [weak self] in
                    self?.say(0); newcomer.play("cheer")
                }
            ),
            (script.myLine + EntranceScript.lineDuration, { [weak self] in self?.hush(0) }),
            (EntranceScript.cardDrop, { [weak self] in self?.showsCard = true }),
            (EntranceScript.countFlip, { [weak self] in self?.countFlipped = true }),
        ]
        for (index, time) in script.cheers.enumerated() {
            let teammate = shown[index]
            events.append(
                (
                    time,
                    { [weak self] in
                        self?.say(index + 1); teammate.play("welcome")
                    }
                ))
            events.append((time + EntranceScript.lineDuration, { [weak self] in self?.hush(index + 1) }))
        }
        for event in events.sorted(by: { $0.time < $1.time }) {
            await wait(until: event.time, from: start)
            guard !Task.isCancelled else { return }
            event.run()
        }
        await wait(until: script.end, from: start)
    }

    /// The squad card's row: the new member, then the teammates, none checked in yet.
    var cardMembers: [SquadMember] {
        guard newcomer != nil else { return [] }
        return (0...teammates.count).map { SquadMember(id: "\($0)", status: .open, isMe: $0 == 0) }
    }

    func player(for member: SquadMember) -> CharacterPlayer? {
        guard let index = Int(member.id) else { return nil }
        return index == 0 ? newcomer?.player : teammates[safe: index - 1]?.player
    }

    private func run(_ newcomer: CastMember) {
        guard let entrance = try? PlaceholderCharacter.entrance() else { return }
        newcomer.play(entrance, blending: false)
        isRunning = true
    }

    private func land() {
        hasLanded = true
        landedAt = .now
    }

    private func say(_ index: Int) { speaking.insert(index) }
    private func hush(_ index: Int) { speaking.remove(index) }

    private func wait(until seconds: Double, from start: Date) async {
        let left = seconds - Date.now.timeIntervalSince(start)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
    }
}

/// The spot's ring on the floor: a dashed hairline while it waits, then a graphite ring drawing
/// itself closed as the new member lands.
private struct LandingRing: View {
    let isClosed: Bool
    let reduceMotion: Bool
    @Environment(\.sceneTheme) private var theme
    private let dash: [CGFloat] = [3, 2]

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(
                    Color(role: .fgMuted, in: theme).opacity(isClosed ? 0 : 0.5),
                    style: StrokeStyle(lineWidth: Sizing.selectionStroke, dash: dash))
            Ellipse()
                .trim(from: 0, to: isClosed ? 1 : 0)
                .stroke(
                    Color(role: .bgBrand, in: theme), style: StrokeStyle(lineWidth: Sizing.ringWidth, lineCap: .round))
        }
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: isClosed)
        .accessibilityHidden(true)
    }
}

/// Paper bits thrown up from the spot on landing, in graphite, ink and white, falling back
/// under gravity and spinning as they go.
private struct Confetti: View {
    let start: Date?
    let origin: CGPoint
    let unit: Double
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Bit {
        let angle: Double
        let speed: Double
        let spin: Double
        let flip: Double
        let life: Double
        let role: ColorRole
    }

    /// The same throw every time, like the design's.
    private static let bits: [Bit] = {
        var seed: UInt64 = 11
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        let roles: [ColorRole] = [.bgBrand, .fgDefault, .bgCanvas]
        return (0..<18).map { index in
            Bit(
                angle: -Double.pi / 2 + (next() - 0.5) * 2.3, speed: 330 + next() * 260, spin: (next() - 0.5) * 1400,
                flip: 8 + next() * 10, life: 1.1 + next() * 0.5, role: roles[index % roles.count])
        }
    }()
    private static let gravity = 900.0
    private static let bitSize = CGSize(width: 7, height: 12)

    var body: some View {
        if let start, !reduceMotion {
            TimelineView(.animation) { timeline in
                Canvas { context, _ in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    for bit in Self.bits where elapsed < bit.life {
                        let left = origin.x + cos(bit.angle) * bit.speed * elapsed * unit
                        let y =
                            origin.y + (sin(bit.angle) * bit.speed * elapsed + Self.gravity * elapsed * elapsed / 2)
                            * unit
                        var piece = context
                        piece.opacity = max(0, 1 - max(0, elapsed - bit.life * 0.6) / (bit.life * 0.4))
                        piece.translateBy(x: left, y: y)
                        piece.rotate(by: .degrees(bit.spin * elapsed))
                        piece.scaleBy(x: cos(elapsed * bit.flip), y: 1)
                        let rect = CGRect(
                            x: -Self.bitSize.width / 2, y: -Self.bitSize.height / 2, width: Self.bitSize.width,
                            height: Self.bitSize.height)
                        piece.fill(
                            Path(rect), with: .color(Color(role: bit.role, in: theme)))
                    }
                }
            }
        }
    }
}

extension Array {
    /// The element at `index`, or nil past the end.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
