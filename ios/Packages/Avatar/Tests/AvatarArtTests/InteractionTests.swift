import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

private func everyInteraction() throws -> [(String, Interaction)] {
    try Persona.allCases.map { ("poke \($0.rawValue)", try PlaceholderCharacter.poke($0)) } + [
        ("bump dodged", try PlaceholderCharacter.bumpDodged()), ("toss", try PlaceholderCharacter.toss()),
        ("stack", try PlaceholderCharacter.stack()),
    ]
}

/// Every part plays once and comes back to rest on every look: the stack's top one where it
/// jumped down, `stackTopLandsAt` to the right, and the open mouth, hidden by then, as it is.
@Test func interactionsEndAtRest() throws {
    for look in Looks.squad {
        let figure = try PlaceholderCharacter.figure(wearing: look)
        let (root, mouth) = (try figure.index("root"), try figure.index("mouthOpen"))
        for (name, interaction) in try everyInteraction() {
            for role in interaction.roles {
                let bound = try figure.bind(role.clip)
                #expect(!role.clip.loops, "\(name)")
                var end = figure.pose(bound, at: role.clip.duration)
                if role.clip.name == "stack-top" {
                    #expect(end.parts[root].x == PlaceholderCharacter.stackTopLandsAt)
                    end.parts[root].x = 0
                }
                end.parts[mouth] = figure.restPose.parts[mouth]
                #expect(nearlyEqual(end, figure.restPose), "\(name): \(role.clip.name)")
            }
        }
    }
}

/// Nobody turns, flips or spins. The one exception is falling flat under gravity, as the 戏精
/// does when poked: it may tip over onto its back, up to 90° and never past, and gets back up.
@Test func interactionsNeverTurnTheCharacter() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let whole = [try figure.index("root"), try figure.index("torso")]
    for (name, interaction) in try everyInteraction() {
        for role in interaction.roles {
            let bound = try figure.bind(role.clip)
            let lean = role.clip.name == "react-drama" ? 90.0 : 15
            for frame in 0...Int(role.clip.duration * 100) {
                let pose = figure.pose(bound, at: Double(frame) / 100)
                for part in whole {
                    #expect(pose.parts[part].scaleX > 0.85, "\(name): \(role.clip.name) at \(frame)")
                    #expect(abs(pose.parts[part].rotation) <= lean, "\(name): \(role.clip.name) at \(frame)")
                }
            }
        }
    }
}

/// The poke lands as the poker reaches furthest in, which is when the poked one reacts; on the
/// stack, the top one stands right over the bottom one's spot while they hold it.
@Test func interactionsMeetOnTheBeat() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let root = try figure.index("root")
    let poke = try PlaceholderCharacter.poke(.drama)
    let jab = try figure.bind(poke.roles[0].clip)
    let reach = (0...Int(jab.clip.duration * 100)).map { figure.pose(jab, at: Double($0) / 100).parts[root].x }
    #expect(figure.pose(jab, at: PlaceholderCharacter.pokeLands).parts[root].x == reach.max())
    #expect(poke.roles[1].delay == PlaceholderCharacter.pokeLands)
    let stack = try PlaceholderCharacter.stack()
    let top = figure.pose(try figure.bind(stack.roles[0].clip), at: 1.5).parts[root]
    #expect(top.x == stack.roles[1].offset && top.y < -200)
}
