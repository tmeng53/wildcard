import AvatarArt
import AvatarDomain
import Testing

/// Every bundled coach builds, plays each move from rest, and stays on the canvas.
@Test func everyCoachPlaysEveryMove() throws {
    #expect(CoachCharacter.bundled == ["xiaohun"])
    for coach in CoachCharacter.bundled {
        let figure = try CoachCharacter.figure(coach)
        for move in CoachCharacter.Move.allCases {
            let clip = try CoachCharacter.clip(move, coach: coach)
            let bound = try figure.bind(clip)
            #expect(clip.loops == move.loops, "\(coach) \(move)")
            expectOnCanvas(figure, bound, for: clip.duration, "\(coach) \(move)")
        }
    }
}

/// At rest the coach's eyes are open and dry; blinking and crying show only in their moves.
@Test func coachFacesShowOnlyInTheirMoves() throws {
    let figure = try CoachCharacter.figure("xiaohun")
    let (blink, cry) = (try figure.index("blink"), try figure.index("cry"))
    #expect(figure.parts[blink].restOpacity == 0 && figure.parts[cry].restOpacity == 0)
    let idle = try figure.bind(CoachCharacter.clip(.idle, coach: "xiaohun"))
    #expect(figure.pose(idle, at: 1).parts[blink].opacity == 0)
    #expect(figure.pose(idle, at: 2.7).parts[blink].opacity == 1)
    let crying = try figure.bind(CoachCharacter.clip(.crying, coach: "xiaohun"))
    #expect(figure.pose(crying, at: 0.5).parts[cry].opacity == 1)
}

/// The shared moves end where they began, so the idle takes over without a jump, and the front
/// left arm shows only while the one behind the body hides: never two left arms, never none.
@Test func sharedMovesEndAtRestWithOneLeftArm() throws {
    let figure = try CoachCharacter.figure("xiaohun")
    let (back, front) = (try figure.index("armL"), try figure.index("armLFront"))
    for move in [CoachCharacter.Move.whistle, .clap, .pepTalk, .cheer] {
        let clip = try CoachCharacter.clip(move, coach: "xiaohun")
        let bound = try figure.bind(clip)
        #expect(figure.pose(bound, at: clip.duration) == figure.restPose, "\(move) ends off rest")
        for frame in 0...Int(clip.duration * 50) {
            let pose = figure.pose(bound, at: Double(frame) / 50)
            #expect(pose.parts[back].opacity + pose.parts[front].opacity == 1, "\(move) at frame \(frame)")
        }
    }
}

/// Every coach plays the shared moves from the one folder, so a new coach gets them for free.
@Test func sharedMovesComeFromOneFolder() throws {
    #expect(try CoachCharacter.clip(.whistle, coach: "xiaohun").name == "whistle")
    #expect(try CoachCharacter.clip(.clap, coach: "xiaohun").name == "clap")
    #expect(try CoachCharacter.clip(.pepTalk, coach: "xiaohun").name == "pep-talk")
}

@Test func aCoachWithoutArtHasNone() {
    #expect(!CoachCharacter.exists("not-a-coach"))
    #expect(throws: AvatarError.self) { try CoachCharacter.figure("not-a-coach") }
}
