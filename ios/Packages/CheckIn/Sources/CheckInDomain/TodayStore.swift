import Contracts
import Foundation
import Observation

/// The home and 打卡's data: the squad's today as last loaded, with the member's own posts
/// counted at once, and the check-ins still waiting to go out. Screens bind to it; it never
/// reads the clock or makes ids itself, so tests pass both.
///
/// A post gets its id, day and time when the member makes it and goes into the outbox before
/// anything is sent. Sending uploads its photos, then saves it under that id; when the network
/// fails it stays in the outbox, still counted on the home, and goes out on the next `load()`,
/// `sendPending()` or post. Saving the same id twice saves it once, so a retry is always safe.
@MainActor @Observable
public final class TodayStore {
    /// Where loading stands.
    public enum Phase: Equatable, Sendable {
        /// Nothing loaded yet.
        case loading
        /// The home is the server's, as of the last load.
        case current
        /// The server couldn't be reached; the home is the copy kept on the device, if any.
        case offline
        /// The member is in no squad.
        case noSquad
        /// The member is signed out.
        case signedOut
    }

    /// What happened to a post.
    public enum PostOutcome: Equatable, Sendable {
        /// The server saved it.
        case posted(CheckIn)
        /// It couldn't go out yet; it is kept and counted, and goes out later.
        case queued
    }

    /// A post the server refused while it was being sent later: it is dropped, and the member
    /// should hear why.
    public struct Refused: Hashable, Sendable {
        public let pending: PendingCheckIn
        public let reason: CheckInError
    }

    public private(set) var phase = Phase.loading
    /// The home as the server last sent it, with the posts it saved since folded in.
    public internal(set) var savedHome: Home?
    /// Posts not yet saved, oldest first.
    public internal(set) var pending: [PendingCheckIn] = []
    /// Posts dropped because the server refused them while they went out late.
    public internal(set) var refused: [Refused] = []
    /// Reactions on check-ins loaded with `loadReactions(to:)`, by check-in.
    public private(set) var reactions: [CheckInID: [Reaction]] = [:]
    /// Whom the member patted today (拍一拍) and who patted them in the last day, as last loaded.
    public private(set) var pokes = SquadPokes.none
    /// The squad's coach on the sideline as last loaded, and the squad it was loaded for.
    /// Set only by `loadCoach()`.
    var loadedCoach: (squad: SquadID, coach: SidelineCoach?)?
    /// The coaches' morning notes (便条) waiting for the member, as last loaded, newest first:
    /// the dot on the coach's phone until the member sees them on the coach's page.
    public internal(set) var coachNotes: [CoachMemberNote] = []
    /// The challenge in today's morning note, as last loaded, for the squad it was loaded for.
    var loadedChallenge: (squad: SquadID, challenge: DayChallenge?)?
    /// 我完成了 is on its way.
    public internal(set) var isCompletingChallenge = false
    /// The coaches changing on the sideline (换教练), from the captain's confirm until the coach
    /// that took over stands there.
    public internal(set) var handover: CoachHandover?
    /// A letter opened again from 通知 or the coach's 简历.
    var letterAgain: CoachLetter?
    /// The newest letter opened on this phone; nil before it is read from the device, or before any.
    var openedLetterID: Int?
    /// What changed in the squad since the home shown before, not yet told (`takeNews()`).
    public internal(set) var news = SquadNews()
    /// The squad the member was in when the server last said they are in none: they left it, or
    /// the captain removed them.
    public private(set) var lostSquad: Squad?
    /// Stores and props the member unlocked that the home hasn't told yet, the earliest first
    /// (`takeUnlocks()`).
    public internal(set) var unlocked: [Unlock] = []

    let backend: any CheckInBackend
    let ledger: (any UnlockLedger)?
    /// The last unlock check, so the next waits for it and none tells an unlock twice.
    var unlockCheck: Task<Void, Never>?
    /// Photos an edit already uploaded, by the picked photo, so its retry sends each once.
    var editUploads: [UUID: PhotoRef] = [:]
    let outbox: any Outbox
    let now: @Sendable () -> Date
    let newID: @Sendable () -> UUID
    /// The outbox's send under way, so two never run at once.
    var draining: Task<Void, Never>?
    /// Posts someone waits on (`post`, `deliver`), and what the drain found became of them.
    var awaited: Set<CheckInID> = []
    var fates: [CheckInID: Fate] = [:]

    public init(
        backend: any CheckInBackend, outbox: any Outbox, unlocks ledger: (any UnlockLedger)? = nil,
        now: @escaping @Sendable () -> Date, newID: @escaping @Sendable () -> UUID
    ) {
        self.backend = backend
        self.ledger = ledger
        self.outbox = outbox
        self.now = now
        self.newID = newID
    }

    // MARK: - Reading

    /// The home to show: the server's, moved on to the member's day if it is from an earlier
    /// one, with every post still waiting counted.
    public var home: Home? {
        guard let saved = savedHome, let day else { return nil }
        var home = saved.rolled(to: day)
        for (index, post) in pending.enumerated() {
            home.today = home.today.countingMine(post, squadSaw: home.squadSees(on: post.day, plus: pending[..<index]))
        }
        return home
    }

    /// The member's day now, in their profile's time zone.
    public var day: LocalDay? {
        savedHome.map { LocalDay(at: now(), in: $0.timeZone) }
    }

