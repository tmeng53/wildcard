#if os(iOS)
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystemUI
import Foundation

/// 今日赛况's data on the home: the day's recap, the day its title names, and who is in it.
extension TodayModel {
    /// 今日赛况, from 21:00 on the member's own clock until their day ends; nil before.
    var recap: DayRecap? {
        guard let home, home.showsRecap(at: now()) else { return nil }
        return home.recap(pending: store.pending)
    }

    /// Noon of the member's today in their time zone: the day the recap's title names.
    var dayDate: Date? {
        guard let home, let day = home.mine?.day else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = home.timeZone
        return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
    }

    /// A member's head and name on 今日赛况: 我 for me, else their nickname, or 队友 before they
    /// made their character.
    func recapMember(_ member: MemberID) -> (head: CharacterPlayer?, name: String) {
        if member == home?.member { return (player, String(copy: "我", bundle: .module)) }
        let nickname = home?.today.members.first { $0.member == member }?.character?.nickname.text
        return (head(of: member.description), nickname ?? String(copy: "队友", bundle: .module))
    }
}
#endif
