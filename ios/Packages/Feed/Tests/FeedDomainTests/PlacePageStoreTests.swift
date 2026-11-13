import Contracts
import FeedDomain
import Foundation
import Testing

/// A place's page in memory: the squad's average over every score given, each call counted, and
/// a failure for the next call when set.
actor FakePlaceBook: PlaceBook {
    var scores: [MemberID: Int] = [member(2): 5]
    var posted = true
    var failure: FeedError?
    private(set) var reads = 0
    let viewer = member(1)

    func page(of key: PlaceKey, in squad: SquadID) async throws(FeedError) -> PlacePage? {
        reads += 1
        if let failure { throw failure }
        guard posted else { return nil }
        let average = scores.isEmpty ? nil : Double(scores.values.reduce(0, +)) / Double(scores.count)
        return PlacePage(
            key: key, place: gym, visits: 12, people: 3, stars: average, raters: scores.count,
            myStars: scores[viewer], sports: [.init(activity: .sport("run"), count: 12)], meals: .none,
            posts: [])
    }

    func rate(_ key: PlaceKey, stars: Int) async throws(FeedError) {
        if let failure { throw failure }
        scores[viewer] = stars
    }

    func fail(with error: FeedError?) { failure = error }
    func nobodyPosted() { posted = false }
}

let gym: Place = {
    do {
        return try Place(name: "Equinox Flatiron", appleID: "I6FD7682FD36BB3BE", latitude: 40.74, longitude: -73.99)
    } catch { fatalError("bad test place") }
}()

@MainActor private func store(_ book: FakePlaceBook) throws -> PlacePageStore {
    PlacePageStore(book: book, squad: squad, place: gym, key: try #require(gym.key))
}

@MainActor @Test func aPlaceShowsWhatTheSquadDidThere() async throws {
    let page = try store(FakePlaceBook())
    #expect(page.phase == .loading)
    await page.load()
    #expect(page.phase == .shown)
    #expect(page.page?.visits == 12)
    #expect(page.page?.stars == 5)
    #expect(page.myStars == nil)
}

@MainActor @Test func aPlaceNobodyPostedFromShowsEmpty() async throws {
    let book = FakePlaceBook()
    await book.nobodyPosted()
    let page = try store(book)
    await page.load()
    #expect(page.phase == .shown)
    #expect(page.page?.visits == 0)
    #expect(page.page?.place.name == "Equinox Flatiron")
}

@MainActor @Test func aScoreShowsAtOnceAndTheSquadsAverageFollows() async throws {
    let page = try store(FakePlaceBook())
    await page.load()
    await page.rate(3)
    #expect(page.myStars == 3)
    #expect(page.page?.stars == 4)
    #expect(page.rateFailed == false)
}

@MainActor @Test func aScoreThatDidntGoOutGoesBack() async throws {
    let book = FakePlaceBook()
    let page = try store(book)
    await page.load()
    await page.rate(4)
    await book.fail(with: .notSent)
    await page.rate(2)
    #expect(page.myStars == 4)
    #expect(page.rateFailed)
    // The page read before stays up.
    #expect(page.phase == .shown)
}

@MainActor @Test func theSameScoreAgainOrOneOffTheScaleSendsNothing() async throws {
    let book = FakePlaceBook()
    let page = try store(book)
    await page.load()
    await page.rate(4)
    let reads = await book.reads
    await page.rate(4)
    await page.rate(0)
    await page.rate(6)
    #expect(await book.reads == reads)
    #expect(page.myStars == 4)
}

@MainActor @Test func aPageThatCantBeReadFailsUntilItCan() async throws {
    let book = FakePlaceBook()
    await book.fail(with: .notSent)
    let page = try store(book)
    await page.load()
    #expect(page.phase == .failed)
    await book.fail(with: nil)
    await page.load()
    #expect(page.phase == .shown)
}

@MainActor @Test func aScoreGivenBeforeAnyonePostedStaysOnTheEmptyPage() async throws {
    let book = FakePlaceBook()
    await book.nobodyPosted()
    let page = try store(book)
    await page.load()
    await page.rate(5)
    #expect(page.myStars == 5)
    #expect(page.page?.myStars == 5)
}
