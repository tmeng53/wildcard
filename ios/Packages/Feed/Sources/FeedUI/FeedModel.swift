#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import Foundation
import Observation
import SportsUI
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
    /// What the squad's coach said: its 战术板 line and its replies. Nil where nobody asks it
    /// (the sample squad without a coach).
    let coach: FeedCoach?
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
    /// The post whose own page is open over the feed, with its comments. The app hides its tab
    /// bar while one is.
    public var opened: CheckInID?
    /// Whom the member's next comment replies to (回复 Mia：…), on the open page.
    var replyingTo: ReplyTarget?
    /// Bumps on each comment the member sends, for its haptic.
    var commentsSent = 0
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
    /// Edits and deletes the member's own posts; without one, posts show no 「…」.
    let editor: (any PostEditing)?
    /// Told each change the member makes to one of their posts here, for the other screens that
    /// show it (我的动态 under a post opened from it).
    public var changed: ((PostChange) -> Void)?
    /// The compose page open on one of the member's posts, to edit it.
    var editing: ComposeModel?
    /// The member's post they asked to delete, waiting for them to confirm.
    var confirmingDelete: CheckInID?
    /// The last delete didn't go through.
    var deleteFailed = false

    /// Each player with the outfit it wears, so a look that changed since builds a new one.
    @ObservationIgnored private var players: [CheckInID: (outfit: Outfit, persona: Persona, player: CharacterPlayer)] =
        [:]
    @ObservationIgnored private var heads: [MemberID: (outfit: Outfit, player: CharacterPlayer)] = [:]
    /// The coaches' characters, by coach, for their heads and the 战术板.
    @ObservationIgnored var coachPlayers: [CoachID: CharacterPlayer] = [:]
    @ObservationIgnored private var flightCount = 0
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored let defaults: UserDefaults

    public init(
        store: FeedStore, viewer: MemberID, editor: (any PostEditing)? = nil, coach: FeedCoach? = nil,
        now: @escaping () -> Date = { Date() },
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.viewer = viewer
        self.editor = editor
        self.coach = coach
        self.now = now
        self.defaults = defaults
        recent = (defaults.stringArray(forKey: Self.recentKey) ?? []).compactMap { try? Emoji($0) }
    }

    // MARK: - Loading

    public func load() async {
        hasNews = false
        await store.load()
        answerArrivals()
        if store.phase == .current, let latest = store.latestNews { keepNewsSeen(until: latest) }
        await store.sendResponses()
        // Last, so a slow coach never holds up the member's own reactions or the news dot.
        await coach?.load(about: store.sections.flatMap { $0.posts.map(\.id) })
    }

    // MARK: - The tab's dot

    /// Whether 动态 has news since the member last opened it (`FeedPost.latestNews(for:)`): the
    /// tab's dot. Opening 动态 clears it.
    public private(set) var hasNews = false

    /// Looks for news while 动态 isn't open. What was seen is kept by the news's own time, never
    /// the phone's clock; the first look on this phone takes what is there as seen.
    public func checkNews() async {
        guard let latest = await store.latestNewsOnServer() else { return }
        guard let seen = defaults.object(forKey: Self.newsSeenKey(viewer)) as? Double else {
            keepNewsSeen(until: latest)
            return
        }
        hasNews = Double(latest.millisecondsSince1970) > seen
    }

    private func keepNewsSeen(until latest: Timestamp) {
        let key = Self.newsSeenKey(viewer)
        let seen = defaults.object(forKey: key) as? Double ?? -.infinity
        defaults.set(max(seen, Double(latest.millisecondsSince1970)), forKey: key)
    }

    private static func newsSeenKey(_ viewer: MemberID) -> String { "feed.newsSeen.\(viewer)" }

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
        announce(String(localized: "\(who)回应了你：\(newest.emoji.text)", bundle: .module.inAppLanguage))
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
        let index = Int((point.x - bar.minX - ReactionBarMetrics.inset) / Sizing.minimumTapTarget)
        return EmojiBar.common.indices.contains(index) ? index : nil
    }

    /// Where a slot's emoji sits, to fly from.
    func slotCenter(_ index: Int) -> CGPoint? {
        guard let bar = barFrame else { return nil }
        return ReactionBarMetrics.slotCenter(index, in: bar)
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
                announce(String(localized: "\(author)收到了\(mine.text)", bundle: .module.inAppLanguage))
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

    private static var teammate: String { String(localized: "队友", bundle: .module.inAppLanguage) }
    private static let recentKey = "feed.recentEmoji"
    private static let recentLimit = 24
    private static func seenKey(_ viewer: MemberID) -> String { "feed.reactionsSeen.\(viewer)" }

    // MARK: - Characters

    /// The author's character on a post, doing what the post is about, as the home does it: on a
    /// 练了 that day's sport, in its kit and looping its move (`kits.json`, as every screen plays a
    /// sport), on a meal eating it from the bowl or the boba, on a 请假条 holding it up (the card
    /// draws the sign), each at the persona's tempo. A reaction's move plays over any of them.
    func player(for post: FeedPost) -> CharacterPlayer? {
        let character = store.characters[post.author]
        let persona = character?.look.moves ?? .energetic
        let look = character?.look.outfit ?? PlaceholderCharacter.lifter
        let (outfit, loop) = Self.dressing(post, look: look, persona: persona)
        if let cached = players[post.id], cached.outfit == outfit, cached.persona == persona { return cached.player }
        guard let figure = try? PlaceholderCharacter.figure(wearing: outfit),
            let player = try? CharacterPlayer(figure: figure, idle: loop ?? .still, now: now())
        else { return nil }
        players[post.id] = (outfit, persona, player)
        return player
    }

    /// Whether the post's character loops something at rest, so its card keeps drawing it.
    func loops(_ post: FeedPost) -> Bool {
        if case .trained(let training) = post.checkIn.entry {
            return Self.kits?.kit(for: training.activity, in: SportList.shared.catalog) != nil
        }
        return true
    }

    /// Whether the post's character holds up a 请假条, which the card draws over it.
    func holdsSign(_ post: FeedPost) -> Bool {
        if case .disclaimer = post.checkIn.entry { true } else { false }
    }

    /// What the author wears and loops for `post`; no loop when the art can't play one.
    private static func dressing(_ post: FeedPost, look: Outfit, persona: Persona) -> (outfit: Outfit, loop: Clip?) {
        switch post.checkIn.entry {
        case .trained(let training):
            guard let kit = kits?.kit(for: training.activity, in: SportList.shared.catalog) else { return (look, nil) }
            return (kit.dress(look), try? PlaceholderCharacter.move(for: kit, persona: persona))
        case .healthyMeal:
            return eating(.healthyMeal, look: look, persona: persona)
        case .cheatMeal:
            return eating(.treatMeal, look: look, persona: persona)
        case .disclaimer:
            return (look, try? PlaceholderCharacter.holdingSign(persona: persona))
        }
    }

    private static func eating(_ meal: CheckInMove, look: Outfit, persona: Persona) -> (outfit: Outfit, loop: Clip?) {
        (PlaceholderCharacter.dressed(look, for: meal), try? PlaceholderCharacter.mealLoop(meal, persona: persona))
    }

    private static let kits = try? PlaceholderCharacter.sportKits()

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

    /// How a comment names someone: 我, their nickname, or 队友 when it isn't known.
    func displayName(of member: MemberID) -> String {
        if member == viewer { return String(localized: "我", bundle: .module.inAppLanguage) }
        return name(of: member) ?? String(localized: "队友", bundle: .module.inAppLanguage)
    }

    /// The move has finished: the character goes back to its idle.
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
