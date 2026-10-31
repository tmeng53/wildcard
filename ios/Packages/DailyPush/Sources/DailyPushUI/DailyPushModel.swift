#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DailyPushDomain
import DesignSystemUI
import FeedDomain
import Foundation
import Observation
import SportsUI

/// The push view's state over its `DailyPushStore`: which post's emoji bar is open, the emoji
/// in flight to its author, and the move the author's character plays. Only the character
/// reacted to moves; the rest hold still, drawn once.
@MainActor @Observable
public final class DailyPushModel {
    /// A move an author's character plays, counted so the same one again plays again.
    struct Played: Equatable {
        let count: Int
        let until: Date
    }

    /// An emoji flying from the bar to the author's head.
    struct Flight: Equatable {
        let count: Int
        let emoji: Emoji
        let from: CGPoint
        let target: CGPoint
    }

    let store: DailyPushStore
    /// When the push arrived, shown in the header.
    let arrived: Date
    /// The post whose emoji bar is open.
    var picking: CheckInID?
    /// Every emoji, over the push, for the post being picked on.
    var browsing = false
    private(set) var flight: Flight?
    private(set) var played: [CheckInID: Played] = [:]
    /// The emoji over a character after it landed, counted so it shows again.
    private(set) var bubbles: [CheckInID: (count: Int, emoji: Emoji)] = [:]

    /// Where each post's smiley and author are in `DailyPushView.space`. Not observed: the bar and
    /// the flight read them only when they start.
    @ObservationIgnored var buttons: [CheckInID: CGRect] = [:]
    @ObservationIgnored var figures: [CheckInID: CGRect] = [:]
    @ObservationIgnored private let looks: [MemberID: CharacterLook]
    @ObservationIgnored private let open: @MainActor (PushDestination) -> Void
    @ObservationIgnored private var players: [CheckInID: CharacterPlayer] = [:]
    @ObservationIgnored private var heads: [MemberID: CharacterPlayer] = [:]
    @ObservationIgnored private var standing: [MemberID: CharacterPlayer] = [:]
    @ObservationIgnored private let now: () -> Date

    /// The flight's length, then the bubble's.
    static let flightTime = 0.45
    static let bubbleTime = 1.5

    /// - Parameters:
    ///   - looks: squadmates' looks the app kept for the push (a member missing wears a stand-in).
    ///   - open: opens the app at a destination.
    public init(
        store: DailyPushStore, arrived: Date, looks: [MemberID: CharacterLook],
        open: @escaping @MainActor (PushDestination) -> Void, now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.arrived = arrived
        self.looks = looks
        self.open = open
        self.now = now
    }

    var push: DailyPush { store.push }

    func go(_ destination: PushDestination) { open(destination) }

    /// What a member is called; a stand-in before they made their character.
    func name(of member: MemberID) -> String {
        if member == push.viewer { return String(localized: "我", bundle: .module.inAppLanguage) }
        return push.name(of: member) ?? String(localized: "队友", bundle: .module.inAppLanguage)
    }

    /// Teammates for the squad standing on an empty day: up to four, me left out.
    var teammates: [MemberID] {
        let known = looks.keys.filter { $0 != push.viewer }.sorted { $0.description < $1.description }
        let named = push.members.filter { $0 != push.viewer }
        return Array((named + known.filter { !named.contains($0) }).prefix(4))
    }

    // MARK: - Reacting

    /// The member picked an emoji on a post: it flies to the author, pops over them, and their
    /// character plays its move. The same emoji again takes it back, with no move.
    func pick(_ emoji: Emoji, on id: CheckInID, from point: CGPoint) {
        picking = nil
        browsing = false
        guard let move = try? store.pick(emoji, on: id) else { return }
        let target = figures[id].map { CGPoint(x: $0.midX, y: $0.minY + $0.height * 0.25) } ?? point
        let count = (flight?.count ?? 0) + 1
        flight = Flight(count: count, emoji: emoji, from: point, target: target)
        Task {
            try? await Task.sleep(for: .seconds(Self.flightTime))
            guard flight?.count == count else { return }
            flight = nil
            bubbles[id] = ((bubbles[id]?.count ?? 0) + 1, emoji)
            play(move, on: id)
        }
    }

    /// The bubble over a character has shown long enough.
    func bubbleDone(_ id: CheckInID, count: Int) {
        if bubbles[id]?.count == count { bubbles[id] = nil }
    }

    /// The move has finished: the character holds still again.
    func finished(_ id: CheckInID, count: Int) {
        if played[id]?.count == count { played[id] = nil }
    }

    private func play(_ move: MoveID, on id: CheckInID) {
        guard let post = store.post(id), let player = player(for: post) else { return }
        let persona = looks[post.author].map(Persona.init) ?? .energetic
        let species = PlaceholderCharacter.species(of: outfit(of: post.author))
        guard
            let clip = PlaceholderCharacter.reactionMove(move.id, persona: persona)
                ?? (try? PlaceholderCharacter.clip("cheer", persona: persona, species: species))
        else { return }
        let start = now()
        try? player.play(clip, now: start)
        played[id] = Played(count: (played[id]?.count ?? 0) + 1, until: start.addingTimeInterval(clip.duration))
    }

    // MARK: - Characters

    /// The author's character on a post, in that day's kit on a 练了.
    func player(for post: PushPost) -> CharacterPlayer? {
        if let player = players[post.id] { return player }
        var outfit = outfit(of: post.author)
        if case .trained(let activity?) = post.entry, let kits = try? PlaceholderCharacter.sportKits() {
            outfit = kits.kit(for: activity, in: SportList.shared.catalog).dress(outfit)
        }
        guard let player = Self.still(outfit, now: now()) else { return nil }
        players[post.id] = player
        return player
    }

    /// A member's head, for the reaction row and who patted.
    func head(of member: MemberID) -> CharacterPlayer? {
        if let player = heads[member] { return player }
        guard let player = Self.still(outfit(of: member), now: now()) else { return nil }
        heads[member] = player
        return player
    }

    /// A teammate standing, on an empty day.
    func standing(_ member: MemberID) -> CharacterPlayer? {
        if let player = standing[member] { return player }
        guard let player = Self.still(outfit(of: member), now: now()) else { return nil }
        standing[member] = player
        return player
    }

    private func outfit(of member: MemberID) -> Outfit {
        looks[member].map(Outfit.init) ?? PlaceholderCharacter.lifter
    }

    private static func still(_ outfit: Outfit, now: Date) -> CharacterPlayer? {
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit) else { return nil }
        return try? CharacterPlayer(figure: figure, idle: .still, now: now)
    }
}
#endif
