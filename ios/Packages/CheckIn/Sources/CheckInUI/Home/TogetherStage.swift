#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import Foundation
import Observation

/// The squad celebrating together on the home scene (`SquadCelebration`, the moves approved on
/// 2026-10-20): two teammates bumping heads (or a 社恐 dodging it), one hopping onto the other's
/// head when they did the same sport, the whole squad jumping in turn when the week's goal is
/// reached. For a pair, the one who starts it walks over beside the other, they play their parts,
/// and it walks back to its own spot; the other stays where it was. Everyone else carries on.
@MainActor @Observable
final class TogetherStage {
    /// Whether the squad celebrates at all: everywhere but the sample squad's UI tests that don't
    /// ask for it, so they meet a home that holds still.
    let isOn: Bool

    init(isOn: Bool = true) { self.isOn = isOn }

    /// Someone's part in what plays.
    struct Part: Equatable {
        let figure: PatStage.Figure
        let clip: Clip
        /// When their clip starts, in seconds from the start.
        let starts: Double
        /// Where they stand while their clip plays; nil to stay on their own spot.
        let spot: StagePosition?
        /// Where their clip leaves them (叠罗汉's top lands on the far side); nil for `spot`.
        let end: StagePosition?

        static func == (lhs: Part, rhs: Part) -> Bool {
            lhs.figure == rhs.figure && lhs.starts == rhs.starts && lhs.spot == rhs.spot && lhs.end == rhs.end
        }
    }

    /// A celebration under way, from its first frame.
    struct Playing: Equatable {
        let kind: SquadCelebration.Kind
        let parts: [Part]
        let start: Date
        let duration: Double
    }

    private(set) var playing: Playing?

    /// How long walking over to the other one takes, and back.
    nonisolated static let walk = 0.7
    /// How far apart two heads bump, and how far the 叠罗汉's bottom one stands from the top
    /// one, in the rig's points (`Interaction`'s offsets for the moves that have them).
    nonisolated static let bumpApart = 200.0
    /// Just below where the squad's card ends over the scene, in stage points (the design's 390 × 844 home):
    /// the 叠罗汉 plays low enough that its top one's jump stays below it.
    nonisolated static let cardBottom = 300.0
    /// How far above the bottom one's feet the 叠罗汉's top one reaches, in the rig's points: its
    /// jump (`stack-top`'s 300) and its own height on the 240-point canvas.
    nonisolated static let stackReach = 540.0
    /// From one teammate's jump to the next in the wave, left to right.
    nonisolated static let waveStagger = 0.14
    /// How high each step of the walk bobs, in the rig's points.
    nonisolated static let stepHeight = 24.0
    /// Steps a second while walking.
    nonisolated static let stepsPerSecond = 3.0

