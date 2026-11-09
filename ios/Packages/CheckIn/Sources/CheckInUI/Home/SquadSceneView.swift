#if os(iOS)
import AvatarArt
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The squad's scene, full screen: the venue's art, every teammate where `SquadStage` puts them,
/// me front and centre, the status rings on the ground, and the dark at night, until the lights
/// are switched on (开灯). Positions are the design's 390-point-wide stage, scaled to the
/// screen's width.
struct SquadSceneView: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    let cast: SquadCast
    let myPlayer: CharacterPlayer?
    let myRing: RingStatus
    /// Whether I sleep at night, as a teammate does who isn't training or eating, and whether I
    /// hold up a 请假条 by day.
    var iSleep = false
    var iHoldSign = false
    /// How long my doze lasts after the lights went off.
    var myDoze = 0.0
    let phase: DayPhase
    /// Whether the member switched the lights on tonight, and their latest pull of the cord.
    let lightsOn: Bool
    let lightsPull: TodayModel.LightsPull?
    /// Bumps on each of my 练了: the ground ring draws, the camera leans in, the streamers fall.
    let celebration: Int
    /// 拍一拍: taps, pats under way and the bubble over a teammate.
    let pats: PatStage
    /// The squad celebrating together: who walks where and when.
    let together: TogetherStage
    /// Whether I can still pat a teammate today; else their bubble says 「拍过了」.
    let canPat: (MemberID) -> Bool
    let tapMate: (MemberID) -> Void
    /// I tapped my own character: it plays its signature move and my card opens.
    let tapMe: () -> Void
    let patMate: (MemberID) -> Void
    /// The squad dropping onto a newly picked scene: nobody is on it until their turn.
    var arrival: TodayModel.Arrival?
    /// I tapped the coach on the sideline: its page opens.
    var tapCoach: () -> Void = {}
    /// Whether the coach's page has a card not seen yet (its phone shows it), and where it stands
    /// on screen.
    var coachHasNews = false
    var coachAt: (CGPoint) -> Void = { _ in }
    /// I tapped the coach's empty spot, there while the squad has no coach: 教练招聘会 opens.
    var tapVacancy: () -> Void = {}
    /// The home's clock, which the coaches changing places (换教练) play against.
    var clock: () -> Date = Date.init

    /// The pull whose wake-up (or doze) has played out, after which the scene stops redrawing
    /// for it under Reduce Motion.
    @State private var settledPull: TodayModel.LightsPull?

    /// The lights' pull while it is still playing.
    private var playingPull: TodayModel.LightsPull? {
        guard let lightsPull, lightsPull != settledPull, lightsPull.isOn == lightsOn else { return nil }
        return lightsPull
    }

    /// How long a pull plays at least: the last sleeper's wake-up and their 请假条 coming back.
    private static let pullPlays = 4.0
    /// How long `pull` plays: switched off, until the slowest doze is over and its "z z" are back.
    private func plays(_ pull: TodayModel.LightsPull) -> Double {
        guard !pull.isOn else { return Self.pullPlays }
        let flip = LightsFlip(isOn: false, reduceMotion: reduceMotion)
        let mates = cast.sleepers.enumerated().map { index, mate in
            flip.start(ofSleeper: index) + (cast.dozes[mate.id] ?? 0)
        }
        let mine = iSleep ? [flip.start(ofSleeper: cast.sleepers.count) + myDoze] : []
        let longest = (mates + mine).max() ?? 0
        return max(Self.pullPlays, longest + LightsFlip.fade)
    }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / StageLayout.width
            ZStack(alignment: .topLeading) {
                SceneArt(scene: theme, layer: .day)
                    .frame(width: proxy.size.width, height: Stage.height * unit)
                    // A tap on the scene itself closes a teammate's bubble.
                    .contentShape(Rectangle())
                    .onTapGesture { pats.dismissBubble() }
                cast(unit: unit)
                if phase == .night {
                    NightLayer(lightsOn: lightsOn, pull: playingPull, artHeight: Stage.height * unit)
                        .frame(width: proxy.size.width, height: max(proxy.size.height, Stage.height * unit))
                        .allowsHitTesting(false)
                }
                CheerBubbles(cast: cast, unit: unit)
                if phase == .night { WokenLine(cast: cast, pull: playingPull, unit: unit) }
                PatOverlay(layer: .marks, cast: cast, pats: pats, unit: unit, canPat: canPat, pat: patMate)
                Streamers(trigger: celebration)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .keyframeAnimator(initialValue: 1.0, trigger: celebration) { content, zoom in
                content.scaleEffect(
                    reduceMotion ? 1 : zoom,
                    anchor: UnitPoint(x: 0.5, y: StageLayout.mySpot.y / Stage.height))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1, duration: Motion.ringFill)
                    CubicKeyframe(Self.lean, duration: 0.23)
                    CubicKeyframe(1, duration: 0.42)
                }
            }
        }
        .background(Color(role: .bgSubtle, in: theme))
        .clipped()
        .task(id: lightsPull) {
            guard let lightsPull else { return }
            try? await Task.sleep(for: .seconds(plays(lightsPull) - Date.now.timeIntervalSince(lightsPull.start)))
            guard !Task.isCancelled else { return }
            settledPull = lightsPull
        }
    }

    /// How far the camera leans in when my ring closes.
    private static let lean = 1.045

    /// Everyone, back to front, redrawn each display frame so runners and swimmers move.
    private func cast(unit: Double) -> some View {
        // Under Reduce Motion it redraws only while a pull of the lights crossfades.
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion && playingPull == nil)) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let figures = placed(at: reduceMotion ? 0 : seconds, date: timeline.date)
            ZStack(alignment: .topLeading) {
                ForEach(figures) { figure in
                    StageFigure(figure: figure, unit: unit, date: timeline.date, reduceMotion: reduceMotion)
                        .onTapGesture {
                            guard arrival == nil else { return }
                            switch figure.id {
                            case .mate(let id): tapMate(id)
                            case .mine: tapMe()
                            }
                        }
                        // Each teammate is a button by their nickname, and I am one by 我, for VoiceOver and UI tests.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: nickname(of: figure.id) ?? ""))
                        .accessibilityIdentifier(figure.id == .mine ? "today.me" : "today.mate")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHidden(nickname(of: figure.id) == nil)
                        .zIndex(figure.depth)
                }
                sidelineCoach(unit: unit, date: timeline.date)
                // Nobody drops into the empty spot: it shows once the squad stands.
                if let spot = cast.vacancy, coachFall(at: timeline.date) >= 0 {
                    SidelineVacancy(spot: spot, unit: unit, tap: tapVacancy)
                        .zIndex(spot.y)
                }
                ForEach(Array(Stage.fronts(of: theme).enumerated()), id: \.offset) { index, depth in
                    SceneArt(scene: theme, layer: .front(index))
                        .frame(width: StageLayout.width * unit, height: Stage.height * unit)
                        .allowsHitTesting(false)
                        .zIndex(depth)
                }
            }
        }
    }

    /// Each figure's spot this frame, back to front, me a little in front of my row. In a pat, the
    /// patter turns to the other, who faces the same way (their step back moves away); a tapped one hops.
    private func placed(at seconds: Double, date: Date) -> [Placed] {
        let pat = pats.pat
        let sleepers = cast.sleepers.map(\.id)
        var figures = cast.mates.compactMap { mate -> Placed? in
            guard let spot = cast.stage.position(of: mate.id, at: seconds) else { return nil }
            let (position, bob) = together.position(of: .mate(mate.id), home: spot, at: date)
            let (sleep, sign) = drowse(
                holdsSign: cast.stage.pose(of: mate.member, at: .day) == .holdingSign,
                sleeper: sleepers.firstIndex(of: mate.id), doze: cast.dozes[mate.id] ?? 0, at: date)
            let hop = Self.hop(since: pats.hops[mate.id], at: date, scale: position.scale) + bob
            return Placed(
                id: .mate(mate.id), player: mate.player, position: position, ring: mate.member.status.ring,
                sleep: sleep, sign: sign, hop: hop, fall: fall(of: mate.id, at: date))
        }
        if let myPlayer {
            let (position, bob) = together.position(of: .mine, home: .mine, at: date)
            // I sleep after the last of the squad, and wake after them.
            let (sleep, sign) = drowse(
                holdsSign: iHoldSign, sleeper: iSleep ? sleepers.count : nil, doze: myDoze, at: date)
            figures.append(
                Placed(
                    id: .mine, player: myPlayer, position: position,
                    ring: myRing, sleep: sleep, sign: sign, hop: bob, fall: fall(of: nil, at: date)))
        }
        // Under Reduce Motion everyone is simply there.
        if arrival != nil, !reduceMotion {
            figures.removeAll { $0.fall.map { $0 < 0 } ?? false }
        }
        guard let pat, date.timeIntervalSince(pat.start) < pat.duration,
            let patter = figures.first(where: { $0.id == pat.patter.placed }),
            let patted = figures.first(where: { $0.id == pat.patted.placed })
        else { return figures }
        let direction: Double = patted.position.point.x >= patter.position.point.x ? 1 : -1
        return figures.map { figure in
            guard figure.id == patter.id || figure.id == patted.id else { return figure }
            // Both face the same way, so the reaction's step back moves away from me. A sleeper
            // wakes for it, and drops back off after.
            return figure.turned(direction, awake: figure.id == patted.id)
        }
    }

    /// How asleep someone looks at `date`, for their "z z", and how much of their 请假条 shows:
    /// at night the sleepers (`sleeper`, their place among them) are asleep with the sign put
    /// away, until the lights wake them; a pull plays out by `LightsFlip`, their "z z" coming
    /// back `doze` seconds after the lights go off.
    private func drowse(holdsSign: Bool, sleeper: Int?, doze: Double, at date: Date) -> (sleep: Double, sign: Double) {
        guard phase == .night, let sleeper else { return (0, holdsSign ? 1 : 0) }
        guard let pull = playingPull else { return (lightsOn ? 0 : 1, lightsOn && holdsSign ? 1 : 0) }
        let flip = LightsFlip(isOn: pull.isOn, reduceMotion: reduceMotion)
        let seconds = date.timeIntervalSince(pull.start)
        return (
            flip.sleep(ofSleeper: sleeper, at: seconds, dozeDuration: doze),
            holdsSign ? flip.sign(ofSleeper: sleeper, at: seconds) : 0
        )
    }

    /// How far into their drop onto a newly picked scene `member` (nil for me) is at `date`, in
    /// seconds: below zero while waiting for their turn; nil once the squad has settled.
    private func fall(of member: MemberID?, at date: Date) -> Double? {
        guard let arrival else { return nil }
        return arrival.elapsed(at: date) - arrival.drop.start(of: arrival.index(of: member))
    }

    /// A teammate's nickname, or 我 for me; nil for anyone without one yet.
    private func nickname(of id: Placed.ID) -> String? {
        guard case .mate(let member) = id else { return String(copy: "我", bundle: .module) }
        return cast.mates.first { $0.id == member }?.name
    }

    /// How high a tapped teammate is in their hop, in stage points.
    private static func hop(since start: Date?, at date: Date, scale: Double) -> Double {
        guard let start else { return 0 }
        let elapsed = date.timeIntervalSince(start)
        guard elapsed >= 0, elapsed < PatStage.hop.duration else { return 0 }
        return sin(elapsed / PatStage.hop.duration * .pi) * PatStage.hop.height * scale / 0.25
    }
}

