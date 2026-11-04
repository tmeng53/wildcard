#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// 战术板: the coach's line for the day, pinned at the top of today like a sheet on a clipboard
/// (the approved 教练发言 design): the coach standing at the left, 教练 and its name and time,
/// then the line.
struct CoachBoard: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let note: CoachNote

    private static let figure = CGSize(width: 66, height: 88)
    private static let clip = CGSize(width: 54, height: 12)
    private static let border: Double = 1.5

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            CoachFigure(coach: note.coach.id.rawValue, pose: .still, crop: CoachCanvas.full) { EmptyView() }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .frame(width: Self.figure.width, height: Self.figure.height)
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
        .background(
            Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color(role: .fgDefault, in: theme), lineWidth: Self.border)
        }
        .overlay(alignment: .top) {
            Capsule()
                .fill(Color(role: .fgDefault, in: theme))
                .frame(width: Self.clip.width, height: Self.clip.height)
                .offset(y: -Self.clip.height / 2)
        }
        .padding(.top, Self.clip.height / 2)
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
    /// Whom it answers, when it answers a member's reply to it.
    var recipient: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            Text(verbatim: coach.name).fontWeight(.semibold)
            CoachTag(.small)
            words
        }
        .typeStyle(TypeRamp.callout)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coachSaid(coach, text, to: recipient))
        .accessibilityIdentifier(recipient == nil ? "feed.coachComment" : "feed.coachAnswer")
    }

    private var words: Text {
        guard let recipient else { return Text(verbatim: text) }
        let reply = Text("回复 \(recipient)", bundle: .module)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        return Text("\(reply)  \(text)", bundle: .module)
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
    let writtenAt: Date
    /// Whom it answers, when it answers a member's reply to it.
    var recipient: String?

    private static let faceSize: Double = 32

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            MemberHead(player: model.coachPlayer(coach.id), size: Self.faceSize, rim: .coach)
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
                words
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(coachSaid(coach, text, to: recipient))
    }

    /// 回复 小美：the words, with 回复 and the name in grey, as a teammate's reply.
    private var words: Text {
        guard let recipient else { return Text(verbatim: text) }
        let reply = Text("回复 \(recipient)：", bundle: .module)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
        return Text("\(reply)\(text)", bundle: .module)
    }
}
#endif
