import Contracts
import MeDomain
import Testing

extension MeModelTests {
    @Test func savesAndForgetsTheBirthdayAndKeepsItWhenSavingFails() async throws {
        let service = FakeService(sample)
        let page = model(service)
        await page.reload()
        #expect(page.overview?.birthday == nil)

        let birthday = Birthday(sent: try LocalDay("1996-04-18"))
        #expect(await page.save(birthday: birthday))
        #expect(page.overview?.birthday == birthday)
        #expect(await service.current.birthday == birthday)

        await service.fail(with: .unavailable)
        #expect(await page.save(birthday: nil) == false)
        #expect(page.overview?.birthday == birthday)
        #expect(page.saveFailed)

        await service.fail(with: nil)
        #expect(await page.save(birthday: nil))
        #expect(page.overview?.birthday == nil)
        #expect(await service.current.birthday == nil)
    }
}
