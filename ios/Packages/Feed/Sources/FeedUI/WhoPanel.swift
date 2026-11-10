#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// Who reacted, right there at the row: the coach first, with the 教练 tag, then each person's
/// head, name and emoji, with a filter by emoji when there's more than one.
struct WhoPanel: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let reactions: Responses<Emoji>
    /// The coach's reply, shown when it left an emoji; never counted or filtered.
    let coach: CoachReply?
    @State private var filter: Emoji?

    static let width: Double = 300
    private static let row: Double = 44
    private static let head: Double = 28
    private static let visibleRows = 5.5

    static func height(for reactions: Responses<Emoji>, coach: CoachReply?) -> Double {
        let coachRows = coach?.emoji == nil ? 0 : 1
        let rows = min(Double(reactions.all.count + coachRows), visibleRows) * row
        let filters = reactions.groups.count > 1 ? Sizing.compactControl + Space.xs : 0
        return rows + filters + 2 * Space.xs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if reactions.groups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
                        PickPill(
                            Text(copy: "全部 \(reactions.all.count)", bundle: .module),
                            isSelected: filter == nil || !reactions.groups.contains { $0.kind == filter }
                        ) {
                            filter = nil
                        }
                        ForEach(reactions.groups, id: \.kind) { group in
                            PickPill(
                                Text(verbatim: "\(group.kind.text) \(group.members.count)"),
                                isSelected: filter == group.kind
                            ) { filter = group.kind }
                        }
                    }
                }
                .frame(height: Sizing.compactControl)
            }
            ScrollView {
                VStack(spacing: 0) {
                    if let coach, let emoji = coach.emoji {
                        coachRow(coach.coach, emoji)
                    }
                    ForEach(shown, id: \.member) { response in
                        HStack(spacing: Space.s) {
                            MemberHead(player: model.head(of: response.member), size: Self.head)
                            Text(verbatim: name(response.member))
                                .typeStyle(TypeRamp.body)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(verbatim: response.kind.text).typeStyle(TypeRamp.headline)
                        }
                        .frame(height: Self.row)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .frame(width: Self.width, height: Self.height(for: reactions, coach: coach))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.who")
    }

    private func coachRow(_ coach: CoachSpeaker, _ emoji: Emoji) -> some View {
        HStack(spacing: Space.s) {
            MemberHead(player: model.coachPlayer(coach.id), size: Self.head, figure: .coach)
            Text(verbatim: coach.name)
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
            CoachTag(.small)
            Spacer(minLength: 0)
            Text(verbatim: emoji.text).typeStyle(TypeRamp.headline)
        }
        .frame(height: Self.row)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(copy: "教练 \(coach.name)：\(emoji.text)", bundle: .module))
        .accessibilityIdentifier("feed.whoCoach")
    }

    /// Everyone who reacted, newest first, or those who left the filter's emoji. A filter whose
    /// emoji nobody has any more shows everyone again.
    private var shown: [Responses<Emoji>.Response] {
        let all = reactions.newest(reactions.all.count)
        let picked = all.filter { $0.kind == filter }
        return picked.isEmpty ? all : picked
    }

    private func name(_ member: MemberID) -> String {
        if member == model.viewer { return String(copy: "我", bundle: .module) }
        return model.name(of: member) ?? String(copy: "队友", bundle: .module)
    }
}
#endif
