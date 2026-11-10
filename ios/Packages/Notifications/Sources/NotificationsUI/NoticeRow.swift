#if os(iOS)
import AvatarArt
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import NotificationsDomain
import SwiftUI

/// One row of 通知: a round icon (the same set the notice banner uses), one line of title, an
/// optional muted line under it, and when it was told. A row that was new is bold, with a dot.
/// A broadcast's words are an admin's message, written for this, so its row shows them whole.
/// What was said on one post in one day is one row: who said it and the newest line.
struct NoticeRow: View {
    @Environment(\.locale) private var locale
    let entry: NoticeEntry
    let heading: NoticeHeading
    let isUnread: Bool
    let now: Date
    let unlocked: (Unlock.Kind, String) -> UnlockWords

    static let icon: Double = 36

    private var notice: Notice { entry.notice }
    private static let dot: Double = 6

    var body: some View {
        let words = NoticeWords(entry: entry, unlocked: unlocked).words
        HStack(spacing: Space.s) {
            words.icon
                .frame(width: Self.icon, height: Self.icon)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 0) {
                words.title
                    .typeStyle(isUnread ? TypeRamp.calloutEmphasis : TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgDefault, in: .gym))
                if let detail = words.detail {
                    detail
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: .gym))
                }
                // A broadcast's button: the row's tap opens it.
                if let action = words.action {
                    NoticeActionLabel(action)
                        .padding(.top, Space.xxs)
                }
            }
            .lineLimit(words.wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: words.wraps)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Space.xxs) {
                when
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgSubtle, in: .gym))
                    .lineLimit(1)
                    .fixedSize()
                if isUnread {
                    Circle()
                        .fill(Color(role: .bgBrand, in: .gym))
                        .frame(width: Self.dot, height: Self.dot)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, Space.xxs)
        .frame(minHeight: Sizing.control)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? Text(copy: "新", bundle: .module) : Text(verbatim: ""))
    }

    /// When it was told: the time today, 昨天 or the weekday this week, the date before.
    private var when: Text {
        switch heading {
        case .today:
            return Text(notice.toldAt, format: .dateTime.hour().minute().locale(locale))
        case .thisWeek:
            if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now),
                Calendar.current.isDate(notice.toldAt, inSameDayAs: yesterday)
            {
                return Text(copy: "昨天", bundle: .module)
            }
            return Text(notice.toldAt, format: .dateTime.weekday(.abbreviated).locale(locale))
        case .earlier:
            return Text(notice.toldAt, format: .dateTime.month(.abbreviated).day().locale(locale))
        }
    }
}

/// What 通知 says of a notice, or of what was said on one post in a day: its title, the line
/// under it, its icon, and a broadcast's button. Its row and its banner both read it.
struct NoticeWords {
    let entry: NoticeEntry
    let unlocked: (Unlock.Kind, String) -> UnlockWords

    private var notice: Notice { entry.notice }

    struct Words {
        let title: Text
        let detail: Text?
        let icon: AnyView
        var action: Text?
        /// Shown whole, on as many lines as it takes.
        var wraps = false
    }