/// A figure on the stage this frame.
private struct Placed: Identifiable {
    enum ID: Hashable {
        case mine
        case mate(MemberID)
    }

    let id: ID
    let player: CharacterPlayer
    let position: StagePosition
    let ring: RingStatus
    /// How asleep they look, 0 to 1: their "z z".
    let sleep: Double
    /// How much of their 请假条 shows, 0 to 1.
    let sign: Double
    /// How high off the ground a tap's hop has them, in stage points.
    let hop: Double
    /// How far into their drop onto a newly picked scene they are, in seconds.
    let fall: Double?

    var depth: Double { position.point.y + (id == .mine ? 50 : 0) }

    func turned(_ direction: Double, awake: Bool) -> Placed {
        Placed(
            id: id, player: player, position: position.facing(direction), ring: ring, sleep: awake ? 0 : sleep,
            sign: sign, hop: hop, fall: fall)
    }
}

extension PatStage.Figure {
    fileprivate var placed: Placed.ID {
        switch self {
        case .mine: .mine
        case .mate(let id): .mate(id)
        }
    }
}

/// One character with its ring on the ground, its 请假条 or its sleep.
private struct StageFigure: View {
    @Environment(\.sceneTheme) private var theme
    let figure: Placed
    let unit: Double
    let date: Date
    let reduceMotion: Bool

