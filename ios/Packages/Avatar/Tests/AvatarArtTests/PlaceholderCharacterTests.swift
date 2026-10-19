import AvatarArt
import AvatarDomain
import AvatarLooks
import Foundation
import Testing

/// The bundled files load and fit together, so a broken edit to them fails here, not on a phone.
@Test(arguments: Looks.squad)
func everyOutfitBuilds(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    #expect(
        figure.parts.map(\.id.rawValue) == [
            "shadow", "root", "tail", "legL", "legR", "torso", "head", "eyes", "brows", "glasses", "mouthSmile",
            "mouthOpen", "propR", "armL", "armR",
        ])
    // Only the bear's hands are free, and only the cat has a tail.
    #expect(figure.parts[12].art.count == (outfit == Looks.bear ? 0 : 1))
    #expect(figure.parts[2].art.count == (outfit == Looks.cat ? 1 : 0))
    // Everyone has eyes and both mouths; only people pick brows.
    #expect([7, 10, 11].allSatisfy { figure.parts[$0].art.count == 1 })
    let people = try PlaceholderCharacter.editorChoices().species.filter(\.wearsHair).flatMap(\.bodies)
    let isPerson = people.contains(outfit.variants["body"] ?? "")
    #expect(figure.parts[8].art.count == (isPerson ? 1 : 0))
    // The open mouth waits hidden until the cheer swaps it in.
    #expect(figure.layout(figure.restPose)[11].opacity == 0)
}

/// Every body and hair the editor can offer, by folder name.
@Test func variantsListTheBundledArt() {
    #expect(
        PlaceholderCharacter.variants(for: "body") == [
            "bear", "bichon", "calico", "cat", "collie", "corgi", "dutch", "golden", "husky", "lihua", "lop",
            "orangewhite", "peach", "rabbit", "ragdoll", "shiba", "siamese", "tortie", "tuxedo",
        ])
    #expect(
        PlaceholderCharacter.variants(for: "hair") == [
            "bob", "bun", "buzz", "curls", "curtain", "long", "pigtails", "ponytail", "spacebuns", "wolf",
        ])
    #expect(PlaceholderCharacter.variants(for: "eyes") == ["dot", "happy", "round", "sharp", "sleepy", "sparkle"])
    #expect(PlaceholderCharacter.variants(for: "brows") == ["arched", "bold", "soft", "worried"])
    #expect(PlaceholderCharacter.variants(for: "mouth") == ["cat", "grin", "oh", "smile", "smirk"])
    #expect(PlaceholderCharacter.variants(for: "cheeks") == ["flushed", "freckles", "rosy"])
    #expect(PlaceholderCharacter.variants(for: "glasses") == ["round", "square"])
    #expect(PlaceholderCharacter.variants(for: "cape").isEmpty)
}

/// A cat leaves its face out and still gets round eyes and a smile; a person can pick others.
@Test func looksWithoutAFaceWearTheDefaultOne() throws {
    let cat = try PlaceholderCharacter.figure(wearing: Looks.cat)
    let plain = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "eyes": "round", "mouth": "smile"]))
    let bare = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach"]))
    #expect(cat.parts[7].art == plain.parts[7].art)
    #expect(bare.parts[7].art == plain.parts[7].art && bare.parts[10].art == plain.parts[10].art)
    let athlete = try PlaceholderCharacter.figure(wearing: Looks.athlete)
    #expect(athlete.parts[7].art != plain.parts[7].art && athlete.parts[10].art != plain.parts[10].art)
}

@Test(arguments: wardrobe)
func everyLookBuilds(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    #expect(figure.parts.count == 15)
}

@Test(arguments: Persona.allCases)
func everyPersonaHasAnIdleAndACheer(persona: Persona) throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let idle = try figure.bind(PlaceholderCharacter.clip("idle", persona: persona))
    let cheer = try figure.bind(PlaceholderCharacter.clip("cheer", persona: persona))
    #expect(idle.clip.name == "idle" && idle.clip.loops)
    #expect(cheer.clip.name == "cheer" && !cheer.clip.loops)
    // The idle loop's last frame is its first, so the loop has no visible jump.
    #expect(nearlyEqual(figure.pose(idle, at: idle.clip.duration - 1e-9), figure.pose(idle, at: 0)))
    // The cheer lands where the idle starts (half-closed eyes included, for deadpan), so
    // handing back to idle doesn't jump either.
    #expect(nearlyEqual(figure.pose(cheer, at: cheer.clip.duration), figure.pose(idle, at: 0)))
}

/// The same pose, give or take floating-point rounding.
private func nearlyEqual(_ first: Pose, _ second: Pose) -> Bool {
    zip(first.parts, second.parts).allSatisfy { one, other in
        Channel.allCases.allSatisfy { abs(one[$0] - other[$0]) < 1e-6 }
    }
}