    var words: Words {
        if entry.isJoined, let talk = Self.talk(entry) { return talk }
        switch notice.subject {
        case .dailyProgress(let alert):
            let parts = Self.pushParts(alert)
            return Words(
                title: parts.map { Text(verbatim: $0.title) } ?? Text(copy: "小队今天的进度", bundle: .module),
                detail: parts?.detail.map { Text(verbatim: $0) },
                icon: AnyView(ProgressIcon(alert: alert)))
        case .weeklyAwards(_, let week):
            let number = Self.weekNumber(of: week)
            return Words(
                title: Text(copy: "每周战报出来了", bundle: .module),
                detail: Text(copy: "第 \(number) 周", bundle: .module),
                icon: AnyView(CrownIcon()))
        case .sceneMoved(let scene, _, let moverName):
            let theme = SceneTheme(rawValue: scene)
            let place = theme?.name ?? Text(copy: "新场地", bundle: .module)
            return Words(
                title: moverName.map { Text(copy: "\($0) 把小队搬到了\(place)", bundle: .module) }
                    ?? Text(copy: "小队搬到了\(place)", bundle: .module),
                detail: nil,
                icon: AnyView(theme.map { AnyView(SceneBadge($0)) } ?? AnyView(NoticeSymbol(systemImage: "map"))))
        case .coachReply(_, let coach, let coachName, let replied, let emoji):
            return Words(
                title: Self.coachTitle(name: coachName, replied: replied, emoji: emoji), detail: nil,
                icon: AnyView(CoachIcon(coach: coach)))
        case .coachNote(let note):
            // 「毛头：…」, as its push says it.
            return Words(
                title: note.coach.name.isEmpty
                    ? Text(copy: "教练：\(note.text)", bundle: .module)
                    : Text(copy: "\(note.coach.name)：\(note.text)", bundle: .module),
                detail: nil,
                icon: AnyView(CoachIcon(coach: note.coach.id)))
        case .coachLetter(let letter):
            // 「毛头给帕帕留了一封交接信」, which opens it again on 今天.
            return Words(
                title: Text(
                    copy: "\(Self.coach(letter.from.name))给\(Self.coach(letter.recipient.name))留了一封交接信", bundle: .module
                ),
                detail: nil, icon: AnyView(CoachIcon(coach: letter.from.id)))
        case .unlocked(let kind, let item):
            let unlock = unlocked(kind, item)
            return Words(title: unlock.title, detail: unlock.detail, icon: unlock.icon)
        case .comment(let alert, _):
            return Words(
                title: Self.pushParts(alert).map { Text(verbatim: $0.title) }
                    ?? Text(copy: "队友评论了你的动态", bundle: .module),
                detail: nil, icon: AnyView(NoticeSymbol(systemImage: "bubble.left.fill")))
        case .broadcast(let broadcast):
            return Words(
                title: Text(verbatim: broadcast.title.localized(in: [AppLanguage.current.rawValue])),
                detail: broadcast.body.map { Text(verbatim: $0.localized(in: [AppLanguage.current.rawValue])) },
                icon: broadcast.icon.map { unlocked($0.kind, $0.id).icon }
                    ?? AnyView(NoticeSymbol(systemImage: "sparkles")),
                action: broadcast.action.map { Text(verbatim: $0.label.localized(in: [AppLanguage.current.rawValue])) },
                wraps: true)
        case .goalSuggestion(let suggestion):
            // The row opens 小队, whose first card is the weekly goal.
            return Words(
                title: Text(copy: "连续 \(suggestion.weeks) 周超过小队目标", bundle: .module),
                detail: Text(copy: "改成人均 \(suggestion.daysPerMember) 次？", bundle: .module),
                icon: AnyView(NoticeSymbol(systemImage: "chart.line.uptrend.xyaxis")))
        }
    }

    /// What was said on one post in one day: 「Coco、毛头和另外 2 人评论了你的动态」, or 「…回复了你」
    /// when any of it answers the member, with the newest line under it.
    private static func talk(_ entry: NoticeEntry) -> Words? {
        let names = entry.voices.map(name)
        guard names.count >= 2 else { return nil }
        let (first, second, others) = (names[0], names[1], names.count - 2)
        let title: Text =
            switch (entry.answersMember, others) {
            case (false, 0): Text(copy: "\(first) 和 \(second) 评论了你的动态", bundle: .module)
            case (false, _): Text(copy: "\(first)、\(second) 和另外 \(others) 人评论了你的动态", bundle: .module)
            case (true, 0): Text(copy: "\(first) 和 \(second) 回复了你", bundle: .module)
            case (true, _): Text(copy: "\(first)、\(second) 和另外 \(others) 人回复了你", bundle: .module)
            }
        let line = entry.latestLine.map { (who: name($0.voice), text: $0.text) }
        return Words(
            title: title,
            detail: line.map { line in Text(copy: "\(line.who)：\(line.text)", bundle: .module) },
            icon: AnyView(NoticeSymbol(systemImage: "bubble.left.and.bubble.right.fill")))
    }

    /// A coach's name now, or 教练 when it has none.
    private static func coach(_ name: String) -> String {
        name.isEmpty ? String(copy: "教练", bundle: .module) : name
    }

    /// A voice's name: a teammate's as the push gave it, the coach's, or 教练.
    private static func name(_ voice: NoticeEntry.Voice) -> String {
        switch voice {
        case .teammate(let name), .coach(let name?): name
        case .coach(nil): String(copy: "教练", bundle: .module)
        }
    }

