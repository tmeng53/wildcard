import CheckInDomain
import Contracts
import Foundation
import Testing

// A 请假条's photos go out with it, as a 训练's do.

@MainActor @Test func aDisclaimersPhotosUploadAndGoOutWithItCoverFirst() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()

    let photos = [photo(2), photo(1)]
    _ = try await today.post(.disclaimer(try Disclaimer("下大雨，在家给猫当沙发", restDay: true), photos: photos))
    await today.sendPending()

    #expect(await backend.uploads == [id(2), id(1)])
    let saved = try #require(await backend.saves.first)
    guard case .disclaimer(let disclaimer) = saved.entry else {
        Issue.record("expected a 请假条")
        return
    }
    #expect(disclaimer.text == "下大雨，在家给猫当沙发")
    #expect(disclaimer.restDay)
    #expect(disclaimer.photos?.all.map(\.path) == photos.map { "\(myID)/\($0.id.uuidString.lowercased())" })
}
