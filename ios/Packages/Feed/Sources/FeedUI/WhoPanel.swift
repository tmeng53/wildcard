#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// Who reacted, right there at the row: each person's head, name and emoji, with a filter by
/// emoji when there's more than one.
struct WhoPanel: View {
    @Environment(\.sceneTheme) private var theme
    let model: FeedModel
    let reactions: Responses<Emoji>
    @State private var filter: Emoji?

    static let width: Double = 300
    private static let row: Double = 44
    private static let head: Double = 28
    private static let visibleRows = 5.5

    static func height(for reactions: Responses<Emoji>) -> Double {
        let rows = min(Double(reactions.all.count), visibleRows) * row
        let filters = reactions.groups.count > 1 ? Sizing.compactControl + Space.xs : 0
        return rows + filters + 2 * Space.xs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if reactions.groups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.xs) {
                        PickPill(Text("全部 \(reactions.all.count)", bundle: .module), isSelected: filter == nil) {
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
                    ForEach(shown, id: \.member) { response in
                        HStack(spacing: Space.s) {
                            Face(player: model.head(of: response.member), size: Self.head)
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
        .frame(width: Self.width, height: Self.height(for: reactions))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.who")
    }

    /// Everyone who reacted, newest first, or those who left the filter's emoji.
    private var shown: [Responses<Emoji>.Response] {
        reactions.newest(reactions.all.count).filter { filter == nil || $0.kind == filter }
    }

    private func name(_ member: MemberID) -> String {
        if member == model.viewer { return String(localized: "我", bundle: .module) }
        return model.name(of: member) ?? String(localized: "队友", bundle: .module)
    }
}
#endif
