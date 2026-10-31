#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import Foundation
import RecapDomain
import SportsUI
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

/// The figures and clips a story plays, built once per member and outfit and kept while the
/// story is open, so a frame only poses and draws.
@MainActor
final class StoryWardrobe {
    private struct Key: Hashable {
        let member: MemberID
        let kit: String?
        let clip: StoryClip?
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

    /// The medal's ribbon: the scene's accent.
    private let ribbon: RGBAColor

    init(cast: StoryCast) {
        self.cast = cast
        let accent = ColorRole.bgAccent.color(in: cast.scene)
        ribbon = RGBAColor(red: accent.red, green: accent.green, blue: accent.blue)
    }

    /// What a trained day's sport puts on, as the editor and 上场 dress it; none for a sport the
    /// member named themselves.
    func kit(for clip: StoryClip?) -> SportKit? {
        guard case .sport(let sport?) = clip else { return nil }
        return kits?.kit(for: .sport(sport), in: SportList.shared.catalog)
    }

    /// Where every part of `member` lands at `time` on the page, wearing `regalia`, and the
    /// drawing to fill in.
    func frame(
        of member: MemberID, act: Act, regalia: Regalia, kit: SportKit?, at time: Double
    ) -> (drawing: FigureDrawing, placements: [Placement])? {
        guard let look = cast[member], let dressed = dress(look, for: act.clip, kit: kit) else { return nil }
        var posed = pose(of: look, dressed, act: act, at: time)
        regalia.dress(&posed, on: dressed.figure)
        return (dressed.drawing, dressed.figure.layout(posed))
    }

    private func pose(of member: StoryMember, _ dressed: Dressed, act: Act, at time: Double) -> Pose {
        let idleTime = time + act.seed
        guard let clip = act.clip, time >= act.start, let move = bound(clip, for: member, on: dressed.figure)
        else {
            return dressed.figure.pose(dressed.idle, at: idleTime)
        }
        if let hold = act.hold, time - act.start >= hold {
            return dressed.figure.pose(move, at: hold)
        }
        var performance = Performance(figure: dressed.figure, idle: dressed.idle, startingAt: -act.seed)
        performance.play(move, at: act.start)
        return performance.pose(at: time)
    }

    /// `member` dressed for the page: the kit for a sport, the food for a meal, and the medal's
    /// ribbon in the scene's accent.
    private func dress(_ member: StoryMember, for clip: StoryClip?, kit: SportKit?) -> Dressed? {
        // Only a meal changes what the look holds, so the rest share one figure.
        let holding: StoryClip? = if case .eat? = clip { clip } else { nil }
        let key = Key(member: member.id, kit: kit?.id, clip: holding)
        if let ready = dressed[key] { return ready }
        var look = holding?.dressing(member.look) ?? kit?.dress(member.look) ?? member.look
        look.colors["medal"] = ribbon
        guard let figure = try? PlaceholderCharacter.figure(wearing: look),
            let clip = try? PlaceholderCharacter.clip("idle", persona: member.persona, species: member.species),
            let idle = try? figure.bind(clip)
        else { return nil }
        let ready = Dressed(figure: figure, drawing: FigureDrawing(figure), idle: idle)
        dressed[key] = ready
        return ready
    }

    /// The clip bound to this figure: a sport's kit move, or the story's own (`StoryClip.art`).
    private func bound(_ clip: StoryClip, for member: StoryMember, on figure: Figure) -> BoundClip? {
        let kit = kit(for: clip)
        let key = "\(member.id)/\(clip.name)/\(kit?.id ?? "")"
        if let ready = clips[key] { return ready }
        let persona = member.persona
        let loaded =
            kit.flatMap { try? PlaceholderCharacter.move(for: $0, persona: persona) }
            ?? (try? clip.art(persona: persona, species: member.species))
        guard let loaded, let ready = try? figure.bind(loaded) else { return nil }
        clips[key] = ready
        return ready
    }

    /// The reader leaning out from behind the cloth on the feed's tile: idle, tilted a little.
    static func peeking(_ member: StoryMember) -> (drawing: FigureDrawing, placements: [Placement])? {
        idle(member, tilt: 8)
    }

    /// The reader standing on their step of the uncovered podium, on the tile of a story they
    /// watched.
    static func standing(_ member: StoryMember) -> (drawing: FigureDrawing, placements: [Placement])? {
        idle(member, tilt: 0)
    }

    private static func idle(_ member: StoryMember, tilt: Double) -> (
        drawing: FigureDrawing, placements: [Placement]
    )? {
        guard let figure = try? PlaceholderCharacter.figure(wearing: member.look),
            let clip = try? PlaceholderCharacter.clip("idle", persona: member.persona, species: member.species),
            let idle = try? figure.bind(clip)
        else { return nil }
        var pose = figure.pose(idle, at: 0.5)
        for part in ["torso", "head"] where tilt != 0 {
            if let index = figure.parts.firstIndex(where: { $0.id == PartID(part) }) {
                pose.parts[index].rotation -= tilt
            }
        }
        return (FigureDrawing(figure), figure.layout(pose))
    }
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

    var body: some View {
        if let frame = wardrobe.frame(
            of: member, act: reduceMotion ? Act() : act, regalia: reduceMotion ? settled : regalia, kit: kit,
            at: reduceMotion ? 0 : time)
        {
            Color.clear
                .aspectRatio(frame.drawing.width / frame.drawing.height, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    GeometryReader { proxy in
                        let scale = Double(proxy.size.width) / frame.drawing.width
                        // Drawn with room around the canvas, so a toss, the stack's jump, lying
                        // flat and the falling crown aren't cut off.
                        CharacterCanvas(drawing: frame.drawing, placements: frame.placements, crop: Self.room)
                            .frame(width: Self.room.width * scale, height: Self.room.height * scale)
                            .offset(x: Self.room.minX * scale, y: Self.room.minY * scale)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    /// The area drawn, in canvas points (`StoryRoom`).
    private static let room = CGRect(
        x: StoryRoom.minX, y: StoryRoom.minY, width: StoryRoom.maxX - StoryRoom.minX,
        height: StoryRoom.maxY - StoryRoom.minY)

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
