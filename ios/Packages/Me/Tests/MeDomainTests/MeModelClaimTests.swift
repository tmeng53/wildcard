import Contracts
import Foundation
import Testing

@testable import MeDomain

/// 领取 on 商店街, saved through 我.
extension MeModelTests {
    @Test func claimingPutsAnUnlockedPieceInTheWardrobeAndAFailedOneTakesItOut() async {
        var overview = sample
        let when = Date(timeIntervalSince1970: 1_793_577_600)
        overview.unlocks = [
            Unlock(kind: .piece, id: "lap-bib", unlockedAt: when, sports: ["run"], checkIns: 5),
            Unlock(kind: .piece, id: "lap-singlet", unlockedAt: when, sports: ["run"], checkIns: 7),
            Unlock(kind: .store, id: "lap", unlockedAt: when, sports: ["run"], checkIns: 3),
        ]
        let service = FakeService(overview)
        let page = model(service)
        await page.reload()
        #expect(page.unclaimed == ["lap-bib", "lap-singlet"])

        #expect(await page.claim("lap-bib"))
        #expect(page.unclaimed == ["lap-singlet"])
        #expect(await service.current.claimed == ["lap-bib"])

        await service.fail(with: .unavailable)
        #expect(await !page.claim("lap-singlet"))
        #expect(page.unclaimed == ["lap-singlet"])
        #expect(page.saveFailed)
    }

    @Test func aReadThatLeftOutAClaimMadeHereStillShowsItClaimed() async {
        var overview = sample
        overview.unlocks = [
            Unlock(
                kind: .piece, id: "lap-bib", unlockedAt: Date(timeIntervalSince1970: 1_793_577_600), sports: [],
                checkIns: 5)
        ]
        let service = FakeService(overview)
        let page = model(service)
        await page.reload()
        #expect(await page.claim("lap-bib"))

        // 商店街's read on opening, sent before the claim saved, comes back after it.
        await service.set(claimed: [])
        await page.reload()
        #expect(page.unclaimed.isEmpty)
    }
}
