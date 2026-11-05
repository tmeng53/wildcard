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
struct NoticeRow: View {
    @Environment(\.locale) private var locale
    let notice: Notice
    let heading: NoticeHeading
    let isUnread: Bool
    let now: Date
    let unlocked: (Unlock.Kind, String) -> UnlockWords

    static let icon: Double = 36
    private static let dot: Double = 6

    var body: some View {
        let words = self.words
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
                    NoticeActionLabel(action, on: .page)
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
        .accessibilityValue(isUnread ? Text("新", bundle: .module) : Text(verbatim: ""))
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
                return Text("昨天", bundle: .module)
            }
            return Text(notice.toldAt, format: .dateTime.weekday(.abbreviated).locale(locale))
        case .earlier:
            return Text(notice.toldAt, format: .dateTime.month(.abbreviated).day().locale(locale))
        }
    }

    private struct Words {
        let title: Text
        let detail: Text?
        let icon: AnyView
        var action: Text?
        /// Shown whole, on as many lines as it takes.
        var wraps = false
    }

    private var words: Words {
        switch notice.subject {
        case .dailyProgress(let alert):
            let parts = Self.pushParts(alert)
            return Words(
                title: parts.map { Text(verbatim: $0.title) } ?? Text("小队今天的进度", bundle: .module),
                detail: parts?.detail.map { Text(verbatim: $0) },
                icon: AnyView(ProgressIcon(alert: alert)))
        case .weeklyAwards(_, let week):
            let number = Self.weekNumber(of: week)
            return Words(
                title: Text("每周战报出来了", bundle: .module),
                detail: Text("第 \(number) 周", bundle: .module),
                icon: AnyView(CrownIcon()))
        case .sceneMoved(let scene, _, let moverName):
            let theme = SceneTheme(rawValue: scene)
            let place = theme?.name ?? Text("新场地", bundle: .module)
            return Words(
                title: moverName.map { Text("\($0) 把小队搬到了\(place)", bundle: .module) }
                    ?? Text("小队搬到了\(place)", bundle: .module),
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
                    ? Text("教练：\(note.text)", bundle: .module)
                    : Text("\(note.coach.name)：\(note.text)", bundle: .module),
                detail: nil,
                icon: AnyView(CoachIcon(coach: note.coach.id)))
        case .unlocked(let kind, let item):
            let unlock = unlocked(kind, item)
            return Words(title: unlock.title, detail: unlock.detail, icon: unlock.icon)
        case .comment(let alert, _):
            return Words(
                title: Self.pushParts(alert).map { Text(verbatim: $0.title) }
                    ?? Text("队友评论了你的打卡", bundle: .module),
                detail: nil, icon: AnyView(NoticeSymbol(systemImage: "bubble.left.fill")))
        case .broadcast(let broadcast):
            return Words(
                title: Text(verbatim: broadcast.title.localized(in: [AppLanguage.current.rawValue])),
                detail: broadcast.body.map { Text(verbatim: $0.localized(in: [AppLanguage.current.rawValue])) },
                icon: broadcast.icon.map { unlocked($0.kind, $0.id).icon }
                    ?? AnyView(NoticeSymbol(systemImage: "sparkles")),
                action: broadcast.action.map { Text(verbatim: $0.label.localized(in: [AppLanguage.current.rawValue])) },
                wraps: true)
        }
    }

    /// 教练 毛头 回复了你的打卡, or the emoji it left when it wrote no line.
    private static func coachTitle(name: String?, replied: Bool, emoji: Emoji?) -> Text {
        switch (name, replied ? nil : emoji) {
        case (let name?, nil): Text("教练 \(name) 回复了你的打卡", bundle: .module)
        case (let name?, let emoji?): Text("教练 \(name) 给你的打卡回了 \(emoji.text)", bundle: .module)
        case (nil, nil): Text("教练回复了你的打卡", bundle: .module)
        case (nil, let emoji?): Text("教练给你的打卡回了 \(emoji.text)", bundle: .module)
        }
    }

    /// The push's own words, as the app's catalog has them in the app's language, split into a
    /// title and what follows; nil for a key this build doesn't have.
    private static func pushParts(_ alert: PushAlert) -> (title: String, detail: String?)? {
        let line = Bundle.main.inAppLanguage.localizedString(forKey: alert.key, value: nil, table: nil)
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
                Color(role: .bgSubtle, in: .gym)
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
