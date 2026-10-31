import Contracts
import Foundation
import Testing

@testable import Backend

// What the phone keeps for one member, on disk, without the API.

private func member(_ uuid: String) throws -> MemberID {
    MemberID(try #require(UUID(uuidString: uuid)))
}

private func root() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "wildcard-tests-\(UUID().uuidString)")
}

private func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
}

@Test func aNewAccountOnThePhoneNeverSeesWhatWasKeptForTheLastOne() throws {
    let folders = MemberFolders(root: root())
    let deleted = try member("11111111-1111-1111-1111-111111111111")
    let kept = folders.folder(for: deleted).appending(path: "home.json")
    try DeviceJSON.write(Data("{}".utf8), to: kept)

    let next = folders.folder(for: try member("22222222-2222-2222-2222-222222222222"))

    #expect(next.lastPathComponent == "22222222-2222-2222-2222-222222222222")
    #expect(!exists(kept))
}

@Test func theSameMemberKeepsTheirCopy() throws {
    let folders = MemberFolders(root: root())
    let mine = try member("11111111-1111-1111-1111-111111111111")
    let kept = folders.folder(for: mine).appending(path: "home.json")
    try DeviceJSON.write(Data("{}".utf8), to: kept)

    #expect(folders.folder(for: mine).appending(path: "home.json") == kept)
    #expect(exists(kept))
}

@Test func filesAnEarlierBuildKeptAtTheRootAreDeleted() throws {
    let root = root()
    let legacy = root.appending(path: "home.json")
    try DeviceJSON.write(Data("{}".utf8), to: legacy)

    _ = MemberFolders(root: root).folder(for: try member("22222222-2222-2222-2222-222222222222"))

    #expect(!exists(legacy))
}

@Test func signingOutDeletesEveryMembersFolder() throws {
    let root = root()
    let folders = MemberFolders(root: root)
    try DeviceJSON.write(
        Data("{}".utf8),
        to: folders.folder(for: try member("11111111-1111-1111-1111-111111111111")).appending(path: "home.json"))

    folders.forgetAll()

    #expect(!exists(root))
}
