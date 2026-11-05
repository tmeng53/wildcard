import AvatarArt
import Contracts
import Foundation
import Testing

@testable import MeDomain

struct CardNumberTests {
    private func overview(picked: Int?, place: Int?) throws -> MeOverview {
        var overview = MeOverview(
            character: MeCharacter(nickname: "小林", outfit: PlaceholderCharacter.lifter, persona: .energetic),
            joinedAt: nil,
            counts: LifetimeCounts(trainedDays: 0, healthyMeals: 0, cheatMeals: 0, disclaimers: 0), week: nil,
            squadName: nil, dailyPushOn: true)
        overview.jerseyNumber = try picked.map { number throws(ContractsError) in try JerseyNumber(number) }
        overview.squadPlace = place
        return overview
    }

    @Test func isThePickElseThePlaceInTheSquad() throws {
        #expect(try overview(picked: 7, place: 3).cardNumber?.text == "07")
        #expect(try overview(picked: nil, place: 1).cardNumber?.text == "01")
        #expect(try overview(picked: nil, place: nil).cardNumber == nil)
    }

    @Test func numbersOnlyUpTo99() throws {
        #expect(try overview(picked: nil, place: 120).cardNumber?.text == "99")
        #expect(throws: ContractsError.jerseyNumberOutOfRange(100)) { try JerseyNumber(100) }
        #expect(throws: ContractsError.jerseyNumberOutOfRange(-1)) { try JerseyNumber(-1) }
    }
}
