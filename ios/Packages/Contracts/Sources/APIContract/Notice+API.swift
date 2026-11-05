import Contracts
import Foundation

// Reading 通知 from the API's wire types.

extension NoticePage {
    /// A notice this build can't read (a kind added later, or one missing what its kind needs)
    /// is left out; the page's `next` still goes on past it.
    public init(_ wire: Components.Schemas.NoticePage) {
        self.init(
            notices: wire.notices.compactMap(Notice.init),
            seenThrough: wire.seenThrough.map(NoticeID.init(rawValue:)),
            next: wire.next.map(NoticeID.init(rawValue:)))
    }
}

extension Notice {
    /// Nil for a notice this build can't read.
    public init?(_ wire: Components.Schemas.NoticeEntry) {
        guard let subject = Self.subject(of: wire) else { return nil }
        let squad: SquadID? =
            if let raw = wire.squadId { try? SquadID(wire: raw) } else { nil }
        self.init(id: NoticeID(rawValue: wire.id), toldAt: wire.at, squad: squad, subject: subject)
    }

    private static func subject(of wire: Components.Schemas.NoticeEntry) -> Subject? {
        let alert = wire.alert.map { PushAlert(key: $0.key, args: $0.args) }
        let checkIn = wire.checkIn.flatMap { try? CheckInID(wire: $0) }
        switch wire.kind {
        case "dailyProgress":
            return alert.map(Subject.dailyProgress)
        case "weeklyAwards":
            guard let alert, let week = wire.weekStart.flatMap({ try? LocalDay($0) }) else { return nil }
            return .weeklyAwards(alert, week: week)
        case "sceneMoved":
            return wire.scene.map {
                .sceneMoved(scene: $0, mover: wire.by.flatMap { try? MemberID(wire: $0) }, moverName: wire.byName)
            }
        case "coachReply":
            return checkIn.flatMap { coachReply(wire, checkIn: $0) }
        case "coachNote":
            return coachNote(wire)
        case "unlocked":
            return unlocked(wire)
        case "comment":
            guard let alert, let checkIn else { return nil }
            return .comment(alert, checkIn: checkIn)
        default:
            return nil
        }
    }

    private static func coachReply(_ wire: Components.Schemas.NoticeEntry, checkIn: CheckInID) -> Subject? {
        guard let coach = wire.coach.flatMap(CoachID.init(rawValue:)), let replied = wire.replied else { return nil }
        return .coachReply(
            checkIn: checkIn, coach: coach, coachName: wire.coachName, replied: replied,
            emoji: wire.emoji.flatMap { try? Emoji($0) })
    }
}

extension Notice {
    fileprivate static func unlocked(_ wire: Components.Schemas.NoticeEntry) -> Subject? {
        guard let kind = wire.unlockKind.flatMap(Unlock.Kind.init(rawValue:)), let item = wire.item else { return nil }
        return .unlocked(kind, item: item)
    }

    /// The morning note as 今天 shows it again from 通知; the coach's name is as it is now.
    fileprivate static func coachNote(_ wire: Components.Schemas.NoticeEntry) -> Subject? {
        guard let note = wire.note, let coach = wire.coach.flatMap(CoachID.init(rawValue:)),
            let day = wire.day.flatMap({ try? LocalDay($0) }), let text = wire.text,
            let squad = wire.squadId.flatMap({ try? SquadID(wire: $0) })
        else { return nil }
        return .coachNote(
            CoachMemberNote(
                id: note, squad: squad, day: day, text: text,
                coach: CoachSpeaker(id: coach, name: wire.coachName ?? "")))
    }
}

extension NoticeID {
    /// The body of `PUT /me/notices/seen`: everything up to this one is read.
    public var seen: Components.Schemas.NoticesSeen { .init(version: ._1, through: rawValue) }
}
