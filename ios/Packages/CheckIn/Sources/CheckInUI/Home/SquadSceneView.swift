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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let cast: SquadCast
    let myPlayer: CharacterPlayer?
    let myRing: RingStatus
    let phase: DayPhase
    /// Whether the member switched the lights on tonight, and their latest pull of the cord.
    let lightsOn: Bool
    let lightsPull: TodayModel.LightsPull?
    /// Bumps on each of my 练了: the ground ring draws, the camera leans in, the streamers fall.
    let celebration: Int
    /// 拍一拍: taps, pats under way and the bubble over a teammate.
    let pats: PatStage
    /// Whether I can still pat a teammate today; else their bubble says 「拍过了」.
    let canPat: (MemberID) -> Bool
    let tapMate: (MemberID) -> Void
    let patMate: (MemberID) -> Void
    /// The squad dropping onto a newly picked scene: nobody is on it until their turn.
    var arrival: TodayModel.Arrival?

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
        let longest =
            cast.sleepers.enumerated().map { index, mate in
                flip.start(ofSleeper: index) + (cast.dozes[mate.id] ?? 0)
            }.max() ?? 0
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
                    NightLayer(lightsOn: lightsOn, pull: playingPull)
                        .frame(width: proxy.size.width, height: Stage.height * unit)
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
                            if arrival == nil, case .mate(let id) = figure.id { tapMate(id) }
                        }
                        // Each teammate is a button by their nickname, for VoiceOver and UI tests.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: nickname(of: figure.id) ?? ""))
                        .accessibilityIdentifier("today.mate")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHidden(nickname(of: figure.id) == nil)
                        .zIndex(figure.depth)
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

    /// Each figure's spot this frame, back to front. Me a little in front of my own row. In a
    /// pat, the one patting turns to the other, who faces the same way, so their reaction's step
    /// back moves away; a tapped teammate hops.
    private func placed(at seconds: Double, date: Date) -> [Placed] {
        let pat = pats.pat
        let sleepers = cast.sleepers.map(\.id)
        var figures = cast.mates.compactMap { mate -> Placed? in
            guard let position = cast.stage.position(of: mate.id, at: seconds) else { return nil }
            let (sleep, sign) = drowse(of: mate, sleeper: sleepers.firstIndex(of: mate.id), at: date)
            return Placed(
                id: .mate(mate.id), player: mate.player, position: position, ring: mate.member.status.ring,
                sleep: sleep, sign: sign, hop: Self.hop(since: pats.hops[mate.id], at: date, scale: position.scale),
                fall: fall(of: mate.id, at: date))
        }
        if let myPlayer {
            figures.append(
                Placed(
                    id: .mine, player: myPlayer,
                    position: .mine,
                    ring: myRing, sleep: 0, sign: 0, hop: 0, fall: fall(of: nil, at: date)))
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

    /// How asleep a teammate looks at `date`, for their "z z", and how much of their 请假条 shows:
    /// at night the sleepers (`sleeper`, their place among them) are asleep with the sign put
    /// away, until the lights wake them; a pull plays out by `LightsFlip`.
    private func drowse(of mate: SquadCast.Mate, sleeper: Int?, at date: Date) -> (sleep: Double, sign: Double) {
        let holdsSign = cast.stage.pose(of: mate.member, at: .day) == .holdingSign
        guard phase == .night, let sleeper else { return (0, holdsSign ? 1 : 0) }
        guard let pull = playingPull else { return (lightsOn ? 0 : 1, lightsOn && holdsSign ? 1 : 0) }
        let flip = LightsFlip(isOn: pull.isOn, reduceMotion: reduceMotion)
        let seconds = date.timeIntervalSince(pull.start)
        return (
            flip.sleep(ofSleeper: sleeper, at: seconds, dozeDuration: cast.dozes[mate.id] ?? 0),
            holdsSign ? flip.sign(ofSleeper: sleeper, at: seconds) : 0
        )
    }

    /// How far into their drop onto a newly picked scene `member` (nil for me) is at `date`, in
    /// seconds: below zero while waiting for their turn; nil once the squad has settled.
    private func fall(of member: MemberID?, at date: Date) -> Double? {
        guard let arrival else { return nil }
        return arrival.elapsed(at: date) - arrival.drop.start(of: arrival.index(of: member))
    }

    /// A teammate's nickname; nil for me and for anyone without one yet.
    private func nickname(of id: Placed.ID) -> String? {
        guard case .mate(let member) = id else { return nil }
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

/// The design's stage: 390 (`StageLayout.width`) by 844 points, the screen it was drawn for.
enum Stage {
    static let height = 844.0

    /// The venue's parts people stand behind, by depth: the tennis net.
    static func fronts(of scene: SceneTheme) -> [Double] {
        scene == .tennis ? [388.5] : []
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
            if figure.sign > 0 {
                SignCard(scale: scale)
                    .position(x: Self.feet.x * scale, y: 249 * scale)
                    .opacity(figure.sign)
            }
            if figure.sleep > 0 {
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

/// The 请假条 a teammate holds up in front of their chest.
private struct SignCard: View {
    @Environment(\.sceneTheme) private var theme
    let scale: Double

    var body: some View {
        Text("请假条", bundle: .module)
            .font(.system(size: 27 * scale, weight: .bold))
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .frame(width: 108 * scale, height: 58 * scale)
            .background(Color(role: .bgCanvas, in: theme), in: card)
            .overlay(card.stroke(Color(role: .fgAccent, in: theme), lineWidth: 4 * scale))
    }

    /// The card as the design draws it in the rig's points: 108 by 58, corners of 9.
    private var card: RoundedRectangle {
        RoundedRectangle(cornerSize: CGSize(width: 9 * scale, height: 9 * scale))
    }
}
#endif

#if os(iOS)
extension StageStatus {
    /// The ring around the head and under the feet: closed once checked in (练了 or 请假条), grey
    /// with the moon on a planned rest day, open otherwise.
    var ring: RingStatus {
        switch self {
        case .trained, .disclaimer: .done
        case .restDay: .restDay
        case .notYet: .open
        }
    }
}
#endif
