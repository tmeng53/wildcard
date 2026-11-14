#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SquadDomain
import SwiftUI

/// 入队申请 at the top of 小队设置 (Tracy, 2026-11-12, approved design v6): each waiting request
/// as the asker's head and name with their note (备注) under it, 拒绝 and 同意. 拒绝 gives no reason;
/// 同意 can't be tapped while the squad is full. The captain's only; gone once nobody waits.
struct SquadJoinRequests: View {
    @Bindable var model: SquadSettingsModel
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        if let requests = model.joining?.requests, !requests.isEmpty {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(copy: "入队申请", bundle: .module)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .accessibilityAddTraits(.isHeader)
                ForEach(requests) { request in
                    row(request)
                }
            }
            // One container, so the identifier names the section rather than each of its rows.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("squad.joinRequests")
        }
    }

    private func row(_ request: WaitingJoinRequest) -> some View {
        HStack(spacing: Space.s) {
            LookHead(character: request.character)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(verbatim: request.character?.nickname.text ?? "")
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                if let note = request.note {
                    Text(verbatim: note)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button {
                Task { await model.answer(request, approve: false) }
            } label: {
                Text(copy: "拒绝", bundle: .module)
            }
            .buttonStyle(TextButtonStyle(.muted))
            .accessibilityIdentifier("squad.joinRequest.decline")
            Button {
                Task { await model.answer(request, approve: true) }
            } label: {
                Text(copy: "同意", bundle: .module)
            }
            .buttonStyle(SecondaryButtonStyle(size: .compact))
            .disabled(!model.canApprove)
            .accessibilityIdentifier("squad.joinRequest.approve")
        }
        .frame(minHeight: SquadSettingsMetrics.row)
    }
}

/// 入队需要审核: whether opening the squad's invite asks the captain first, worded like a group
/// chat's 加群需要验证. The captain's only.
struct JoinApprovalRow: View {
    @Bindable var model: SquadSettingsModel

    var body: some View {
        if let required = model.joining?.required {
            SwitchRow(
                Text(copy: "入队需要审核", bundle: .module),
                isOn: Binding(get: { required }, set: { isOn in Task { await model.setJoinApproval(isOn) } }),
                showsDivider: false
            )
            .accessibilityIdentifier("squad.joinApproval")
        }
    }
}
#endif
