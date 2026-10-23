import Contracts
import FeedDomain
import Foundation

func member(_ number: Int) -> MemberID { MemberID(uuid(number)) }
func checkInID(_ number: Int) -> CheckInID { CheckInID(uuid(1000 + number)) }
let squad = SquadID(uuid(9000))

func uuid(_ number: Int) -> UUID {
    let tail = String(number)
    let padded = String(repeating: "0", count: 12 - tail.count) + tail
    guard let id = UUID(uuidString: "00000000-0000-4000-8000-\(padded)") else { fatalError("bad test uuid \(number)") }
    return id
}

func day(_ text: String) -> LocalDay {
    do { return try LocalDay(text) } catch { fatalError("bad test day \(text)") }
}

/// Seconds after 2026-10-20T00:00:00Z.
func at(_ seconds: Int64) -> Timestamp { Timestamp(millisecondsSince1970: 1_792_454_400_000 + seconds * 1000) }

func checkIn(_ number: Int, by author: MemberID, on onDay: String, at moment: Int64 = 0, disclaimer: Bool = false)
    -> CheckIn
{
    do {
        let entry: CheckIn.Entry =
            disclaimer ? .disclaimer(try Disclaimer("腿说今天它请假")) : .trained(Training(activity: .sport(.run)))
        return CheckIn(
            id: checkInID(number), member: author, day: day(onDay), createdAt: at(moment),
            audience: try Audience([squad]),
            entry: entry)
    } catch { fatalError("bad test check-in") }
}

func emoji(_ text: String) -> Emoji {
    do { return try Emoji(text) } catch { fatalError("not an emoji: \(text)") }
}

func reactions(_ pairs: [(MemberID, String, Int64)]) -> Responses<Emoji> {
    Responses(pairs.map { .init(member: $0.0, kind: emoji($0.1), moment: at($0.2)) })
}

/// The squad's posts in memory, recording every response sent. A call can be held until
/// `release()`, and fail with `failure`.
actor FakeSource: FeedSource {
    enum Call: Equatable {
        case posts(LocalDay, LocalDay)
        case reaction(Emoji?, CheckInID)
    }

    private(set) var calls: [Call] = []
    var posts: [FeedPost]
    var failure: FeedError?
    var characters: [MemberID: MemberCharacter] = [:]
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(_ posts: [FeedPost], failing failure: FeedError? = nil) {
        self.posts = posts
        self.failure = failure
    }

    func fail(with error: FeedError?) { failure = error }
    func setCharacters(_ characters: [MemberID: MemberCharacter]) { self.characters = characters }
    func setPosts(_ posts: [FeedPost]) { self.posts = posts }
    func hold() { holding = true }
    func release() {
        holding = false
        held.forEach { $0.resume() }
        held = []
    }
    var waiting: Int { held.count }

    func posts(in squad: SquadID, from first: LocalDay, through last: LocalDay) async throws(FeedError) -> [FeedPost] {
        calls.append(.posts(first, last))
        if let failure { throw failure }
        return posts.filter { (first...last).contains($0.checkIn.day) }
    }

    func characters(in squad: SquadID) async throws(FeedError) -> [MemberID: MemberCharacter] {
        if let failure { throw failure }
        return characters
    }

    func photo(_ ref: PhotoRef) async -> Data? { nil }

    func setReaction(_ emoji: Emoji?, on checkIn: CheckInID) async throws(FeedError) {
        calls.append(.reaction(emoji, checkIn))
        await wait()
        if let failure { throw failure }
    }

    private func wait() async {
        guard holding else { return }
        await withCheckedContinuation { held.append($0) }
    }
}
