import Contracts

// 补打卡: a post can count for today or one of the `CheckIn.backfillDays` before it.
extension TodayStore {
    /// The days a post can count for (补打卡): today and the `CheckIn.backfillDays` before it,
    /// the earliest first. Empty until the home is loaded.
    public var postableDays: [LocalDay] {
        guard let day else { return [] }
        return (0...CheckIn.backfillDays).reversed().map { day.adding(days: -$0) }
    }

    /// The days among `postableDays` the member has a 练了 on, as far as the home knows (its
    /// own posts since Monday, and those still waiting): no 请假条 can go there. The server
    /// checks the days before Monday.
    public var trainedDays: Set<LocalDay> {
        guard let home else { return [] }
        let saved = home.checkIns.filter { checkIn in
            guard checkIn.member == home.member, case .trained = checkIn.entry else { return false }
            return true
        }.map(\.day)
        let waiting = pending.filter { if case .trained = $0.draft { true } else { false } }.map(\.day)
        var days = Set(saved + waiting)
        if let day, home.mine?.day == day, home.mine?.training == .trained { days.insert(day) }
        return days
    }

    /// Throws when the day already rules the draft out. Another phone may have posted since the
    /// last load: a 请假条 must know about a 练了 the server has, and a copy from an earlier day
    /// can't say what today holds, so the server is asked first; offline, the home shown decides.
    func check(_ draft: CheckInDraft, on chosen: LocalDay?) async throws(CheckInError) {
        guard case .disclaimer = draft else {
            if let saved = savedHome, let day, saved.mine.map({ $0.day < day }) ?? false { await refresh() }
            return
        }
        await refresh()
        if let chosen, chosen != day {
            if trainedDays.contains(chosen) { throw .alreadyTrained }
        } else if !myStatus.allowsDisclaimer {
            throw .alreadyTrained
        }
    }
}
