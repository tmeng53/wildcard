import Contracts
import Foundation
import Testing

@testable import Backend

// Photos kept on disk, without the API: kept by path, the photos of the posts posted longest ago
// going first.

private func emptyFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "wildcard-photos-\(UUID().uuidString)")
}

/// A post's time, `day` days into November 2026.
private func posted(_ day: Int) -> Date { Date(timeIntervalSince1970: 1_793_491_200 + Double(day) * 86_400) }

@Test func aKeptPhotoComesBackByItsPath() async {
    let cache = PhotoCache(directory: emptyFolder(), limit: 100)
    await cache.keep(Data([1, 2, 3]), at: "aaaa/bbbb", postedAt: posted(1))

    #expect(await cache.photo(at: "aaaa/bbbb") == Data([1, 2, 3]))
    #expect(await cache.photo(at: "aaaa/cccc") == nil)
}

@Test func aPhotoKeptOnceIsReadByTheNextLaunch() async {
    let folder = emptyFolder()
    await PhotoCache(directory: folder, limit: 100).keep(Data([7]), at: "a/b", postedAt: posted(1))

    #expect(await PhotoCache(directory: folder, limit: 100).photo(at: "a/b") == Data([7]))
}

@Test func aFullCacheDropsThePhotosOfTheOldestPostsEvenWhenJustSeen() async {
    let cache = PhotoCache(directory: emptyFolder(), limit: 100)
    await cache.keep(Data(count: 40), at: "latest/1", postedAt: posted(8))
    await cache.keep(Data(count: 40), at: "older/2", postedAt: posted(5))
    // Seen last, scrolling far back, but its post is the oldest.
    _ = await cache.photo(at: "older/2")

    // 120 bytes is over the 100: room is made down to 80.
    await cache.keep(Data(count: 40), at: "middle/3", postedAt: posted(6))

    #expect(await cache.photo(at: "latest/1")?.count == 40)
    #expect(await cache.photo(at: "middle/3")?.count == 40)
    #expect(await cache.photo(at: "older/2") == nil)
}

@Test func aPhotoOlderThanAFullCacheIsNotKept() async {
    let cache = PhotoCache(directory: emptyFolder(), limit: 100)
    await cache.keep(Data(count: 40), at: "a/1", postedAt: posted(8))
    await cache.keep(Data(count: 40), at: "b/2", postedAt: posted(7))

    await cache.keep(Data(count: 40), at: "old/3", postedAt: posted(1))

    #expect(await cache.photo(at: "old/3") == nil)
    #expect(await cache.photo(at: "a/1") != nil)
    #expect(await cache.photo(at: "b/2") != nil)
}

@Test func aPhotoBiggerThanTheCacheIsNotKept() async {
    let cache = PhotoCache(directory: emptyFolder(), limit: 10)
    await cache.keep(Data(count: 11), at: "big/1", postedAt: posted(1))

    #expect(await cache.photo(at: "big/1") == nil)
}

@Test func signingOutForgetsEveryPhoto() async {
    let cache = PhotoCache(directory: emptyFolder(), limit: 100)
    await cache.keep(Data([1]), at: "a/1", postedAt: posted(1))
    await cache.forgetAll()

    #expect(await cache.photo(at: "a/1") == nil)
    await cache.keep(Data([2]), at: "a/2", postedAt: posted(1))
    #expect(await cache.photo(at: "a/2") == Data([2]))
}

@Test func theAPIReadsAKeptPhotoWithoutItsURL() async throws {
    let cache = PhotoCache(directory: emptyFolder(), limit: 100)
    await cache.keep(Data([9]), at: "kept/1", postedAt: posted(1))
    let api = WildcardAPI(
        url: try #require(URL(string: "http://127.0.0.1:1")), accessToken: { _ in "token" }, photos: cache)

    // No view URL and nothing listening: only the kept copy can answer.
    #expect(await api.photo(try PhotoRef(path: "kept/1")) == Data([9]))
    #expect(await api.photo(try PhotoRef(path: "missing/1")) == nil)
}

@Test func aDownloadStartedBeforeSignOutIsNotKept() async {
    let cache = PhotoCache(directory: emptyFolder(), limit: 100)
    let started = await cache.generation
    await cache.forgetAll()

    await cache.keep(Data([1]), at: "late/1", postedAt: posted(1), startedIn: started)

    #expect(await cache.photo(at: "late/1") == nil)
    await cache.keep(Data([2]), at: "next/1", postedAt: posted(1), startedIn: await cache.generation)
    #expect(await cache.photo(at: "next/1") == Data([2]))
}
