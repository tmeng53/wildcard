import AvatarArt
import AvatarDomain
import Foundation
import Testing

/// The bundled files load and fit together, so a broken edit to them fails here, not on a phone.
@Test(arguments: PlaceholderCharacter.squad)
func everyOutfitBuilds(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    #expect(
        figure.parts.map(\.id.rawValue) == [
            "shadow", "root", "tail", "legL", "legR", "torso", "earL", "earR", "head", "flapL", "flapR", "crown",
            "nose",
            "eyes", "brows", "glasses", "mouthSmile", "mouthOpen", "propR", "armL", "armR",
        ])
    // Only the bear's hands are free, and only the cat has a tail.
    #expect(try figure.part("propR").art.count == (outfit == PlaceholderCharacter.bear ? 0 : 1))
    #expect(try figure.part("tail").art.count == (outfit == PlaceholderCharacter.cat ? 1 : 0))
    // Everyone has eyes and both mouths; only people pick brows.
    #expect(try ["eyes", "mouthSmile", "mouthOpen"].allSatisfy { try figure.part($0).art.count == 1 })
    let isPerson = PlaceholderCharacter.people.contains(outfit.variants["body"] ?? "")
    #expect(try figure.part("brows").art.count == (isPerson ? 1 : 0))
    // The open mouth waits hidden until the cheer swaps it in.
    #expect(figure.layout(figure.restPose)[try figure.index("mouthOpen")].opacity == 0)
}

/// Every body and hair the editor can offer, by folder name.
@Test func variantsListTheBundledArt() {
    #expect(
        PlaceholderCharacter.variants(for: "body") == [
            "bear", "bichon", "calico", "cat", "collie", "corgi", "dutch", "golden", "husky", "lihua", "lop",
            "orangewhite", "peach", "rabbit", "ragdoll", "shiba", "siamese", "tan", "tortie", "tuxedo",
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

/// People pick hair and a face; animals keep the default face their coat goes with.
@Test func theEditorOffersAFaceToPeopleOnly() {
    #expect(
        PlaceholderCharacter.slots(for: "tan") == [
            "body", "hair", "eyes", "brows", "mouth", "cheeks", "glasses", "hat", "top", "bottom", "prop",
        ])
    #expect(PlaceholderCharacter.slots(for: "cat") == ["body", "hat", "top", "bottom", "prop"])
    #expect(PlaceholderCharacter.people.allSatisfy(PlaceholderCharacter.variants(for: "body").contains))
}

/// A cat leaves its face out and still gets round eyes and a smile; a person can pick others.
@Test func looksWithoutAFaceWearTheDefaultOne() throws {
    let cat = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.cat)
    let plain = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach", "eyes": "round", "mouth": "smile"]))
    let bare = try PlaceholderCharacter.figure(wearing: Outfit(["body": "peach"]))
    #expect(try cat.part("eyes").art == plain.part("eyes").art)
    #expect(try bare.part("eyes").art == plain.part("eyes").art)
    #expect(try bare.part("mouthSmile").art == plain.part("mouthSmile").art)
    let baller = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.baller)
    #expect(try baller.part("eyes").art != plain.part("eyes").art)
    #expect(try baller.part("mouthSmile").art != plain.part("mouthSmile").art)
}

/// Brows take the hair's color until they're given their own.
@Test func browsFollowTheHairUntilPickedSeparately() throws {
    let (auburn, blonde, black) = try (
        #require(RGBAColor(hex: "#A2452F")), #require(RGBAColor(hex: "#E2BF74")), #require(RGBAColor(hex: "#2A2333"))
    )
    var look = PlaceholderCharacter.lifter
    look.dyeHair(auburn)
    #expect(look.colors["hair"] == auburn && look.colors["brows"] == auburn)
    look.colors["brows"] = black
    look.dyeHair(blonde)
    #expect(look.colors["hair"] == blonde && look.colors["brows"] == black)
    let figure = try PlaceholderCharacter.figure(wearing: look)
    #expect(try figure.part("brows").art[0].shapes.allSatisfy { $0.stroke?.color == black })

    // Without brows, only the hair takes the color, and the look still builds.
    var browless = Outfit(["body": "peach", "hair": "bob"])
    browless.dyeHair(auburn)
    #expect(browless.colors == ["hair": auburn])
    _ = try PlaceholderCharacter.figure(wearing: browless)
    // Brows put on later take the dyed hair's color.
    browless.wear("bold", in: "brows")
    #expect(browless.colors["brows"] == auburn)
    _ = try PlaceholderCharacter.figure(wearing: browless)
    // Taking brows off drops their color, so the look still builds.
    look.wear(nil, in: "brows")
    #expect(look.colors["brows"] == nil && look.variants["brows"] == nil)
    _ = try PlaceholderCharacter.figure(wearing: look)
}

