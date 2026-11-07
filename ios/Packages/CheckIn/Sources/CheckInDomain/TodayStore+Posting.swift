import Contracts
import Foundation

extension TodayStore {
    // MARK: - Posting

    /// Posts a check-in, shared to the member's squad unless `shared` is false (which keeps it
    /// to the member), for `chosen`, today or one of the `backfillDays` before it
    /// (补打卡; today when left out): saved by the server now or, offline, later. Today's post
    /// counts on the home at once; a past day's once the server has it and the home is read again.
    /// Throws when it can never be saved: a 请假条 on a day with a 练了, a day out of reach, or a
    /// refusal from the server.
    @discardableResult
    public func post(_ draft: CheckInDraft, shared: Bool = true, on chosen: LocalDay? = nil)
        async throws(CheckInError) -> PostOutcome
    {
        let post = try await queue(draft, shared: shared, on: chosen)
        switch await fate(of: post.id) {
        case .saved(let saved):
            await landed(saved)
            return .posted(saved)
        case .refused(let refusal): throw refusal.reason
        case .waiting: return .queued
        }
    }

    /// Puts a check-in in the outbox, as `post` does, and returns it without sending it: it counts
    /// on the home at once, and `deliver` sends it. Throws only for what the phone can tell
    /// before sending: a 请假条 on a day with a 练了, or a day out of reach.
    public func queue(_ draft: CheckInDraft, shared: Bool = true, on chosen: LocalDay? = nil)
        async throws(CheckInError) -> PendingCheckIn
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
        return post
    }

    /// What became of a post `deliver` sent.
    public enum Delivery: Equatable, Sendable {
        /// The server saved it.
        case posted(CheckIn)
        /// It couldn't go out yet (offline or signed out); it stays in the outbox and goes out later.
        case waiting
        /// The server refused it; it is dropped and listed in `refused`.
        case refused
    }

    /// Sends the outbox until the queued post `id` is saved, refused or can't go out yet, waiting
    /// for a send already under way rather than starting a second.
    public func deliver(_ id: CheckInID) async -> Delivery {
        switch await fate(of: id) {
        case .saved(let saved):
            await landed(saved)
            return .posted(saved)
        case .refused(let refusal):
            refused.append(refusal)
            return .refused
        case .waiting:
            return .waiting
        }
    }

    /// How far the queued post `id` has gone out, from 0 to 1: a share for each photo uploaded,
    /// and the last for the save. Nil once it has left the outbox.
    public func progress(of id: CheckInID) -> Double? {
        guard let post = pending.first(where: { $0.id == id }) else { return nil }
        let photos = post.draft.photos.count
        return Double(photos - post.photosToUpload.count) / Double(photos + 1)
    }

    /// What follows a post the server saved: a past day's counts (my week, 出赛表) come from the
    /// server, and a 练了 is what opens a store or a prop (the payoff doesn't wait for that).
    private func landed(_ saved: CheckIn) async {
        if saved.isBackfill { await refresh() }
        if case .trained = saved.entry { Task { await checkUnlocks() } }
    }

    /// Sends every post still waiting, oldest first, and stops at the first that can't go out
    /// yet. One the server refuses is dropped and listed in `refused`.
    public func sendPending() async {
        await drain()
    }

    /// What became of a post someone waits on.
    enum Fate {
        case saved(CheckIn)
        case refused(Refused)
        /// Still in the outbox.
        case waiting
    }

    /// Drains the outbox until the post `id` has left it, or a drain of its own left it there.
    /// A drain already under way is waited for, and the post sent by it if it gets that far.
    private func fate(of id: CheckInID) async -> Fate {
        awaited.insert(id)
        defer {
            awaited.remove(id)
            fates[id] = nil
        }
        var ranOwn = false
        while !ranOwn, pending.contains(where: { $0.id == id }) {
            ranOwn = draining == nil
            await drain()
        }
        return fates[id] ?? .waiting
    }

    /// Sends the outbox oldest first, one post at a time, until it is empty or a post can't go
    /// out yet, so the server sees posts in the order they were made. Only one drain runs at
    /// once: a second caller waits for it. It reads the outbox afresh after each post, so one made
    /// meanwhile goes out with it.
    private func drain() async {
        if let draining {
            await draining.value
            return
        }
        // Cleared by the drain itself, before anyone waiting on it resumes.
        let run = Task {
            await sendAll()
            draining = nil
        }
        draining = run
        await run.value
    }

    /// The drain's work. A refusal is listed in `refused`, except an awaited post's, which goes
    /// to its waiter.
    private func sendAll() async {
        while let post = pending.first {
            do throws(CheckInError) {
                let saved = try await send(post)
                if awaited.contains(post.id) { fates[post.id] = .saved(saved) }
            } catch {
                if error == .notSent || error == .signedOut { return }
                let refusal = Refused(pending: post, reason: error)
                if awaited.contains(post.id) {
                    fates[post.id] = .refused(refusal)
                } else {
                    refused.append(refusal)
                }
            }
        }
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
    func fold(_ saved: CheckIn) {
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
}
