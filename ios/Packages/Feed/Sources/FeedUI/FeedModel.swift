#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import FeedDomain
import Foundation
import Observation

/// The 动态 screen's state over its `FeedStore`: which post's emoji bar is open, the moves the
/// authors' characters play when someone reacts, and the post to scroll to. Reactions show at
/// once and go out behind.
@MainActor @Observable
public final class FeedModel {
    /// A move an author's character plays, counted so the same one again plays again.
    struct Played: Equatable {
        let count: Int
        let until: Date
    }

    /// The emoji that popped on a card, where it popped (nil for the card's corner).
    struct Pop: Equatable {
        let count: Int
        let emoji: Emoji
        let point: CGPoint?
    }

    let store: FeedStore
    let viewer: MemberID
    /// The post whose emoji bar is open.
    var picking: CheckInID?
    /// The post to scroll to next: one opened from the home.
    var focus: CheckInID?
    private(set) var played: [CheckInID: Played] = [:]
    private(set) var pops: [CheckInID: Pop] = [:]
    /// Bumps on each emoji the member leaves, for its haptic.
    private(set) var responses = 0

    @ObservationIgnored private var players: [CheckInID: CharacterPlayer] = [:]
    @ObservationIgnored private var heads: [MemberID: CharacterPlayer] = [:]
    @ObservationIgnored private let now: () -> Date

    public init(store: FeedStore, viewer: MemberID, now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.viewer = viewer
        self.now = now
    }

    // MARK: - Loading

    public func load() async {
        await store.load()
        await store.sendResponses()
    }

    /// Opens 动态 on a post the member just made: shown even before the server lists it.
    public func open(_ checkIn: CheckIn?) {
        guard let checkIn else { return }
        store.show(checkIn)
        focus = checkIn.id
    }

    // MARK: - Reacting

    /// Leaves or swaps the member's emoji on a post: it pops on the card, the author's character
    /// plays its move, and it goes out behind.
    func react(_ gesture: ReactionGesture, on post: FeedPost, at point: CGPoint? = nil) {
        picking = nil
        do {
            let move = try store.react(gesture, on: post.id)
            if let mine = store.post(post.id)?.reactions.kind(of: viewer) {
                pops[post.id] = Pop(count: (pops[post.id]?.count ?? 0) + 1, emoji: mine, point: point)
            }
            if let move { play(move, on: post) }
            responses += 1
        } catch {
            return
        }
        Task { await store.sendResponses() }
    }

    // MARK: - Characters

    /// The author's character on a post: their look, in that day's kit on a 练了, holding still
    /// until someone reacts.
    func player(for post: FeedPost) -> CharacterPlayer? {
        if let player = players[post.id] { return player }
        let character = store.characters[post.author]
        var outfit = character?.look.outfit ?? PlaceholderCharacter.lifter
        if case .trained(let training) = post.checkIn.entry, let kits = try? PlaceholderCharacter.sportKits() {
            outfit = kits.kit(for: training.activity).dress(outfit)
        }
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let player = try? CharacterPlayer(figure: figure, idle: .still, now: now())
        else { return nil }
        players[post.id] = player
        return player
    }

    /// The character's head, for the faces in a reaction row.
    func head(of member: MemberID) -> CharacterPlayer? {
        if let player = heads[member] { return player }
        let outfit = store.characters[member]?.look.outfit ?? PlaceholderCharacter.lifter
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let player = try? CharacterPlayer(figure: figure, idle: .still, now: now())
        else { return nil }
        heads[member] = player
        return player
    }

    /// What `member` is called: their nickname, else a stand-in until they make a character.
    func name(of member: MemberID) -> String? {
        store.characters[member]?.nickname.text
    }

    /// The move has finished: the character holds still again.
    func finished(_ post: CheckInID, count: Int) {
        if played[post]?.count == count { played[post] = nil }
    }

    private func play(_ move: MoveID, on post: FeedPost) {
        guard let player = player(for: post) else { return }
        let persona = store.characters[post.author]?.look.moves ?? .energetic
        let species = store.characters[post.author]?.look.species
        guard
            let clip = PlaceholderCharacter.reactionMove(move.id)
                ?? (try? PlaceholderCharacter.clip("cheer", persona: persona, species: species))
        else { return }
        let start = now()
        try? player.play(clip, now: start)
        played[post.id] = Played(
            count: (played[post.id]?.count ?? 0) + 1, until: start.addingTimeInterval(clip.duration))
    }
}
#endif
