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
            return alert.flatMap { weeklyAwards(wire, alert: $0) }
        case "sceneMoved":
            return wire.scene.map {
                .sceneMoved(scene: $0, mover: wire.by.flatMap { try? MemberID(wire: $0) }, moverName: wire.byName)
            }
        case "coachReply":
            return checkIn.flatMap { coachReply(wire, checkIn: $0) }
        case "comment":
            guard let alert, let checkIn else { return nil }
            return .comment(alert, checkIn: checkIn)
        case "trainedWith":
            guard let alert, let checkIn else { return nil }
            return .trainedWith(alert, checkIn: checkIn)
        default:
            return toldInApp(wire)
        }
    }

    /// The other kinds, apart to keep each switch small; nil for a kind this build doesn't know.
    private static func toldInApp(_ wire: Components.Schemas.NoticeEntry) -> Subject? {
        switch wire.kind {
        case "coachNote":
            return coachNote(wire)
        case "coachLetter":
            return coachLetter(wire).map(Subject.coachLetter)
        case "unlocked":
            return unlocked(wire)
        case "broadcast":
            return broadcast(wire).map(Subject.broadcast)
        case "goalSuggestion":
            guard let weeks = wire.weeks, let days = wire.daysPerMember else { return nil }
            return .goalSuggestion(GoalSuggestion(weeks: weeks, daysPerMember: days))
        default:
            return nil
        }
    }

    private static func weeklyAwards(_ wire: Components.Schemas.NoticeEntry, alert: PushAlert) -> Subject? {
        wire.weekStart.flatMap { try? LocalDay($0) }.map { .weeklyAwards(alert, week: $0) }
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

    /// The letter as 今天 opens it again from 通知; the coaches' names are as they are now.
    fileprivate static func coachLetter(_ wire: Components.Schemas.NoticeEntry) -> CoachLetter? {
        guard let id = wire.letter, let from = wire.coach.flatMap(CoachID.init(rawValue:)),
            let recipient = wire.toCoach.flatMap(CoachID.init(rawValue:)),
            let day = wire.day.flatMap({ try? LocalDay($0) }), let text = wire.text,
            let squad = wire.squadId.flatMap({ try? SquadID(wire: $0) })
        else { return nil }
        return CoachLetter(
            id: id, squad: squad, from: CoachSpeaker(id: from, name: wire.coachName ?? ""),
            to: CoachSpeaker(id: recipient, name: wire.toCoachName ?? ""), day: day, text: text)
    }

    fileprivate static func broadcast(_ wire: Components.Schemas.NoticeEntry) -> Broadcast? {
        guard let id = wire.broadcast, let title = wire.title.map(CatalogNames.init) else { return nil }
        let action = wire.action.flatMap { action in
            AppDestination(address: action.destination).map {
                Broadcast.Action(label: CatalogNames(action.label), destination: $0)
            }
        }
        return Broadcast(
            id: id, title: title, body: wire.body.map(CatalogNames.init), action: action,
            style: wire.style == "celebration" ? .celebration : .banner,
            icon: wire.icon.flatMap { icon in
                Unlock.Kind(rawValue: icon.kind).map { Broadcast.Gift(kind: $0, id: icon.id) }
            },
            gifts: (wire.gifts ?? []).compactMap { gift in
                Unlock.Kind(rawValue: gift.kind).map { Broadcast.Gift(kind: $0, id: gift.id) }
            },
            letter: wire.teamLetter.map { letter in
                Broadcast.Letter(
                    lines: CatalogNames(letter.lines.value1),
                    presents: letter.presents.compactMap { present in
                        switch present.kind {
                        case "piece": .piece(present.id)
                        case "badge": .badge(present.id)
                        default: nil
                        }
                    })
            })
    }
}

extension CatalogNames {
    init(_ wire: Components.Schemas.LocalizedWords) {
        self.init(simplifiedChinese: wire.zhHans, english: wire.en, traditionalChinese: wire.zhHant)
    }
}

extension NoticeID {
    /// The body of `PUT /me/notices/seen`: everything up to this one is read.
    public var seen: Components.Schemas.NoticesSeen { .init(version: ._1, through: rawValue) }
}
