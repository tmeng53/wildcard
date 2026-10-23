#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
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

/// The award a character wears: the medal on the chest, the crown dropping onto the head. The
/// rig has no award art yet, so both are drawn over the character, following its torso and head
/// through every move.
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
        let kit: String?
    }

    private struct Dressed {
        let figure: Figure
        let drawing: FigureDrawing
        let idle: BoundClip
    }

    private var dressed: [Key: Dressed] = [:]
    private var clips: [String: BoundClip] = [:]
    private let cast: StoryCast
    private let kits = try? PlaceholderCharacter.sportKits()

    init(cast: StoryCast) {
        self.cast = cast
    }

    /// What a trained day's sport puts on, as the editor and 上场 dress it; none for a sport the
    /// member named themselves.
    func kit(for clip: StoryClip?) -> SportKit? {
        guard case .sport(let sport?) = clip else { return nil }
        return kits?.kit(for: .sport(sport))
    }

    /// Where every part of `member` lands at `time` on the page, the drawing to fill in, and
    /// where its award goes.
    func frame(of member: MemberID, act: Act, kit: SportKit?, at time: Double) -> CharacterFrame? {
        guard let look = cast[member], let dressed = dress(look, kit: kit) else { return nil }
        let placements = dressed.figure.layout(pose(of: look, dressed, act: act, at: time))
        return CharacterFrame(
            drawing: dressed.drawing, placements: placements,
            crown: Self.anchor(.crown, on: dressed.figure, placements),
            medal: Self.anchor(.medal, on: dressed.figure, placements))
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

    private func dress(_ member: StoryMember, kit: SportKit?) -> Dressed? {
        let key = Key(member: member.id, kit: kit?.id)
        if let ready = dressed[key] { return ready }
        let look = kit?.dress(member.look) ?? member.look
        guard let figure = try? PlaceholderCharacter.figure(wearing: look),
            let clip = try? PlaceholderCharacter.clip("idle", persona: member.persona, species: member.species),
            let idle = try? figure.bind(clip)
        else { return nil }
        let ready = Dressed(figure: figure, drawing: FigureDrawing(figure), idle: idle)
        dressed[key] = ready
        return ready
    }

    /// The clip bound to this figure. The art has only the sports' moves so far, so the story's
    /// own (the toss, the stack, eating, dozing, lying flat) play the persona's cheer for now.
    private func bound(_ clip: StoryClip, for member: StoryMember, on figure: Figure) -> BoundClip? {
        let kit = kit(for: clip)
        let key = "\(member.id)/\(clip.name)/\(kit?.id ?? "")"
        if let ready = clips[key] { return ready }
        let persona = member.persona
        let cheer = { try? PlaceholderCharacter.clip("cheer", persona: persona, species: member.species) }
        let loaded: Clip? =
            switch clip {
            case .sport: kit.flatMap { try? PlaceholderCharacter.move(for: $0, persona: persona) } ?? cheer()
            default: cheer()
            }
        guard let loaded, let ready = try? figure.bind(loaded) else { return nil }
        clips[key] = ready
        return ready
    }

    /// The reader leaning out from behind the cloth on the feed's tile: idle, tilted a little.
    static func peeking(_ member: StoryMember) -> (drawing: FigureDrawing, placements: [Placement])? {
        guard let figure = try? PlaceholderCharacter.figure(wearing: member.look),
            let clip = try? PlaceholderCharacter.clip("idle", persona: member.persona, species: member.species),
            let idle = try? figure.bind(clip)
        else { return nil }
        var pose = figure.pose(idle, at: 0.5)
        for part in ["torso", "head"] {
            if let index = figure.parts.firstIndex(where: { $0.id == PartID(part) }) {
                pose.parts[index].rotation -= 8
            }
        }
        return (FigureDrawing(figure), figure.layout(pose))
    }

    /// Where an award sits, in the canvas: the crown's bottom on top of the head, the medal on
    /// the chest, each with the part's turn.
    private enum Award {
        case crown, medal

        var part: PartID { self == .crown ? "head" : "torso" }
        /// The spot on the part at rest, in canvas points (the head's art tops out at 78).
        var spot: Point { self == .crown ? Point(x: 120, y: 78) : Point(x: 120, y: 232) }
    }

    private static func anchor(_ award: Award, on figure: Figure, _ placements: [Placement]) -> CharacterFrame.Anchor? {
        guard let index = figure.parts.firstIndex(where: { $0.id == award.part }), index < placements.count else {
            return nil
        }
        let transform = placements[index].transform
        return CharacterFrame.Anchor(
            point: transform.apply(to: award.spot), degrees: atan2(transform.b, transform.a) * 180 / .pi)
    }
}

