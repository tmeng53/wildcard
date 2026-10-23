import Contracts
import Foundation

/// 今日赛况: the squad's day as the home shows it from the evening on, without a push. It only
/// says what people did: nobody who hasn't checked in is named or counted as missing.
public struct DayRecap: Hashable, Sendable {
    /// One line of the recap, most telling first.
    public enum Highlight: Hashable, Sendable {
        /// Everyone checked in today, a 请假条 included.
        case everyoneShowedUp(members: Int)
        /// The first 练了 of the day, by when it was posted.
        case firstIn(MemberID, Activity)
        /// The 请假条 of the day, word for word; the earliest when several posted one.
        case disclaimer(MemberID, String)
        /// The squad's meals today.
        case meals(healthy: Int, cheat: Int)
        /// Nobody trained today.
        case quietDay
    }

    /// The hour of the member's own evening the recap shows from, until their day ends.
    public static let hour = 21
    /// How many lines the recap shows.
    public static let maxHighlights = 3

    /// Members who checked in today, a 请假条 counting as it does on the squad card.
    public let showedUp: Int
    public let members: Int
    /// Up to `maxHighlights`, in order.
    public let highlights: [Highlight]
}

extension Home {
    /// Today's recap, from the squad's today and its check-ins the home holds.
    public var recap: DayRecap {
        let showedUp = today.members.filter { $0.training != .notCheckedIn }
        let posts = today.members.flatMap { todaysCheckIns(of: $0.member) }.sorted { $0.createdAt < $1.createdAt }
        var highlights: [DayRecap.Highlight] = []
        if !today.members.isEmpty, showedUp.count == today.members.count {
            highlights.append(.everyoneShowedUp(members: today.members.count))
        }
        let firstTraining = posts.lazy.compactMap { post -> (MemberID, Activity)? in
            if case .trained(let training) = post.entry { (post.member, training.activity) } else { nil }
        }
        .first
        if let (member, activity) = firstTraining { highlights.append(.firstIn(member, activity)) }
        let disclaimer = posts.lazy.compactMap { post -> (MemberID, String)? in
            if case .disclaimer(let note) = post.entry { (post.member, note.text) } else { nil }
        }
        .first
        if let (member, text) = disclaimer { highlights.append(.disclaimer(member, text)) }
        let healthy = posts.count { if case .healthyMeal = $0.entry { true } else { false } }
        let cheat = posts.count { if case .cheatMeal = $0.entry { true } else { false } }
        if healthy + cheat > 0 { highlights.append(.meals(healthy: healthy, cheat: cheat)) }
        if firstTraining == nil { highlights.append(.quietDay) }
        return DayRecap(
            showedUp: showedUp.count, members: today.members.count,
            highlights: Array(highlights.prefix(DayRecap.maxHighlights)))
    }

    /// Whether the recap shows at `now`: from `DayRecap.hour` on the member's own clock until
    /// their day ends, the 3am grace included.
    public func showsRecap(at now: Date) -> Bool {
        guard let day = mine?.day else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard
            let evening = calendar.date(
                from: DateComponents(year: day.year, month: day.month, day: day.day, hour: DayRecap.hour))
        else { return false }
        return now >= evening && LocalDay(at: now, in: timeZone) == day
    }
}