/// Personas read differently at a glance: how high each one jumps, and the moves that
/// define them.
@Test func personasMoveTheirOwnWay() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    func rootValues(_ persona: Persona, _ value: (PartPose) -> Double) throws -> [Double] {
        let cheer = try figure.bind(PlaceholderCharacter.clip("cheer", persona: persona))
        return (0...Int(cheer.clip.duration * 100)).map { value(figure.pose(cheer, at: Double($0) / 100).parts[1]) }
    }
    // Root y is up-negative, so the highest jump has the smallest minimum.
    let peaks = try Persona.allCases.map { try rootValues($0, \.y).min() ?? 0 }
    #expect(abs(peaks[0] - -10) < 0.5)  // deadpan
    #expect(abs(peaks[1] - -36) < 0.5)  // energetic
    #expect(peaks.min() == peaks[1])
    #expect(peaks.max() == peaks[0])
    // The show-off spins: the figure flips through its own width.
    #expect(try rootValues(.showoff, \.scaleX).min() ?? 1 < 0)
    // The shy one edges sideways before it hops.
    #expect(abs((try rootValues(.shy, \.x).min() ?? 0) - -10) < 0.5)
}

/// Every look stays inside the canvas through every frame of every persona's clips, so a view sized to
/// the art never cuts off an ear or a racket. The bottom edge is left out: the shadow sits on it.
@Test(arguments: Persona.allCases, wardrobe)
func everyFrameStaysOnTheCanvas(persona: Persona, outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    for name in ["idle", "cheer"] {
        let bound = try figure.bind(PlaceholderCharacter.clip(name, persona: persona))
        for frame in 0...Int(bound.clip.duration * 50) {
            let time = Double(frame) / 50
            for (part, placement) in zip(figure.parts, figure.layout(figure.pose(bound, at: time)))
            where placement.opacity > 0 {
                for shape in part.art.flatMap(\.shapes) {
                    let margin = (shape.stroke?.width ?? 0) / 2
                    for point in outline(shape.path).map(placement.transform.apply(to:)) {
                        #expect(
                            point.x - margin >= 0 && point.x + margin <= figure.width && point.y - margin >= 0,
                            "\(persona.rawValue) \(name) at \(time)s: \(part.id) reaches (\(point.x), \(point.y))")
                    }
                }
            }
        }
    }
}

/// Points along each segment of a path, curves sampled every tenth of the way.
private func outline(_ path: [PathElement]) -> [Point] {
    var points: [Point] = []
    var current = Point(x: 0, y: 0)
    func along(_ point: (Double) -> Point) {
        points += (1...10).map { point(Double($0) / 10) }
    }
    for element in path {
        switch element {
        case .move(let point), .line(let point):
            points.append(point)
            current = point
        case .quadCurve(let end, let control):
            let start = current
            along { way in
                let rest = 1 - way
                return Point(
                    x: rest * rest * start.x + 2 * rest * way * control.x + way * way * end.x,
                    y: rest * rest * start.y + 2 * rest * way * control.y + way * way * end.y)
            }
            current = end
        case .curve(let end, let control1, let control2):
            let start = current
            along { way in
                let rest = 1 - way
                return Point(
                    x: rest * rest * rest * start.x + 3 * rest * rest * way * control1.x + 3 * rest * way * way
                        * control2.x + way * way * way
                        * end.x,
                    y: rest * rest * rest * start.y + 3 * rest * rest * way * control1.y + 3 * rest * way * way
                        * control2.y + way * way * way * end.y
                )
            }
            current = end
        case .close: break
        }
    }
    return points
}

/// Every body the editor groups is bundled, and every bundled body is in a group; every prop
/// it offers is bundled.
@Test func theEditorOffersBundledArt() throws {
    let choices = try PlaceholderCharacter.editorChoices()
    #expect(choices.species.map(\.id) == ["person", "cat", "dog", "rabbit", "bear"])
    #expect(choices.species.map(\.wearsHair) == [true, false, false, false, false])
    let grouped = choices.species.flatMap(\.bodies)
    #expect(Set(grouped).count == grouped.count)
    #expect(Set(grouped) == Set(PlaceholderCharacter.variants(for: "body")))
    #expect(choices.props == ["dumbbell", "racket"])
    #expect(Set(choices.props).isSubset(of: PlaceholderCharacter.variants(for: "prop")))
}

@Test func tonesNameTheColorAnUncoloredVariantShows() {
    #expect(PlaceholderCharacter.tones(for: "top", wearing: "tee")?.base == RGBAColor(hex: "#2D5BA0"))
    #expect(PlaceholderCharacter.tones(for: "body", wearing: "calico") == nil)
    #expect(PlaceholderCharacter.tones(for: "prop", wearing: "dumbbell") == nil)
}

@Test func editorChoicesOfAnotherVersionAreRejected() {
    #expect(throws: AvatarError.unsupportedVersion(2)) {
        try EditorChoices.decode(Data(#"{"version": 2, "species": [], "props": []}"#.utf8))
    }
}

/// A misspelt key fails instead of loading as if it were absent.
@Test func editorChoicesWithAnUnknownKeyAreRejected() {
    #expect(throws: AvatarError.malformedJSON(#".species[0]: unknown key "hiar""#)) {
        try EditorChoices.decode(
            Data(#"{"version": 1, "species": [{"id": "person", "bodies": ["peach"], "hiar": true}], "props": []}"#.utf8)
        )
    }
}
