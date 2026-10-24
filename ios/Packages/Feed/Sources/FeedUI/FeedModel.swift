#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import FeedDomain
import Foundation
import Observation
import SwiftUI

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

    /// An emoji on its way to the author's head: from a slot of the bar, or as the big ❤️ from
    /// where a photo was double-tapped. Points are in `FeedView.space`.
    struct Flight: Equatable, Identifiable {
        let id: Int
        let post: CheckInID
        let emoji: Emoji
        let from: CGPoint
        /// The double tap's heart: it pops big where the finger was before it flies.
        let big: Bool
    }

    /// A teammate's reaction on one of my posts, shown in a bubble over my character.
    struct Bubble: Equatable {
        let count: Int
        let arrival: Arrival
    }

    /// How long an emoji flies from the bar to the head.
    static let flight: Double = 0.45
    /// How long the double tap's heart pops and holds before it flies.
    static let bigHold: Double = 0.55
    /// How long the bubble stays over my character after its move.
    static let bubbleHold: Double = 1.6

    let store: FeedStore
    let viewer: MemberID
    /// The post whose emoji bar is open.
    var picking: CheckInID?
    /// The bar was opened by pressing and holding the card: the card lifts over the blurred feed,
    /// and sliding along the bar picks.
    var lifted = false
    /// The bar's slot under the finger while holding, which grows.
    var hovering: Int?
    /// Where the open bar is, in `FeedView.space`, for the slide to pick.
    var barFrame: CGRect?
    /// The post whose who-reacted panel is open.
    var listing: CheckInID?
    /// The post to scroll to next: one opened from the home.
    var focus: CheckInID?
    private(set) var played: [CheckInID: Played] = [:]
    private(set) var flights: [Flight] = []
    private(set) var bubbles: [CheckInID: Bubble] = [:]
    /// The emoji the member picked lately, newest first, for the grid's 最近.
    private(set) var recent: [Emoji]
    /// Bumps on each emoji the member leaves, for its haptic.
    private(set) var picks = 0
    /// Bumps when a teammate's reaction on my post arrives, for its haptic.
    private(set) var arrivals = 0
    /// Bumps when the bar opens by holding a card, for its haptic.
    private(set) var lifts = 0

    /// Each player with the outfit it wears, so a look that changed since builds a new one.
    @ObservationIgnored private var players: [CheckInID: (outfit: Outfit, player: CharacterPlayer)] = [:]
    @ObservationIgnored private var heads: [MemberID: (outfit: Outfit, player: CharacterPlayer)] = [:]
    @ObservationIgnored private var flightCount = 0
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let defaults: UserDefaults

    public init(
        store: FeedStore, viewer: MemberID, now: @escaping () -> Date = { Date() }, defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.viewer = viewer
        self.now = now
        self.defaults = defaults
        recent = (defaults.stringArray(forKey: Self.recentKey) ?? []).compactMap { try? Emoji($0) }
    }

    // MARK: - Loading

    public func load() async {
        await store.load()
        answerArrivals()
        await store.sendResponses()
    }

    /// Teammates' reactions on my posts since 动态 last showed them: my character answers each
    /// with its move, under a bubble with their head and emoji. What was shown is kept by the
    /// server's time of the newest reaction, never the phone's clock, which may be off.
    private func answerArrivals() {
        guard store.phase == .current else { return }
        let key = Self.seenKey(viewer)
        let seen = (defaults.object(forKey: key) as? Double).map { Timestamp(millisecondsSince1970: Int64($0)) }
        let latest = store.arrivals(since: Timestamp(millisecondsSince1970: .min))
        if let newest = latest.first?.moment, seen.map({ newest > $0 }) ?? true {
            defaults.set(Double(newest.millisecondsSince1970), forKey: key)
        } else if seen == nil {
            // Opened with nothing yet: the first reaction to come is news.
            defaults.set(0.0, forKey: key)
        }
        // The first time 动态 opens on this phone, what was there before isn't news.
        guard let seen else { return }
        let arrived = latest.filter { $0.moment > seen }
        guard let newest = arrived.first else { return }
        for arrival in arrived {
            guard let post = store.post(arrival.post) else { continue }
            let count = (bubbles[arrival.post]?.count ?? 0) + 1
            bubbles[arrival.post] = Bubble(count: count, arrival: arrival)
            play(MoveID(arrival.emoji), on: post)
        }
        arrivals += 1
        let who = name(of: newest.member) ?? Self.teammate
        announce(String(localized: "\(who)回应了你：\(newest.emoji.text)", bundle: .module))
    }

    /// The bubble has shown long enough.
    func bubbleShown(_ post: CheckInID, count: Int) {
        if bubbles[post]?.count == count { bubbles[post] = nil }
    }

    /// Opens 动态 on a post the member just made: shown even before the server lists it.
    public func open(_ checkIn: CheckIn?) {
        guard let checkIn else { return }
        store.show(checkIn)
        focus = checkIn.id
    }

    // MARK: - Reacting

    /// Opens the emoji bar on a post; holding the card lifts it.
    func openBar(on post: CheckInID, lifted: Bool) {
        listing = nil
        hovering = nil
        barFrame = nil
        picking = post
        self.lifted = lifted
        if lifted { lifts += 1 }
    }

    func closeBar() {
        picking = nil
        lifted = false
        hovering = nil
        barFrame = nil
    }

    /// The bar's slot at `point` (in `FeedView.space`) while sliding along it, if any: a little
    /// above and below the bar counts, as a finger covers what it's on.
    func slot(at point: CGPoint) -> Int? {
        guard let bar = barFrame, bar.insetBy(dx: 0, dy: -Space.l).contains(point) else { return nil }
        let index = Int((point.x - bar.minX - EmojiBar.inset) / Sizing.minimumTapTarget)
        return EmojiBar.common.indices.contains(index) ? index : nil
    }

    /// Where a slot's emoji sits, to fly from.
    func slotCenter(_ index: Int) -> CGPoint? {
        guard let bar = barFrame else { return nil }
        return CGPoint(
            x: bar.minX + EmojiBar.inset + (Double(index) + 0.5) * Sizing.minimumTapTarget, y: bar.midY)
    }

    /// Leaves or swaps the member's emoji on a post: it flies from `from` to the author's head,
    /// which then plays its move, and it goes out behind. The same emoji again takes it back:
    /// nothing flies and nothing moves.
    func react(_ gesture: ReactionGesture, on post: FeedPost, from point: CGPoint? = nil) {
        closeBar()
        do {
            let move = try store.react(gesture, on: post.id)
            if let move, let mine = store.post(post.id)?.reactions.kind(of: viewer) {
                remember(mine)
                let big = gesture == .doubleTap
                if let point {
                    flightCount += 1
                    let flight = Flight(id: flightCount, post: post.id, emoji: mine, from: point, big: big)
                    flights.append(flight)
                    Task {
                        try? await Task.sleep(for: .seconds((big ? Self.bigHold : 0) + Self.flight))
                        flights.removeAll { $0.id == flight.id }
                        play(move, on: post)
                    }
                } else {
                    play(move, on: post)
                }
                let author = name(of: post.author) ?? Self.teammate
                announce(String(localized: "\(author)收到了\(mine.text)", bundle: .module))
            }
            picks += 1
        } catch {
            return
        }
        Task { await store.sendResponses() }
    }

    private func remember(_ emoji: Emoji) {
        recent = Array(([emoji] + recent.filter { $0 != emoji }).prefix(Self.recentLimit))
        defaults.set(recent.map(\.text), forKey: Self.recentKey)
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(AttributedString(text)).post()
    }

    private static var teammate: String { String(localized: "队友", bundle: .module) }
    private static let recentKey = "feed.recentEmoji"
    private static let recentLimit = 24
    private static func seenKey(_ viewer: MemberID) -> String { "feed.reactionsSeen.\(viewer)" }

    // MARK: - Characters

    /// The author's character on a post: their look, in that day's kit on a 练了, holding still
    /// until someone reacts.
    func player(for post: FeedPost) -> CharacterPlayer? {
        let character = store.characters[post.author]
        var outfit = character?.look.outfit ?? PlaceholderCharacter.lifter
        if case .trained(let training) = post.checkIn.entry, let kits = try? PlaceholderCharacter.sportKits() {
            outfit = kits.kit(for: training.activity).dress(outfit)
        }
        if let cached = players[post.id], cached.outfit == outfit { return cached.player }
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let player = try? CharacterPlayer(figure: figure, idle: .still, now: now())
        else { return nil }
        players[post.id] = (outfit, player)
        return player
    }

    /// The character's head, for the faces in a reaction row.
    func head(of member: MemberID) -> CharacterPlayer? {
        let outfit = store.characters[member]?.look.outfit ?? PlaceholderCharacter.lifter
        if let cached = heads[member], cached.outfit == outfit { return cached.player }
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let player = try? CharacterPlayer(figure: figure, idle: .still, now: now())
        else { return nil }
        heads[member] = (outfit, player)
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
            let clip = PlaceholderCharacter.reactionMove(move.id, persona: persona)
                ?? (try? PlaceholderCharacter.clip("cheer", persona: persona, species: species))
        else { return }
        let start = now()
        try? player.play(clip, now: start)
        played[post.id] = Played(
            count: (played[post.id]?.count ?? 0) + 1, until: start.addingTimeInterval(clip.duration))
    }
}
#endif