    /// Where the member's day stands. Not checked in until the home is loaded.
    public var myStatus: TrainingStatus {
        guard let mine = home?.mine, mine.day == day else { return .notCheckedIn }
        return mine.training
    }

    /// The sport a new 练了 starts with: today's in the plan, else the latest 练了.
    public var suggestedActivity: Activity? {
        guard let home, let day else { return nil }
        return home.suggestedActivity(on: day)
    }

    /// 常用运动, for the sport picker.
    public var recentActivities: [Activity] { home?.recentActivities() ?? [] }

    // MARK: - Loading

    /// Shows the copy kept on the device at once, then loads the server's and sends any post
    /// still waiting.
    public func load() async {
        if savedHome == nil {
            savedHome = await backend.savedHome()
            pending = await outbox.load()
        }
        await refresh()
        await loadPokes()
        await loadCoach()
        await sendPending()
        // A member who travelled takes the phone's zone once their waiting posts are out, as each
        // one's day was made in the old zone. Best effort: the home stays as it is if it fails.
        if pending.isEmpty, (try? await backend.followPhoneZone()) == true { await refresh() }
        await checkUnlocks()
    }

    /// Loads the server's home; keeps the one shown when the server can't be reached. A post
    /// saved while the load was on its way, and missing from what it read, is counted again.
    public func refresh() async {
        do {
            if let fresh = try await backend.home() {
                let earlier = savedHome
                savedHome = fresh
                news = news.adding(SquadNews(from: earlier, to: fresh))
                lostSquad = nil
                for saved in earlier?.checkIns ?? [] where saved.member == fresh.member && saved.day == day {
                    fold(saved)
                }
                phase = .current
                // An accepted challenge follows the server each reread: done by the coach meanwhile,
                // or gone once the squad's day is over.
                if acceptedChallenge != nil, let home = savedHome { await loadChallenge(in: home) }
            } else {
                if let squad = savedHome?.squad { lostSquad = squad }
                savedHome = nil
                phase = .noSquad
            }
        } catch .signedOut {
            phase = .signedOut
        } catch {
            phase = .offline
        }
    }

    // MARK: - Reactions

    /// Loads who reacted to a check-in.
    public func loadReactions(to checkIn: CheckInID) async throws(CheckInError) {
        reactions[checkIn] = try await backend.reactions(to: checkIn)
    }

    /// The member's own reaction on a check-in, if any.
    public func myReaction(on checkIn: CheckInID) -> Emoji? {
        guard let member = savedHome?.member else { return nil }
        return reactions[checkIn]?.first { $0.member == member }?.emoji
    }

    /// Sets the member's reaction, shown at once and taken back if the server says no.
    public func react(_ emoji: Emoji, to checkIn: CheckInID) async throws(CheckInError) {
        guard let member = savedHome?.member else { throw .notSent }
        let before = reactions[checkIn]
        var after = (before ?? []).filter { $0.member != member }
        after.append(Reaction(member: member, emoji: emoji, reactedAt: Timestamp(now())))
        reactions[checkIn] = after
        do {
            try await backend.react(emoji, to: checkIn)
        } catch {
            reactions[checkIn] = before
            throw error
        }
    }

    /// Takes the member's reaction back, at once, and restores it if the server says no.
    public func removeReaction(from checkIn: CheckInID) async throws(CheckInError) {
        guard let member = savedHome?.member else { throw .notSent }
        let before = reactions[checkIn]
        reactions[checkIn] = before?.filter { $0.member != member }
        do {
            try await backend.removeReaction(from: checkIn)
        } catch {
            reactions[checkIn] = before
            throw error
        }
    }

    // MARK: - 拍一拍

    /// Loads whom the member patted today and who patted them; keeps what was shown when the
    /// server can't be reached.
    public func loadPokes() async {
        guard let squad = savedHome?.squad.id, phase == .current else { return }
        do {
            let fresh = try await backend.pokes(in: squad)
            // A pat sent today while the load was on its way stays counted.
            let mine = patsSent?.day == day ? patsSent?.members ?? [] : []
            pokes = SquadPokes(sent: fresh.sent.union(mine), received: fresh.received)
        } catch {}
    }

    /// The pats sent from this phone today, so a load that read the server before one landed
    /// doesn't show it as not sent.
    private var patsSent: (day: LocalDay, members: Set<MemberID>)?

    /// Pats a teammate (拍一拍): counted as patted at once, so the button turns 拍过了, and taken
    /// back if the server says no or can't be reached, so it can be tried again.
    public func pat(_ member: MemberID) async throws(CheckInError) {
        guard canPat(member), let squad = savedHome?.squad.id, let today = day else { return }
        pokes.sent.insert(member)
        var sentToday = patsSent?.day == today ? patsSent?.members ?? [] : []
        sentToday.insert(member)
        patsSent = (today, sentToday)
        do {
            try await backend.pat(member, in: squad)
        } catch {
            pokes.sent.remove(member)
            patsSent?.members.remove(member)
            throw error
        }
    }
}

extension TodayStore {
    /// Whether the member can pat `member` now: a teammate on the home not patted yet today.
    public func canPat(_ member: MemberID) -> Bool {
        guard let home, member != home.member, home.today.members.contains(where: { $0.member == member })
        else { return false }
        return !pokes.sent.contains(member)
    }
}