    /// Plays `celebration` with the figures on the scene (`spots`: where each one stands now,
    /// with its player and persona). Says whether it started; it doesn't while another plays or
    /// someone in it isn't on the scene.
    @discardableResult
    func play(
        _ celebration: SquadCelebration, myself: MemberID,
        figures: [PatStage.Figure: (player: CharacterPlayer, persona: Persona, spot: StagePosition)], now: Date = .now
    ) -> Bool {
        guard playing == nil, let parts = try? Self.parts(of: celebration, myself: myself, figures: figures),
            !parts.isEmpty
        else { return false }
        let duration =
            parts.map { part in
                part.starts + part.clip.duration + (part.spot == nil ? 0 : Self.walk)
            }.max() ?? 0
        let current = Playing(kind: celebration.kind, parts: parts, start: now, duration: duration)
        playing = current
        for part in parts {
            guard let player = figures[part.figure]?.player else { continue }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(part.starts))
                try? player.play(part.clip, now: now.addingTimeInterval(part.starts))
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            if self?.playing == current { self?.playing = nil }
        }
        return true
    }

    /// Whether `figure` plays a part that leaves its canvas far behind (叠罗汉's top one, up on
    /// the other's head), so it is drawn with the room `PlaceholderCharacter.stackReachAbove` asks.
    func reachesHigh(_ figure: PatStage.Figure) -> Bool {
        guard let playing, playing.kind == .stack else { return false }
        return playing.parts.contains { $0.figure == figure }
    }

    /// Where `figure` stands at `date`: on its own spot (`home`, where it would be now), or on
    /// its way to or from its place in the celebration, bobbing with each step (`bob`, in the
    /// stage's points at its scale, as `Placed.hop` takes it).
    func position(of figure: PatStage.Figure, home: StagePosition, at date: Date) -> (StagePosition, bob: Double) {
        let (position, bob) = walk(of: figure, home: home, at: date)
        return (position, bob * position.scale)
    }

    /// `position(of:home:at:)` with the bob in the rig's points.
    private func walk(of figure: PatStage.Figure, home: StagePosition, at date: Date) -> (StagePosition, bob: Double) {
        guard let playing, let part = playing.parts.first(where: { $0.figure == figure }), let spot = part.spot
        else { return (home, 0) }
        let elapsed = date.timeIntervalSince(playing.start)
        let movesEnd = part.starts + part.clip.duration
        guard elapsed >= 0, elapsed < movesEnd + Self.walk else { return (home, 0) }
        if elapsed < part.starts {
            let walked = min(1, elapsed / Self.walk)
            return (Self.between(home, spot, Self.ease(walked)), Self.bob(elapsed, walking: walked < 1))
        }
        let end = part.end ?? spot
        if elapsed < movesEnd { return (spot, 0) }
        let back = (elapsed - movesEnd) / Self.walk
        return (Self.between(end, home, Self.ease(back)), Self.bob(elapsed - movesEnd, walking: true))
    }

    // MARK: Staging

    /// Each part: who plays what, when and where.
    private static func parts(
        of celebration: SquadCelebration, myself: MemberID,
        figures: [PatStage.Figure: (player: CharacterPlayer, persona: Persona, spot: StagePosition)]
    ) throws(AvatarError) -> [Part] {
        func figure(_ id: MemberID) -> PatStage.Figure { id == myself ? .mine : .mate(id) }
        switch celebration {
        case .wave:
            let jumpers = figures.sorted { $0.value.spot.point.x < $1.value.spot.point.x }
            var parts: [Part] = []
            for (index, entry) in jumpers.enumerated() {
                parts.append(
                    Part(
                        figure: entry.key,
                        clip: try PlaceholderCharacter.clip(for: .wave, persona: entry.value.persona),
                        starts: Double(index) * waveStagger, spot: nil, end: nil))
            }
            return parts
        case .bump(let mine, let mate, let dodged):
            guard let starter = figures[figure(mine)], let other = figures[figure(mate)] else { return [] }
            if dodged {
                let roles = try PlaceholderCharacter.bumpDodged().roles
                return pair(
                    starter: (figure(mine), roles[0].clip, starter.spot),
                    other: (figure(mate), roles[1].clip, other.spot),
                    apart: roles[1].offset, facingEachOther: false)
            }
            return try pair(
                starter: (figure(mine), PlaceholderCharacter.clip(for: .bump, persona: starter.persona), starter.spot),
                other: (figure(mate), PlaceholderCharacter.clip(for: .bump, persona: other.persona), other.spot),
                apart: bumpApart, facingEachOther: true)
        case .stack(let top, let bottom):
            guard let starter = figures[figure(top)], let other = figures[figure(bottom)] else { return [] }
            let roles = try PlaceholderCharacter.stack().roles
            return pair(
                starter: (figure(top), roles[0].clip, starter.spot), other: (figure(bottom), roles[1].clip, other.spot),
                apart: roles[1].offset, facingEachOther: false, landsAt: PlaceholderCharacter.stackTopLandsAt,
                below: cardBottom, reach: stackReach)
        }
    }

    /// Two figures: the starter walks to `apart` rig points from the other, on its own side,
    /// and both play their clips once it is there. They face each other, or both face the way
    /// the starter walked (the moves are drawn facing right, the other one on the right). With
    /// `below`, a move reaching `reach` rig points above the other's feet stays below that depth:
    /// an other standing too far back (on the treadmills, under the squad's card) steps forward
    /// to the nearest depth where it does, as the starter walks over.
    private static func pair(
        starter: (figure: PatStage.Figure, clip: Clip, spot: StagePosition),
        other: (figure: PatStage.Figure, clip: Clip, spot: StagePosition),
        apart: Double, facingEachOther: Bool, landsAt: Double? = nil, below: Double? = nil, reach: Double = 0
    ) -> [Part] {
        let from = starter.spot
        let target = below.map { clearOf($0, reach: reach, from: other.spot) } ?? other.spot
        let direction: Double = from.point.x <= target.point.x ? 1 : -1
        let stand = StagePosition(
            point: StagePoint(x: target.point.x - direction * apart * target.scale, y: target.point.y),
            facing: direction,
            scale: target.scale)
        let end = landsAt.map { distance in
            StagePosition(
                point: StagePoint(x: stand.point.x + direction * distance * target.scale, y: target.point.y),
                facing: direction, scale: target.scale)
        }
        return [
            Part(figure: starter.figure, clip: starter.clip, starts: walk, spot: stand, end: end),
            Part(
                figure: other.figure, clip: other.clip, starts: walk,
                spot: target.facing(facingEachOther ? -direction : direction), end: nil),
        ]
    }

    /// `spot`, or straight in front of it at the first depth where a figure there reaching
    /// `reach` rig points up stays below `top`.
    private static func clearOf(_ top: Double, reach: Double, from spot: StagePosition) -> StagePosition {
        var depth = spot.point.y
        while depth - reach * StageLayout.scale(atDepth: depth) < top { depth += 1 }
        guard depth > spot.point.y else { return spot }
        return StagePosition(
            point: StagePoint(x: spot.point.x, y: depth), facing: spot.facing, scale: StageLayout.scale(atDepth: depth))
    }

    private static func between(_ from: StagePosition, _ target: StagePosition, _ amount: Double) -> StagePosition {
        let point = StagePoint(
            x: from.point.x + (target.point.x - from.point.x) * amount,
            y: from.point.y + (target.point.y - from.point.y) * amount)
        // Facing the way it walks; one that waits where it stands keeps its own way until it turns.
        let facing: Double
        if amount >= 1 {
            facing = target.facing
        } else if target.point.x == from.point.x {
            facing = from.facing
        } else {
            facing = target.point.x > from.point.x ? 1 : -1
        }
        return StagePosition(
            point: point, facing: facing, scale: from.scale + (target.scale - from.scale) * amount)
    }

    /// Eases in and out, so a walk starts and stops softly.
    private static func ease(_ amount: Double) -> Double {
        let clamped = min(max(amount, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private static func bob(_ seconds: Double, walking: Bool) -> Double {
        guard walking else { return 0 }
        return abs(sin(seconds * stepsPerSecond * .pi)) * stepHeight
    }
}
#endif