    /// 教练 毛头 回复了你的动态, or the emoji it left when it wrote no line.
    private static func coachTitle(name: String?, replied: Bool, emoji: Emoji?) -> Text {
        switch (name, replied ? nil : emoji) {
        case (let name?, nil): Text(copy: "教练 \(name) 回复了你的动态", bundle: .module)
        case (let name?, let emoji?): Text(copy: "教练 \(name) 给你的动态回了 \(emoji.text)", bundle: .module)
        case (nil, nil): Text(copy: "教练回复了你的动态", bundle: .module)
        case (nil, let emoji?): Text(copy: "教练给你的动态回了 \(emoji.text)", bundle: .module)
        }
    }

    /// The push's own words, as the app's catalog has them in the app's language, split into a
    /// title and what follows; nil for a key this build doesn't have.
    private static func pushParts(_ alert: PushAlert) -> (title: String, detail: String?)? {
        let line = String(copyKey: alert.key, bundle: Bundle.main)
        guard line != alert.key else { return nil }
        return PushAlertWords(alert).parts(line)
    }

    /// The week's number in its year, as the 战报 and 出赛表 count weeks (ISO 8601).
    private static func weekNumber(of week: LocalDay) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        let day = DateComponents(calendar: calendar, year: week.year, month: week.month, day: week.day)
        return day.date.map { calendar.component(.weekOfYear, from: $0) } ?? 0
    }
}

/// A notice told while the app is open, in the banner that drops in over any page (2026-11-08):
/// 通知's words for it and a button, 去看看 for a store or a scene, 查看 for the rest, or a
/// broadcast's own. The app opens its `Notice.destination` on a tap.
public struct ToldNoticeBanner: View {
    private let notice: Notice
    private let unlocked: (Unlock.Kind, String) -> UnlockWords

    /// - Parameter unlocked: how a store, piece or prop is named, as on 通知's rows.
    public init(_ notice: Notice, unlocked: @escaping (Unlock.Kind, String) -> UnlockWords) {
        (self.notice, self.unlocked) = (notice, unlocked)
    }

    public var body: some View {
        if let entry = NoticeEntry([notice]) {
            let words = NoticeWords(entry: entry, unlocked: unlocked).words
            NoticeBanner(words.title, detail: words.detail, action: words.action ?? action) { words.icon }
        }
    }

    private var action: Text {
        switch notice.subject {
        case .unlocked, .sceneMoved: Text(copy: "去看看", bundle: .module)
        default: Text(copy: "查看", bundle: .module)
        }
    }
}

/// The 6pm push: the squad's week as a ring on graphite.
private struct ProgressIcon: View {
    let alert: PushAlert

    var body: some View {
        let done = alert.args.first.flatMap(Double.init) ?? 0
        let goal = alert.args.dropFirst().first.flatMap(Double.init) ?? 0
        ZStack {
            Color(role: .bgBrand, in: .gym)
            Group {
                Circle()
                    .stroke(Color(role: .fgOnBrand, in: .gym).opacity(0.3), lineWidth: Sizing.ringWidth)
                Circle()
                    .trim(from: 0, to: goal > 0 ? min(1, done / goal) : 0)
                    .stroke(
                        Color(role: .fgOnBrand, in: .gym),
                        style: StrokeStyle(lineWidth: Sizing.ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
            }
            .padding(Space.xs)
        }
        .accessibilityHidden(true)
    }
}

/// The week's 战报: a crown on the gym's steel.
private struct CrownIcon: View {
    var body: some View {
        ZStack {
            Color(role: .bgScene, in: .gym)
            Image(systemName: "crown.fill")
                .font(.system(size: Sizing.smallIcon, weight: .semibold))
                .foregroundStyle(Color(role: .fgOnScene, in: .gym))
        }
        .accessibilityHidden(true)
    }
}

/// The coach's head, as on the sideline; a coach this build has no art for shows the 教练 symbol.
private struct CoachIcon: View {
    let coach: CoachID
    @State private var head: CharacterPlayer?

    var body: some View {
        ZStack {
            if let head {
                Color(role: .bgBrand, in: .gym)
                CharacterHead(player: head, figure: .coach)
            } else {
                NoticeSymbol(systemImage: "megaphone.fill")
            }
        }
        .accessibilityHidden(true)
        .task(id: coach) {
            let id = coach.rawValue
            guard CoachCharacter.exists(id) else { return }
            head = try? CharacterPlayer(figure: CoachCharacter.figure(id), idle: CoachCharacter.clip(.idle, coach: id))
        }
    }
}
#endif
