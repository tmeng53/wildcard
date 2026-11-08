import AvatarArt
import AvatarDomain
import CheckInDomain
import Contracts
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

/// A teammate who trained holds their sport's kit and loops its move, as my own character does:
/// a swimmer in the pool swims, and a tennis player away from the court still serves, as a
/// swimmer or climber away from water and wall still swims or climbs. Anyone else keeps their
/// look and pose loop.
@Test func aTeammateWhoTrainedLoopsTheirSportsMove() throws {
    let look = PlaceholderCharacter.lifter
    let names = CatalogNames(simplifiedChinese: "", english: "", traditionalChinese: "")
    let sports = SportCatalog(
        categories: [("water", "swim"), ("racket", "tennis"), ("outdoorWinter", "climb")].map { category, sport in
            SportCatalog.Category(
                id: category, names: names, color: "#4A6C8C",
                entries: [
                    SportCatalog.Entry(
                        sport: Sport(stringLiteral: sport), names: names, icon: "figure.run", offered: true,
                        category: category)
                ])
        }, signUpCommon: [], checkInQuick: [])
    let inPool = try StagePose.station(.swimming).dress(
        look, trained: .sport("swim"), persona: .drama, species: nil, catalog: sports)
    #expect(inPool.outfit.variants["prop"] == "goggles")
    #expect(inPool.loop.name == "goggles")
    #expect(inPool.loop.loops)

    let serving = try StagePose.inPlace(.sport("tennis")).dress(
        look, trained: .sport("tennis"), persona: .drama, species: nil, catalog: sports)
    #expect(serving.outfit.variants["prop"] == "racket")
    #expect(serving.loop.name == "racket")

    for (sport, prop): (Sport, String) in [("swim", "goggles"), ("climb", "chalkbag")] {
        let away = try StagePose.inPlace(.sport(sport)).dress(
            look, trained: .sport(sport), persona: .drama, species: nil, catalog: sports)
        #expect(away.outfit.variants["prop"] == prop)
        #expect(away.loop.name == prop)
    }

    let standing = try StagePose.standing.dress(look, trained: nil, persona: .drama, species: nil, catalog: sports)
    #expect(standing.outfit == look)
    #expect(standing.loop.name == "idle")
}