@Test(arguments: wardrobe)
func everyLookBuilds(outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    #expect(figure.parts.count == 21)
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

/// Each species moves its own way on top of every persona: the moves start and end at rest,
/// so the idle still loops without a jump and the cheer still lands where the idle starts.
@Test(arguments: Persona.allCases, ["peach", "cat", "shiba", "golden", "rabbit", "lop", "bear"])
func speciesMovesLayerOnEveryPersona(persona: Persona, body: String) throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
    let plainIdle = try figure.bind(PlaceholderCharacter.clip("idle", persona: persona))
    let idle = try figure.bind(PlaceholderCharacter.clip("idle", persona: persona, body: body))
    let cheer = try figure.bind(PlaceholderCharacter.clip("cheer", persona: persona, body: body))
    #expect(idle.clip.accents.count == 1)
    #expect(idle.clip.accents.first?.tempo == persona.accentTempo)
    #expect(idle.clip.accents.first?.strength == persona.accentStrength)
    #expect(cheer.clip.accents.count == (["peach", "cat"].contains(body) ? 0 : 1))
    #expect(nearlyEqual(figure.pose(idle, at: 0), figure.pose(plainIdle, at: 0)))
    #expect(nearlyEqual(figure.pose(cheer, at: cheer.clip.duration), figure.pose(idle, at: 0)))
}

/// Bodies the editor doesn't list, or a species with no moves, play the persona's clip as is.
@Test func speciesFollowTheEditorsGroups() throws {
    #expect(PlaceholderCharacter.species(of: "tan") == "person")
    #expect(PlaceholderCharacter.species(of: "lop") == "rabbit")
    #expect(PlaceholderCharacter.species(of: "husky") == "dog")
    #expect(PlaceholderCharacter.species(of: "dragon") == nil)
    #expect(try PlaceholderCharacter.clip("idle", persona: .shy, body: "dragon").accents.isEmpty)
    #expect(try PlaceholderCharacter.clip("idle", persona: .shy, body: nil).accents.isEmpty)
}

/// A cat yawns now and then: its mouth opens wide and its eyes shut, later for a deadpan cat,
/// which does everything slowly.
@Test func catsYawn() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.cat)
    let mouth = try figure.index("mouthOpen")
    func openMouth(_ persona: Persona, at time: Double) throws -> Double {
        let idle = try figure.bind(PlaceholderCharacter.clip("idle", persona: persona, body: "cat"))
        return figure.layout(figure.pose(idle, at: time))[mouth].opacity
    }
    #expect(try openMouth(.energetic, at: 0) == 0)
    // The yawn is 3.3 to 4.5 s into the cat's loop: 2.4 to 3.2 s for an energetic cat
    // (1.4 times as fast), 4.7 to 6.4 s for a deadpan one (0.7 times).
    #expect(try openMouth(.energetic, at: 2.8) == 1)
    #expect(try openMouth(.deadpan, at: 2.8) == 0)
    #expect(try openMouth(.deadpan, at: 5.5) == 1)
}

/// Rabbits and pointy-eared dogs carry their ears as parts of their own, so the moves can turn
/// them: upright ears behind the head, a lop's floppy ones over it; rabbits move their noses too.
/// Dogs whose ears don't move (a golden's, a bichon's) keep them in the head's art, drawn as before.
@Test func earsThatMoveArePartsOfTheirOwn() throws {
    let parts: [String: [PartID]] = [
        "rabbit": ["earL", "earR", "nose"], "dutch": ["earL", "earR", "nose"], "lop": ["flapL", "flapR", "nose"],
        "shiba": ["earL", "earR"], "corgi": ["earL", "earR"], "husky": ["earL", "earR"],
        "golden": [], "collie": [], "bichon": [],
    ]
    for (body, moving) in parts {
        let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": body]))
        for part in ["earL", "earR", "flapL", "flapR", "nose"] as [PartID] {
            #expect(try figure.part(part).art.isEmpty == !moving.contains(part), "\(body) \(part)")
        }
    }
}

/// A hat sits over floppy ears, as it did before the ears were parts of their own.
@Test func hatsSitOverFloppyEars() throws {
    let figure = try PlaceholderCharacter.figure(wearing: Outfit(["body": "lop", "hat": "cap"]))
    #expect(try figure.index("crown") > figure.index("flapL") && figure.index("crown") > figure.index("flapR"))
    #expect(try figure.part("crown").art.count == 2)
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

/// Every look stays inside the canvas through every frame of every persona's clips, with its
/// species' moves on top, so a view sized to
/// the art never cuts off an ear or a racket. The bottom edge is left out: the shadow sits on it.
@Test(arguments: Persona.allCases, wardrobe)
func everyFrameStaysOnTheCanvas(persona: Persona, outfit: Outfit) throws {
    let figure = try PlaceholderCharacter.figure(wearing: outfit)
    for name in ["idle", "cheer"] {
        let bound = try figure.bind(PlaceholderCharacter.clip(name, persona: persona, body: outfit.variants["body"]))
        // An idle with its species' moves on top lines its two loops up differently each time
        // round, so it plays for 20 s, a few rounds of the longest.
        let seconds = bound.clip.accents.isEmpty || !bound.clip.loops ? bound.clip.duration : 20
        for frame in 0...Int(seconds * 50) {
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

/// Every body the editor groups is bundled, and every bundled body except `tan` (a skin tone the
/// person's swatches cover) is in a group; every prop it offers is bundled.
@Test func theEditorOffersBundledArt() throws {
    let choices = try PlaceholderCharacter.editorChoices()
    #expect(choices.species.map(\.id) == ["person", "cat", "dog", "rabbit", "bear"])
    #expect(choices.species.map(\.wearsHair) == [true, false, false, false, false])
    let grouped = choices.species.flatMap(\.bodies)
    #expect(Set(grouped).count == grouped.count)
    #expect(Set(grouped).union(["tan"]) == Set(PlaceholderCharacter.variants(for: "body")))
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
