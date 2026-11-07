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
    public private(set) var pending: [PendingCheckIn] = []
    /// Posts dropped because the server refused them while they went out late.
    public internal(set) var refused: [Refused] = []
    /// Reactions on check-ins loaded with `loadReactions(to:)`, by check-in.
    public private(set) var reactions: [CheckInID: [Reaction]] = [:]
    /// Whom the member patted today (拍一拍) and who patted them in the last day, as last loaded.
    public private(set) var pokes = SquadPokes.none
    /// The squad's coach on the sideline as last loaded, and the squad it was loaded for.
    /// Set only by `loadCoach()`.
    var loadedCoach: (squad: SquadID, coach: SidelineCoach?)?
    /// The coaches' morning notes (便条) waiting on 今天, as last loaded, the one to show first;
    /// one at a time, each until it is put away (`putAwayNote()`).
    public internal(set) var coachNotes: [CoachMemberNote] = []
    /// A note shown again from 通知, before any waiting.
    var noteAgain: CoachMemberNote?
    /// Notes put away on this phone since launch, kept out of a load that crossed the put-away.
    var putAway: Set<Int> = []
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
    private let outbox: any Outbox
    let now: @Sendable () -> Date
    private let newID: @Sendable () -> UUID
    /// Whether the outbox is being sent, so two sends never run at once.
    private var isDraining = false

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

    /// The member's day now, in their profile's time zone, with the 3am grace.
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

    // MARK: - Posting

    /// Posts a check-in, shared to the member's squad unless `shared` is false (which keeps it
    /// to the member), for `chosen`, today or one of the `backfillDays` before it
    /// (补打卡; today when left out): saved by the server now or, offline, later. Today's post
    /// counts on the home at once; a past day's once the server has it and the home is read again. Throws when it can never be saved: a 请假条 on a day with a 练了, a day
    /// out of reach, or a refusal from the server.
    @discardableResult
    public func post(_ draft: CheckInDraft, shared: Bool = true, on chosen: LocalDay? = nil)
        async throws(CheckInError) -> PostOutcome
    {
        if let chosen, !postableDays.contains(chosen) { throw .refused }
        try await check(draft, on: chosen)
        guard let home, let day else { throw .notSent }
        let audience: Audience
        do { audience = try Audience(shared ? [home.squad.id] : []) } catch { throw .refused }
        let post = PendingCheckIn(
            id: CheckInID(newID()), member: home.member, day: chosen ?? day, postedDay: day,
            createdAt: Timestamp(now()), audience: audience, draft: draft)
        pending.append(post)
        await outbox.save(pending)
        switch await drain(watching: post.id) {
        case .saved(let saved):
            // A past day's counts (my week, 出赛表) come from the server.
            if saved.isBackfill { await refresh() }
            // A 练了 is what opens a store or a prop; the payoff doesn't wait for the answer.
            if case .trained = saved.entry { Task { await checkUnlocks() } }
            return .posted(saved)
        case .refused(let reason): throw reason
        case .waiting: return .queued
        }
    }

    /// Sends every post still waiting, oldest first, and stops at the first that can't go out
    /// yet. One the server refuses is dropped and listed in `refused`.
    public func sendPending() async {
        await drain(watching: nil)
    }

    /// What became of the post a drain watched.
    private enum Fate {
        case saved(CheckIn)
        case refused(CheckInError)
        /// Still in the outbox, or going out with a drain already under way.
        case waiting
    }

    /// Sends the outbox oldest first, one post at a time, until it is empty or a post can't go
    /// out yet, so the server sees posts in the order they were made. Only one drain runs at
    /// once; it reads the outbox afresh after each post, so one made meanwhile goes out with it.
    /// A refusal is listed in `refused`, except the watched post's, which is returned.
    @discardableResult
    private func drain(watching watched: CheckInID?) async -> Fate {
        guard !isDraining else { return .waiting }
        isDraining = true
        defer { isDraining = false }
        var fate = Fate.waiting
        while let post = pending.first {
            do throws(CheckInError) {
                let saved = try await send(post)
                if post.id == watched { fate = .saved(saved) }
            } catch {
                if error == .notSent || error == .signedOut { return fate }
                if post.id == watched {
                    fate = .refused(error)
                } else {
                    refused.append(Refused(pending: post, reason: error))
                }
            }
        }
        return fate
    }

    /// Uploads the post's photos still to upload, then saves it. A refusal drops it from the
    /// outbox; a network failure keeps it.
    private func send(_ waiting: PendingCheckIn) async throws(CheckInError) -> CheckIn {
        var post = waiting
        let id = post.id
        do throws(CheckInError) {
            for photo in post.photosToUpload {
                post.uploaded[photo.id] = try await backend.upload(photo)
                await keep(post)
            }
            guard let checkIn = try post.checkIn() else { throw .refused }
            let saved = try await backend.save(checkIn)
            // Counted as saved before it leaves the outbox, so the home never shows it as neither.
            fold(saved)
            await drop(id)
            return saved
        } catch {
            // Offline or signed out, it waits; refused, it never goes out.
            if error != .notSent, error != .signedOut { await drop(id) }
            throw error
        }
    }

    /// Counts a check-in the server saved into the home it last sent, so the home doesn't
    /// wait for the next load: in the squad's today only if it was shared there.
    private func fold(_ saved: CheckIn) {
        guard var home = savedHome?.rolled(to: saved.day), saved.member == home.member,
            !home.checkIns.contains(where: { $0.id == saved.id })
        else { return }
        home.today = home.today.countingMine(saved, squadSaw: home.squadSees(on: saved.day))
        home.checkIns.append(saved)
        savedHome = home
    }

    private func keep(_ post: PendingCheckIn) async {
        guard let index = pending.firstIndex(where: { $0.id == post.id }) else { return }
        pending[index] = post
        await outbox.save(pending)
    }

    func drop(_ id: CheckInID) async {
        pending.removeAll { $0.id == id }
        await outbox.save(pending)
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
