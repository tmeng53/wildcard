import Contracts
import Observation

/// What a place's page shows (地点页): the page as the server worked it out, and the member's own
/// score, which shows at once when they tap a star and goes back if it couldn't be saved.
@MainActor @Observable
public final class PlacePageStore {
    public enum Phase: Equatable, Sendable {
        case loading
        case shown
        /// The page couldn't be read, and there is none to show from before.
        case failed
    }

    /// The place as the post tagged it, shown while its page loads.
    public let place: Place
    public let key: PlaceKey
    public private(set) var phase = Phase.loading
    /// The page; empty for a place nobody in the squad posted from yet.
    public private(set) var page: PlacePage?
    /// The member's score as it shows: their pick at once, the server's after.
    public private(set) var myStars: Int?
    /// The last score the member picked didn't go out; it is back to what it was.
    public private(set) var rateFailed = false

    private let book: any PlaceBook
    private let squad: SquadID

    public init(book: any PlaceBook, squad: SquadID, place: Place, key: PlaceKey) {
        (self.book, self.squad, self.place, self.key) = (book, squad, place, key)
    }

    /// Reads the page; one already shown stays when it can't be read again.
    public func load() async {
        do throws(FeedError) {
            let read = try await book.page(of: key, in: squad) ?? .empty(place, key: key, myStars: myStars)
            page = read
            myStars = read.myStars
            phase = .shown
        } catch {
            if page == nil { phase = .failed }
        }
    }

    /// Gives the member's score: it shows at once, then the page is read again for the squad's
    /// new average.
    public func rate(_ stars: Int) async {
        guard PlacePage.scores.contains(stars), stars != myStars else { return }
        let before = myStars
        myStars = stars
        rateFailed = false
        do throws(FeedError) {
            try await book.rate(key, stars: stars)
        } catch {
            // A later pick took over meanwhile: that one is the member's score now.
            guard myStars == stars else { return }
            myStars = before
            rateFailed = true
            return
        }
        await load()
    }
}
