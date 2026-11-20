import Contracts
import Foundation
import Testing

@testable import MeDomain

private let mia = BlockedMember(
    id: MemberID(UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))), character: nil,
    since: Date(timeIntervalSince1970: 1_792_454_400))

@MainActor @Test func unblockingTakesThemOffTheListOnceTheServerTookIt() async {
    let service = FakeService(sample)
    await service.setBlocked([mia])
    let list = BlockedMembersModel(service: service)
    await list.load()
    #expect(list.blocked == [mia])

    await service.fail(with: .unavailable)
    await list.unblock(mia.id)
    #expect(list.blocked == [mia])
    #expect(list.failed)

    await service.fail(with: nil)
    await list.unblock(mia.id)
    #expect(list.blocked == [])
    #expect(!list.failed)
}
