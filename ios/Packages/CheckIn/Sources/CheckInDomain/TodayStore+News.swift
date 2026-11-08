import Contracts

/// What the home tells once: the squad's news, the member's new unlocks and refused posts.
extension TodayStore {
    /// The posts the server refused, once: the home tells them, and the next call has none until
    /// another is refused. Oldest first.
    public func takeRefused() -> [Refused] {
        defer { refused = [] }
        return refused
    }

    /// The squad's news, once: the home tells it, and the next call has none until something else
    /// changes.
    public func takeNews() -> SquadNews {
        defer { news = SquadNews() }
        return news
    }

    /// Reads the member's unlocks and queues the ones this phone hasn't told. One check at a time:
    /// each waits for the last, so a load's and a 练了's never both tell the same unlock. What is
    /// queued counts as told, so an app closed before its banner shows never shows it. Offline, it
    /// tries again on the next load or 练了.
    public func checkUnlocks() async {
        let previous = unlockCheck
        let check = Task {
            await previous?.value
            await readUnlocks()
        }
        unlockCheck = check
        await check.value
    }

    private func readUnlocks() async {
        guard let ledger, phase == .current else { return }
        let told = await ledger.told()
        guard let unlocks = try? await ledger.unlocks() else { return }
        let news = UnlockNews.untold(unlocks, told: told)
        let queued = Set(unlocked.map(UnlockNews.key))
        unlocked += news.tell.filter { !queued.contains(UnlockNews.key($0)) }
        if news.told != told { await ledger.keep(told: news.told) }
    }

    /// The unlocks to tell, once: the next call has none until the member unlocks more.
    public func takeUnlocks() -> [Unlock] {
        defer { unlocked = [] }
        return unlocked
    }
}