/// One character's drawing posed for a moment, and where its crown and medal go.
struct CharacterFrame {
    struct Anchor {
        let point: Point
        let degrees: Double
    }

    let drawing: FigureDrawing
    let placements: [Placement]
    let crown: Anchor?
    let medal: Anchor?
}

/// One character on a page, posed for `time`. Its feet stand on the bottom of the frame's
/// canvas; the caller sizes and places it.
struct StoryCharacter: View {
    let wardrobe: StoryWardrobe
    let member: MemberID
    var act = Act()
    var regalia = Regalia.none
    /// A trained day's kit, worn while its move plays.
    var kit: SportKit?
    let time: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        if let frame = wardrobe.frame(
            of: member, act: reduceMotion ? Act() : act, kit: kit, at: reduceMotion ? 0 : time)
        {
            let worn = reduceMotion ? settled : regalia
            CharacterCanvas(drawing: frame.drawing, placements: frame.placements)
                .aspectRatio(frame.drawing.width / frame.drawing.height, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        let scale = Double(proxy.size.width) / frame.drawing.width
                        if worn.medal, let medal = frame.medal {
                            award("medal.fill", size: Self.medalSize * scale, at: medal, scale: scale)
                                .offset(y: Self.medalSize * scale / 2)
                        }
                        if let fallen = worn.crown, let crown = frame.crown {
                            award("crown.fill", size: Self.crownSize * scale, at: crown, scale: scale)
                                .offset(y: -Self.crownSize * scale / 2 - Self.crownDropHeight * scale * (1 - fallen))
                                .opacity(min(fallen * 6, 1))
                        }
                    }
                }
                .accessibilityHidden(true)
        }
    }

    private func award(_ symbol: String, size: Double, at anchor: CharacterFrame.Anchor, scale: Double) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size))
            .foregroundStyle(Color(role: .fgAccent, in: theme))
            .rotationEffect(.degrees(anchor.degrees))
            .position(x: anchor.point.x * scale, y: anchor.point.y * scale)
    }

    /// The awards' size, and how far above the head the crown starts, in canvas points.
    private static let crownSize = 56.0
    private static let medalSize = 34.0
    private static let crownDropHeight = 260.0

    /// With Reduce Motion the award is simply on.
    private var settled: Regalia {
        Regalia(medal: regalia.medal, crown: regalia.crown.map { _ in 1 })
    }
}

extension View {
    /// Stands a character with its feet at `point`, at `scale` of the rig's canvas.
    func standing(feetAt point: CGPoint, scale: Double) -> some View {
        let width = StoryRig.width * scale
        let height = StoryRig.height * scale
        return frame(width: width, height: height)
            .position(x: point.x, y: point.y - height * StoryRig.feetLine + height / 2)
    }
}

/// The rig's canvas and where its feet stand: the root's pivot, as a share of the height.
private enum StoryRig {
    private static let rig = try? PlaceholderCharacter.rig()
    static let width = rig?.width ?? 240
    static let height = rig?.height ?? 320
    static let feetLine = (rig?.parts.first { $0.id == "root" }?.pivot.y).map { $0 / height } ?? 0.975
}
#endif
