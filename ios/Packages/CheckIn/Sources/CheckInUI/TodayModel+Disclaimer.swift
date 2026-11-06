#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem

/// Which days a 请假条 can go on, for the burst and the 请假条 page.
extension TodayModel {
    /// A 请假条 is on offer while some day it can count for is free of a 练了 (补打卡).
    var unavailable: Set<CheckInKind> {
        let blocked = blockedForDisclaimer
        return disclaimerDays.contains { !blocked.contains($0) } ? [] : [.disclaimer]
    }

    /// The days a 请假条 can count for, today last.
    var disclaimerDays: [LocalDay] { store.postableDays }

    /// The days a 请假条 can't go on: one with a 练了, and today when it rules one out.
    var blockedForDisclaimer: Set<LocalDay> {
        var blocked = store.trainedDays
        if let today = store.postableDays.last, !store.myStatus.allowsDisclaimer || store.restsToday {
            blocked.insert(today)
        }
        return blocked
    }
}
#endif
