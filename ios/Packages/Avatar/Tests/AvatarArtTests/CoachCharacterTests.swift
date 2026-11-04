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
            #expect(clip.loops == (move != .cheer), "\(coach) \(move)")
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

@Test func aCoachWithoutArtHasNone() {
    #expect(!CoachCharacter.exists("not-a-coach"))
    #expect(throws: AvatarError.self) { try CoachCharacter.figure("not-a-coach") }
}
