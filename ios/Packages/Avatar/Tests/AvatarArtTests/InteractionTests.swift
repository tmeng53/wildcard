import AvatarArt
import AvatarDomain
import AvatarLooks
import Testing

private func everyInteraction() throws -> [(String, Interaction)] {
    [
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

/// Nobody turns, flips or spins.
@Test func interactionsNeverTurnTheCharacter() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let whole = [try figure.index("root"), try figure.index("torso")]
    for (name, interaction) in try everyInteraction() {
        for role in interaction.roles {
            let bound = try figure.bind(role.clip)
            for frame in 0...Int(role.clip.duration * 100) {
                let pose = figure.pose(bound, at: Double(frame) / 100)
                for part in whole {
                    #expect(pose.parts[part].scaleX > 0.85, "\(name): \(role.clip.name) at \(frame)")
                    #expect(abs(pose.parts[part].rotation) <= 15, "\(name): \(role.clip.name) at \(frame)")
                }
            }
        }
    }
}

/// On the stack, the top one stands right over the bottom one's spot while they hold it.
@Test func stackTopStandsOverTheBottom() throws {
    let figure = try PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter)
    let root = try figure.index("root")
    let stack = try PlaceholderCharacter.stack()
    let top = figure.pose(try figure.bind(stack.roles[0].clip), at: 1.5).parts[root]
    #expect(top.x == stack.roles[1].offset && top.y < -200)
}
