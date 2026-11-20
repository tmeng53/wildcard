#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// 设置 › 已拉黑: each teammate the member blocked, their head and name, with 解除, which shows
/// them to each other again at once.
struct BlockedMembersView: View {
    @Bindable var model: BlockedMembersModel
    @Environment(\.sceneTheme) private var theme

    private static let headSize: Double = 32

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(copy: "已拉黑", bundle: .module)
                    .typeStyle(TypeRamp.taskTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(model.blocked) { member in
                        row(member)
                        if member.id != model.blocked.last?.id {
                            Rectangle()
                                .fill(Color(role: .borderDefault, in: theme))
                                .frame(height: 1)
                        }
                    }
                }
                if model.failed { InlineFailure(Text(copy: "没解除成功，再试一次", bundle: .module)) }
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .background(Color(role: .bgCanvas, in: theme))
        .pushedPage()
        .task { await model.load() }
        .accessibilityIdentifier("blocked.page")
    }

    private func row(_ member: BlockedMember) -> some View {
        HStack(spacing: Space.s) {
            MemberHead(player: Self.head(of: member.character), size: Self.headSize)
                .accessibilityHidden(true)
            Text(verbatim: name(of: member))
                .typeStyle(TypeRamp.body)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .lineLimit(1)
            Spacer(minLength: Space.s)
            Button {
                Task { await model.unblock(member.id) }
            } label: {
                Text(copy: "解除", bundle: .module)
            }
            .buttonStyle(SecondaryButtonStyle(size: .compact))
            .accessibilityIdentifier("blocked.unblock")
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blocked.member")
    }

    private func name(of member: BlockedMember) -> String {
        guard let nickname = member.character?.nickname, !nickname.isEmpty else {
            return String(copy: "队友", bundle: .module)
        }
        return nickname
    }

    /// Their head in their look, standing still; the starter look for one who never made theirs.
    private static func head(of character: MeCharacter?) -> CharacterPlayer? {
        guard let figure = try? PlaceholderCharacter.figure(wearing: character?.outfit ?? PlaceholderCharacter.lifter)
        else { return nil }
        return try? CharacterPlayer(figure: figure, idle: .still)
    }
}
#endif
