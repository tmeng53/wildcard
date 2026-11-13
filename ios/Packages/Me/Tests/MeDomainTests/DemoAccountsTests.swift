import Contracts
import Foundation
import Testing

@testable import MeDomain

private func member(_ number: Int) -> MemberID {
    MemberID(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)) ?? UUID())
}

private let own = DemoAccount(id: member(1), isOwner: true, character: nil)
private let demo = DemoAccount(id: member(2), isOwner: false, character: nil)

/// Which way each switch went, and what it answered.
@MainActor
private final class Switches {
    var targets: [MemberID] = []
    var home = 0
    var works = true
}

@MainActor
private func model(
    current: MemberID, switches: Switches,
    service: any DemoAccountService = KeptDemoAccounts([own, demo]) {
        member(3)
    }
) -> DemoAccountsModel {
    DemoAccountsModel(
        service: service, current: current,
        switchTo: { id in
            switches.targets.append(id)
            return switches.works
        },
        returnHome: {
            switches.home += 1
            return switches.works
        })
}

private struct Unreachable: DemoAccountService {
    func accounts() async throws(MeError) -> [DemoAccount] { throw .unavailable }
    func create() async throws(MeError) -> MemberID { throw .unavailable }
}

@MainActor
struct DemoAccountsTests {
    @Test func listsTheAccounts() async {
        let model = model(current: own.id, switches: Switches())
        await model.load()
        #expect(model.accounts == [own, demo])
        #expect(model.phase == .ready)
    }

    @Test func aDemoAccountIsSwitchedToAndTheOwnAccountReturnedTo() async {
        let switches = Switches()
        await model(current: own.id, switches: switches).open(demo)
        await model(current: demo.id, switches: switches).open(own)
        #expect(switches.targets == [demo.id])
        #expect(switches.home == 1)
    }

    @Test func theAccountThisPhoneIsOnDoesNothing() async {
        let switches = Switches()
        await model(current: own.id, switches: switches).open(own)
        #expect(switches.targets.isEmpty && switches.home == 0)
    }

    @Test func aNewAccountIsMadeThenSwitchedTo() async {
        let switches = Switches()
        let service = KeptDemoAccounts([own]) { member(3) }
        await model(current: own.id, switches: switches, service: service).makeNew()
        #expect(switches.targets == [member(3)])
        #expect(await service.kept.map(\.id) == [own.id, member(3)])
    }

    @Test func aFailedSwitchOrListSaysSo() async {
        let switches = Switches()
        switches.works = false
        let switching = model(current: own.id, switches: switches)
        await switching.open(demo)
        #expect(switching.phase == .failed)

        let listing = model(current: own.id, switches: switches, service: Unreachable())
        await listing.load()
        await listing.makeNew()
        #expect(listing.phase == .failed)
        #expect(switches.targets == [demo.id])
    }
}
