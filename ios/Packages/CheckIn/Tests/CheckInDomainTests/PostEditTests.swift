import CheckInDomain
import Contracts
import Foundation
import Testing

private func savedMeal(photos paths: [String], caption: String?) throws -> CheckIn {
    let refs = try paths.map { try PhotoRef(path: $0, size: PhotoSize(width: 1080, height: 1350)) }
    return CheckIn(
        id: CheckInID(id(500)), member: myID, day: tuesday,
        createdAt: Timestamp(millisecondsSince1970: 1_792_510_000_000),
        audience: try Audience([squadID]),
        entry: .cheatMeal(Meal(photos: refs.isEmpty ? nil : try Photos(refs), caption: try caption.map(Caption.init))))
}

private let picked = PreparedPhoto(
    id: id(900), jpeg: Data([0xFF, 0xD8]), size: try? PhotoSize(width: 800, height: 600))

@Test func anEditKeepsTheSavedPhotosAndAddsTheNewOnesInOrder() throws {
    let saved = try savedMeal(photos: ["\(myID)/a", "\(myID)/b"], caption: "炸鸡")
    let kept = try #require(saved.entry.photos?.all.last)
    let edit = PostEdit(
        original: saved, activity: .sport("run"), minutes: nil, line: " 炸鸡和可乐 ",
        photos: [.new(picked), .saved(kept)])
    #expect(edit.newPhotos == [picked])

    let uploaded = try PhotoRef(path: "\(myID)/new")
    let checkIn = try edit.checkIn(uploaded: [picked.id: uploaded])
    #expect(checkIn.id == saved.id)
    #expect(checkIn.day == saved.day)
    #expect(checkIn.createdAt == saved.createdAt)
    #expect(checkIn.audience == saved.audience)
    guard case .cheatMeal(let meal) = checkIn.entry else {
        Issue.record("the kind changed: \(checkIn.entry)")
        return
    }
    #expect(meal.caption?.text == "炸鸡和可乐")
    #expect(meal.photos?.all.map(\.path) == ["\(myID)/new", "\(myID)/b"])
    // The new photo carries its own size; the kept one keeps the saved size.
    #expect(
        meal.photos?.all.map(\.size) == [
            try PhotoSize(width: 800, height: 600), try PhotoSize(width: 1080, height: 1350),
        ])
}

@Test func anEditCanTakeEveryPhotoAndTheCaptionOff() throws {
    let saved = try savedMeal(photos: ["\(myID)/a"], caption: "炸鸡")
    let checkIn = try PostEdit(original: saved, activity: .sport("run"), minutes: nil, line: "  ", photos: [])
        .checkIn(uploaded: [:])
    #expect(checkIn.entry == .cheatMeal(Meal(photos: nil, caption: nil)))
}

@Test func aPhotoNotYetUploadedOrAnEmptyDisclaimerCantBeSaved() throws {
    let saved = try savedMeal(photos: [], caption: nil)
    #expect(throws: CheckInError.refused) {
        try PostEdit(original: saved, activity: .sport("run"), minutes: nil, line: "", photos: [.new(picked)])
            .checkIn(uploaded: [:])
    }
    let disclaimer = CheckIn(
        id: saved.id, member: myID, day: tuesday, createdAt: saved.createdAt, audience: saved.audience,
        entry: .disclaimer(try Disclaimer("下雨了")))
    let empty = PostEdit(original: disclaimer, activity: .sport("run"), minutes: nil, line: " ", photos: [])
    #expect(!empty.isSavable)
    #expect(PostEdit(original: disclaimer, activity: .sport("run"), minutes: nil, line: "还在下", photos: []).isSavable)
}

@MainActor @Test func editingUploadsTheNewPhotosThenSavesAndDeletingRemovesThePost() async throws {
    let saved = try savedMeal(photos: ["\(myID)/a"], caption: "炸鸡")
    let backend = ScriptedBackend(server: sampleHome(checkIns: [saved]))
    let today = store(backend)
    await today.load()

    let edited = try await today.edit(
        PostEdit(original: saved, activity: .sport("run"), minutes: nil, line: "炸鸡", photos: [.new(picked)]))
    #expect(await backend.uploads == [picked.id])
    #expect(await backend.edits == [edited])
    #expect(today.home?.checkIns.first { $0.id == saved.id } == edited)

    try await today.delete(saved.id)
    #expect(await backend.deletes == [saved.id])
    #expect(today.home?.checkIns.contains { $0.id == saved.id } == false)
}

@MainActor @Test func anEditTriedAgainSendsEachNewPhotoOnce() async throws {
    let saved = try savedMeal(photos: [], caption: "炸鸡")
    let backend = ScriptedBackend(server: sampleHome(checkIns: [saved]))
    let today = store(backend)
    await today.load()
    let second = PreparedPhoto(id: id(901), jpeg: Data([0xFF, 0xD8]), size: picked.size)
    let edit = PostEdit(
        original: saved, activity: .sport("run"), minutes: nil, line: "炸鸡", photos: [.new(picked), .new(second)])

    // The first photo goes up, then the second fails: the try fails with one photo already sent.
    await backend.set(uploadsBeforeFailing: 1)
    await #expect(throws: CheckInError.notSent) { try await today.edit(edit) }
    await backend.set(uploadsBeforeFailing: .max)
    let edited = try await today.edit(edit)
    #expect(await backend.uploads == [picked.id, second.id])
    #expect(await backend.edits == [edited])
}
