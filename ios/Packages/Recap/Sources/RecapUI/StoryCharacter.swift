#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Foundation
import RecapDomain
import SwiftUI

/// What one character does on a page: idle, then `clip` from `start`. A one-shot clip hands
/// back to idle; with `hold`, it stops that far in and stays (lying flat, a pose).
struct Act: Hashable {
    var clip: StoryClip?
    var start: Double = 0
    var hold: Double?
    /// Moves the character's idle along, so a lineup doesn't sway in step.
    var seed: Double = 0
}

/// The award a character wears: the medal on the chest, the crown dropping onto the head. Both
/// ride every move, since they are parts of the rig.
struct Regalia: Hashable {
    var medal = false
    /// How far the crown has fallen, from 0 (out of sight above) to 1 (on the head); nil for none.
    var crown: Double?

    static let none = Regalia()
}

/// The figures and clips a story plays, built once per member and outfit and kept while the
/// story is open, so a frame only poses and draws.
@MainActor
final class StoryWardrobe {
    private struct Key: Hashable {
        let member: MemberID
        let prop: String?
        let regalia: Bool
    }

    private struct Dressed {
        let figure: Figure
        let drawing: FigureDrawing
        let idle: BoundClip
    }

    private var dressed: [Key: Dressed] = [:]
    private var clips: [String: BoundClip] = [:]
    private let cast: StoryCast

    init(cast: StoryCast) {
        self.cast = cast
    }

    /// Where every part of `member` lands at `time` on the page, and the drawing to fill in.
    func frame(of member: MemberID, act: Act, regalia: Regalia, prop: String?, at time: Double)
        -> (drawing: FigureDrawing, placements: [Placement])?
    {
        guard let look = cast[member], let dressed = dress(look, prop: prop, regalia: regalia != .none) else {
            return nil
        }
        var pose = pose(of: look, dressed, act: act, at: time)
        Self.place(regalia, in: dressed.figure, pose: &pose)
        return (dressed.drawing, dressed.figure.layout(pose))
    }

    private func pose(of member: StoryMember, _ dressed: Dressed, act: Act, at time: Double) -> Pose {
        let idleTime = time + act.seed
        guard let clip = act.clip, time >= act.start, let move = bound(clip, for: member, on: dressed.figure) else {
            return dressed.figure.pose(dressed.idle, at: idleTime)
        }
        if let hold = act.hold, time - act.start >= hold {
            return dressed.figure.pose(move, at: hold)
        }
        var performance = Performance(figure: dressed.figure, idle: dressed.idle, startingAt: -act.seed)
        performance.play(move, at: act.start)
        return performance.pose(at: time)
    }

    private func dress(_ member: StoryMember, prop: String?, regalia: Bool) -> Dressed? {
        let key = Key(member: member.id, prop: prop, regalia: regalia)
        if let ready = dressed[key] { return ready }
        var look = member.look
        if let prop { look.variants["prop"] = prop }
        if regalia {
            look.variants[PlaceholderCharacter.medalSlot] = PlaceholderCharacter.gold
            look.variants[PlaceholderCharacter.crownSlot] = PlaceholderCharacter.gold
        }
        guard let figure = try? PlaceholderCharacter.figure(wearing: look),
            let idle = try? figure.bind(
                PlaceholderCharacter.clip("idle", persona: member.persona, species: member.species))
        else { return nil }
        let ready = Dressed(figure: figure, drawing: FigureDrawing(figure), idle: idle)
        dressed[key] = ready
        return ready
    }

    /// The clip bound to this figure; a move the art doesn't have yet plays the persona's cheer.
    private func bound(_ clip: StoryClip, for member: StoryMember, on figure: Figure) -> BoundClip? {
        let key = "\(member.id)/\(member.persona.rawValue)/\(clip.name)"
        if let ready = clips[key] { return ready }
        let persona = member.persona
        let cheer = { try? PlaceholderCharacter.clip("cheer", persona: persona, species: member.species) }
        let loaded: Clip? =
            switch clip {
            case .award(.cheer): cheer()
            // Each persona eats its own way, with its own food; a full belly until those land.
            case .eat:
                (try? PlaceholderCharacter.move("\(clip.name)-\(persona.rawValue)"))
                    ?? (try? PlaceholderCharacter.move("fullbelly"))
            default: (try? PlaceholderCharacter.move(clip.name)) ?? cheer()
            }
        guard let loaded, let ready = try? figure.bind(loaded) else { return nil }
        clips[key] = ready
        return ready
    }

    /// The reader leaning out from behind the cloth on the feed's tile: idle, tilted a little.
    static func peeking(_ member: StoryMember) -> (drawing: FigureDrawing, placements: [Placement])? {
        guard let figure = try? PlaceholderCharacter.figure(wearing: member.look),
            let idle = try? figure.bind(
                PlaceholderCharacter.clip("idle", persona: member.persona, species: member.species))
        else { return nil }
        var pose = figure.pose(idle, at: 0.5)
        for part in ["torso", "head"] {
            if let index = figure.parts.firstIndex(where: { $0.id == PartID(part) }) {
                pose.parts[index].rotation -= 8
            }
        }
        return (FigureDrawing(figure), figure.layout(pose))
    }

    /// Hides what isn't won yet and drops the crown from above the head.
    private static func place(_ regalia: Regalia, in figure: Figure, pose: inout Pose) {
        if let medal = figure.parts.firstIndex(where: { $0.id == PlaceholderCharacter.medalPart }) {
            pose.parts[medal].opacity = regalia.medal ? 1 : 0
        }
        if let crown = figure.parts.firstIndex(where: { $0.id == PlaceholderCharacter.awardPart }) {
            let fallen = regalia.crown ?? 0
            pose.parts[crown].opacity = regalia.crown == nil ? 0 : min(fallen * 6, 1)
            pose.parts[crown].y -= crownDropHeight * (1 - fallen)
        }
    }

    /// How far above the head the crown starts, in canvas points.
    private static let crownDropHeight = 260.0
}

/// One character on a page, posed for `time`. Its feet stand on the bottom of the frame's
/// canvas; the caller sizes and places it.
struct StoryCharacter: View {
    let wardrobe: StoryWardrobe
    let member: MemberID
    var act = Act()
    var regalia = Regalia.none
    var prop: String?
    let time: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let frame = wardrobe.frame(
            of: member, act: reduceMotion ? Act() : act, regalia: reduceMotion ? settled : regalia, prop: prop,
            at: reduceMotion ? 0 : time)
        {
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                .aspectRatio(frame.drawing.width / frame.drawing.height, contentMode: .fit)
                .accessibilityHidden(true)
        }
    }

    /// With Reduce Motion the award is simply on.
    private var settled: Regalia {
        Regalia(medal: regalia.medal, crown: regalia.crown.map { _ in 1 })
    }
}

extension View {
    /// Stands a character with its feet at `point`, at `scale` of the rig's canvas.
    func standing(feetAt point: CGPoint, scale: Double) -> some View {
        let width = PlaceholderCharacter.canvas.width * scale
        let height = PlaceholderCharacter.canvas.height * scale
        return frame(width: width, height: height)
            .position(x: point.x, y: point.y - height * PlaceholderCharacter.feetLine + height / 2)
    }
}
#endif
