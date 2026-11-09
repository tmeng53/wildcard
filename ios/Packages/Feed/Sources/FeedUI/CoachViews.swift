#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// 战术板: the coach's line for the day, pinned at the top of today like a sheet on a clipboard
/// (the approved 教练发言 design): the coach standing at the left, 教练 and its name and time,
/// then the line. Over the coach's card, where the coach already stands, it leaves the figure out
/// (`showsCoach`).
public struct CoachBoard: View {
    @Environment(\.sceneTheme) private var theme
    private let note: CoachNote
    private let showsCoach: Bool

    public init(note: CoachNote, showsCoach: Bool = true) {
        self.note = note
        self.showsCoach = showsCoach
    }

    private static let figure = CGSize(width: 66, height: 88)

    public var body: some View {
        ClipboardCard {
            HStack(alignment: .bottom, spacing: Space.s) {
                if showsCoach {
                    CoachFigure(coach: note.coach.id.rawValue, pose: .still, crop: CoachCanvas.full) { EmptyView() }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .frame(width: Self.figure.width, height: Self.figure.height)
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.xxs) {
                        CoachTag().padding(.trailing, Space.xxs)
                        Text(verbatim: note.coach.name)
                        Text(verbatim: "·")
                        Text(note.writtenAt, format: .dateTime.hour().minute())
                    }
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .lineLimit(1)
                    Text(verbatim: note.text)
                        .typeStyle(TypeRamp.callout)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Space.s)
            }
            .padding(.top, Space.m)
            .padding(.horizontal, Space.m)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("教练 \(note.coach.name)：\(note.text)", bundle: .module))
        .accessibilityIdentifier("feed.coachBoard")
    }
}

/// The coach's line under a card: its name, the 教练 tag, 回复 and whom when it answers a reply,
/// then the words.
struct CoachCommentLine: View {
    @Environment(\.sceneTheme) private var theme
    let coach: CoachSpeaker
    let text: String
    /// The text with its @ tags.
    let words: MentionedWords
    /// Whom it answers, when it answers a member's reply to it.
    var recipient: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(verbatim: coach.name).fontWeight(.semibold)
            CoachTag(.small)
            said
        }
        .typeStyle(TypeRamp.callout)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coachSaid(coach, text, to: recipient))
        .accessibilityIdentifier(recipient == nil ? "feed.coachComment" : "feed.coachAnswer")
    }

    private var said: Text {
        let words = self.words.text(in: theme)
        guard let recipient else { return words }
        let reply = Text("回复 \(recipient)", bundle: .module)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        return Text("\(reply)  \(words)", bundle: .module)
    }
}

/// What VoiceOver reads for the coach's line or answer: 「教练 毛头：…」, 「教练 毛头 回复 小美：…」.
private func coachSaid(_ coach: CoachSpeaker, _ text: String, to recipient: String?) -> Text {
    guard let recipient else { return Text("教练 \(coach.name)：\(text)", bundle: .module) }
    return Text("教练 \(coach.name) 回复 \(recipient)：\(text)", bundle: .module)
}

/// The coach's line on a post's own page, first among the comments, or its answer to a member's
/// reply, right after it: its head, name, tag and time, then 回复 and whom when it answers, then
/// the words. A tap replies to the coach; the page makes it a button.
struct CoachCommentRow: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let coach: CoachSpeaker
    let text: String
    /// Whom it @s, in the order written.
    let mentions: [MemberID]
    let writtenAt: Date
    /// Whom it answers, when it answers a member's reply to it.
    var recipient: String?

    private static let faceSize: Double = 32

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            MemberHead(player: model.coachPlayer(coach.id), size: Self.faceSize, figure: .coach)
            VStack(alignment: .leading, spacing: Space.xxs / 2) {
                HStack(spacing: Space.xs) {
                    Text(verbatim: coach.name)
                        .typeStyle(TypeRamp.footnoteEmphasis)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                    CoachTag(.small)
                    Text(writtenAt, format: .dateTime.hour().minute())
                        .typeStyle(TypeRamp.caption)
                        .foregroundStyle(Color(role: .fgSubtle, in: theme))
                }
                .lineLimit(1)
                said
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coachSaid(coach, text, to: recipient))
    }

    /// 回复 小美：the words, with 回复 and the name in grey, as a teammate's reply, and its @ tags.
    private var said: Text {
        let words = model.words(of: text, mentioning: mentions).text(in: theme)
        guard let recipient else { return words }
        let reply = Text("回复 \(recipient)：", bundle: .module)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        return Text("\(reply)\(words)", bundle: .module)
    }
}
#endif
