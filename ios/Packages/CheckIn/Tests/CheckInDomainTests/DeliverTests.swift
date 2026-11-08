import CheckInDomain
import Contracts
import Foundation
import Testing

private let run = CheckInDraft.trained(.sport("run"), nil, PostBody(photos: [], caption: "雨中五公里"))

@MainActor @Test func aQueuedPostCountsAtOnceAndDeliverSavesIt() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()

    let post = try await today.queue(run)
    #expect(await backend.saves.isEmpty)
    #expect(today.myStatus == .trained)
    #expect(today.progress(of: post.id) == 0)

    guard case .posted(let saved) = await today.deliver(post.id) else {
        Issue.record("expected it saved")
        return
    }
    #expect(saved.id == post.id)
    #expect(today.pending.isEmpty)
    #expect(today.progress(of: post.id) == nil)
    #expect(today.myStatus == .trained)
}

@MainActor @Test func deliverWaitsOfflineWithItsPhotosProgressKept() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(uploadsBeforeFailing: 1)

    let post = try await today.queue(.healthyMeal(PostBody(photos: [photo(1), photo(2)], caption: "")))
    #expect(await today.deliver(post.id) == .waiting)
    // One of two photos up, the save still to come.
    #expect(today.progress(of: post.id) == 1.0 / 3.0)
    #expect(today.refused.isEmpty)

    await backend.set(uploadsBeforeFailing: .max)
    #expect(await today.deliver(post.id) != .waiting)
    #expect(await backend.uploads == [id(1), id(2)])
}

@MainActor @Test func aRefusalOnDeliverIsListedToTell() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notInSquad)

    let post = try await today.queue(run)
    #expect(await today.deliver(post.id) == .refused)
    #expect(today.pending.isEmpty)
    #expect(today.refused.map(\.pending.id) == [post.id])
    #expect(today.refused.map(\.reason) == [.notInSquad])
    #expect(today.myStatus == .notCheckedIn)
}

@MainActor @Test func aPostSentByADrainAlreadyUnderWayStillReportsItsFate() async throws {
    let backend = ScriptedBackend()
    let today = store(backend)
    await today.load()
    await backend.set(failure: .notSent)
    try await today.post(.healthyMeal(PostBody(photos: [], caption: "鸡胸肉")))

    await backend.set(failure: nil)
    await backend.holdSaves()
    let sending = Task { await today.sendPending() }
    while await backend.savesWaiting == 0 { await Task.yield() }
    let post = try await today.queue(run)
    await backend.releaseSaves()
    await sending.value
    // The drain under way sent it before anyone asked.
    #expect(today.pending.isEmpty)

    guard case .posted(let saved) = await today.deliver(post.id) else {
        Issue.record("expected it saved")
        return
    }
    #expect(saved.id == post.id)
}
