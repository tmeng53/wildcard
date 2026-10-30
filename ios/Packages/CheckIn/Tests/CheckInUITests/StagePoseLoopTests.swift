import AvatarArt
import CheckInDomain
import Testing

@testable import CheckInUI

/// Each pose on the home scene plays its own loop: sitting, the sign and sleeping, and
/// everyone else the persona's idle with their species' moves on top.
@Test func eachPosePlaysItsLoop() throws {
    #expect(try StagePose.sitting.loop(persona: .drama, species: nil).name == "sit")
    #expect(try StagePose.holdingSign.loop(persona: .drama, species: nil).name == "sign")
    #expect(try StagePose.asleep.loop(persona: .drama, species: nil).name == "sleep")
    for pose in [StagePose.standing, .inPlace(nil), .station(.jogging)] {
        #expect(try pose.loop(persona: .drama, species: "cat").name == "idle")
    }
    #expect(
        try StagePose.standing.loop(persona: .drama, species: "cat")
            != PlaceholderCharacter.clip("idle", persona: .drama))
}

/// The lights' timeline waits for the `woken` move to end before a sleeper's 请假条 comes back.
@Test func theWakeUpLastsAsLongAsTheTimelineSays() throws {
    #expect(try PlaceholderCharacter.woken().duration == LightsFlip.wokenDuration)
}