    /// The rig's canvas and where its feet are on it.
    private static let canvas = CGSize(width: 240, height: 320)
    private static let feet = CGPoint(x: 120, y: 316)
    /// The canvas with the room a pat's moves reach into, in the rig's points.
    private static let reach = CGRect(
        x: -PlaceholderCharacter.patReachSideways, y: -PlaceholderCharacter.patReachAbove,
        width: canvas.width + 2 * PlaceholderCharacter.patReachSideways,
        height: canvas.height + PlaceholderCharacter.patReachAbove + PlaceholderCharacter.patReachBelow)
    /// The canvas with the room the drop starts in, 420 rig points above it, while it falls.
    private static let fallReach = CGRect(
        x: reach.minX, y: -fallRoom, width: reach.width, height: reach.maxY + fallRoom)
    /// The room above the canvas while falling: the drop's height and a little air for the head.
    private static let fallRoom = PlaceholderCharacter.dropHeight + 20

    /// Still in the air, before the drop touches down.
    private var isFalling: Bool { figure.fall.map { $0 < DropIn.land } ?? false }

    var body: some View {
        let scale = figure.position.scale * unit
        let point = figure.position.point
        let frame = reduceMotion ? figure.player.restFrame : figure.player.frame(at: date)
        let falling = isFalling && !reduceMotion
        let crop = falling ? Self.fallReach : Self.reach
        let lift =
            falling
            ? DropIn.lift(
                at: figure.fall ?? 0, spotY: point.y, clipLift: PlaceholderCharacter.dropHeight * figure.position.scale)
            : 0
        ZStack {
            if !falling {
                GroundRing(ring: figure.ring, scale: scale, unit: unit)
                    .position(x: Self.feet.x * scale, y: Self.feet.y * scale - 2 * unit)
            }
            // Drawn with room around the canvas for moves that reach past it (a pat's reaction
            // staggering back, the drop from above), laid out at the canvas's size so everything
            // else stays put.
            Color.clear.overlay {
                CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: crop)
                    .frame(width: crop.width * scale, height: crop.height * scale)
                    .offset(y: (crop.midY - Self.canvas.height / 2) * scale)
            }
            .scaleEffect(x: figure.position.facing, y: 1)
            .offset(y: -(figure.hop + lift) * unit)
            .allowsHitTesting(false)
            if figure.sign > 0, !falling {  // A sign and sleep wait for the figure to land.
                SignCard(scale: scale)
                    .position(x: Self.feet.x * scale, y: 249 * scale)
                    .opacity(figure.sign)
            }
            if figure.sleep > 0, !falling {
                Text(verbatim: "z z")
                    .font(.system(size: 60 * scale, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(role: .fgOnScene, in: theme).opacity(0.85 * figure.sleep))
                    .position(x: 170 * scale, y: 60 * scale)
            }
        }
        .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
        .contentShape(Rectangle())
        .position(
            x: point.x * unit,
            y: point.y * unit - (Self.feet.y - Self.canvas.height / 2) * scale)
    }
}

/// The status ring on the ground under a character's feet, the same rule as the head rings in
/// the card: in the scene's ring colour once checked in, thin and grey on a rest day. When it
/// turns checked in on screen it draws itself clockwise, like the card's ring. Its size follows
/// the character (`scale`); its line stays the same on everyone (`unit`, one stage point).
private struct GroundRing: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let ring: RingStatus
    let scale: Double
    let unit: Double
    @State private var drawn: Double?

    var body: some View {
        let shape = Ellipse()
        ZStack {
            switch ring {
            case .done:
                shape.trim(from: 0, to: drawn ?? 1)
                    .stroke(Color(role: .ring, in: theme), style: StrokeStyle(lineWidth: 3 * unit, lineCap: .round))
            case .restDay:
                shape.stroke(Color(role: .borderDefault, in: theme), lineWidth: 1.6 * unit)
            case .open:
                EmptyView()
            }
        }
        // The design's ellipse: 105 by 36 rig points around the feet.
        .frame(width: 210 * scale, height: 71.4 * scale)
        .onChange(of: ring) { _, new in
            guard new == .done, !reduceMotion else { return }
            drawn = 0
            withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: Motion.ringFill)) { drawn = 1 }
        }
        .allowsHitTesting(false)
    }
}
#endif
