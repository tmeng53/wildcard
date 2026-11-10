#if os(iOS)
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// What a member is up to today, as the home's scene shows them.
struct MateToday: Equatable {
    let title: String
    let detail: String?
    /// The member is me: nothing to pat.
    let isMe: Bool
}

/// 今天 over a member's player card when a tap on them on the home opens it (Tracy, 2026-11-04,
/// in place of the bubble over their head): their status and the words of their latest post, and
/// 「拍一拍」 (「拍过了」 once patted today), which closes the card so the pat plays on the scene.
/// Draws nothing for someone the home doesn't show.
public struct MateTodayStrip: View {
    private let model: TodayModel
    private let member: MemberID
    private let close: () -> Void
    @Environment(\.sceneTheme) private var theme

    public init(model: TodayModel, member: MemberID, close: @escaping () -> Void) {
        (self.model, self.member, self.close) = (model, member, close)
    }

    public var body: some View {
        if let today = model.today(of: member) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(copy: "今天", bundle: .module)
                    .typeStyle(TypeRamp.label)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                HStack(spacing: Space.s) {
                    VStack(alignment: .leading, spacing: Space.xxs / 2) {
                        Text(verbatim: today.title)
                            .typeStyle(TypeRamp.headline)
                            .foregroundStyle(Color(role: .fgDefault, in: theme))
                            .lineLimit(1)
                            .accessibilityIdentifier("today.mateToday.title")
                        if let detail = today.detail {
                            Text(verbatim: detail)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !today.isMe { patButton }
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(role: .bgCanvas, in: theme),
                in: RoundedRectangle(cornerRadius: Radius.card + Space.xxs, style: .continuous)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.mateToday")
        }
    }

    private var patButton: some View {
        let patted = !model.canPat(member)
        return Button {
            close()
            // Once the card has gone, so the pat plays on the scene in view.
            Task { @MainActor [model, member] in
                try? await Task.sleep(for: .seconds(Motion.sheet.response))
                model.patMate(member)
            }
        } label: {
            if patted { Text(copy: "拍过了", bundle: .module) } else { Text(copy: "拍一拍", bundle: .module) }
        }
        .buttonStyle(PrimaryButtonStyle(.regular))
        .disabled(patted)
        .fixedSize()
        .accessibilityIdentifier("today.pat")
    }
}
#endif
