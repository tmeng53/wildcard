#if os(iOS)
import AvatarUI
import DesignSystem
import DesignSystemUI
import OnboardingDomain
import SwiftUI

/// 等队长同意 (Tracy, 2026-11-12): the squad the member asked to join, as its invite showed it, and
/// its captain, with 撤回申请. It reads the request again every few seconds and as the app comes
/// back, and goes on to 上场 once the captain lets them in. After a no it is 申请没有通过: the squad
/// greyed under 未通过, and 重新选小队, with no alert.
struct WaitingStep: View {
    let model: SignUpModel
    @Environment(\.sceneTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    /// How often 等队长同意 asks whether the captain answered.
    private static let checkEvery: Duration = .seconds(10)

    var body: some View {
        StepPage(step: .waiting, title: title, character: model.myCharacter, onBack: nil) {
            if let request = model.request {
                VStack(alignment: .leading, spacing: Space.s) {
                    SquadSummaryCard(name: request.squadName, heads: model.requestHeads, isDeclined: isDeclined) {
                        Text(copy: "\(request.memberCount) 人", bundle: .module)
                    }
                    .accessibilityIdentifier("waiting.squad")
                    if !isDeclined, let captain = request.captain {
                        HStack(spacing: Space.s) {
                            MemberHead(player: model.captainHead?.player, size: Self.captainHead)
                            Text(verbatim: captain.nickname.text)
                                .typeStyle(TypeRamp.body)
                                .foregroundStyle(Color(role: .fgDefault, in: theme))
                                .lineLimit(1)
                            Spacer(minLength: Space.xs)
                            Text(copy: "队长", bundle: .module)
                                .typeStyle(TypeRamp.footnote)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("waiting.captain")
                    }
                }
            }
        } actions: {
            FailureLine(failure: model.failure)
            if isDeclined {
                StepButton(
                    title: Text(copy: "重新选小队", bundle: .module), isWorking: false, isEnabled: true,
                    action: model.chooseAgain
                )
                .accessibilityIdentifier("waiting.chooseAgain")
            } else {
                Button(action: model.withdrawRequest) {
                    Text(copy: "撤回申请", bundle: .module)
                        .loadingLabel(model.isWorking)
                }
                .buttonStyle(TextButtonStyle())
                .disabled(model.isWorking)
                .accessibilityIdentifier("waiting.withdraw")
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled, model.step == .waiting, let request = model.request, request.status != .declined {
                await model.checkRequest()
                try? await Task.sleep(for: Self.checkEvery)
            }
        }
    }

    /// The captain's head beside their name, as a row's.
    private static let captainHead: Double = 40

    private var isDeclined: Bool { model.request?.status == .declined }

    private var title: Text {
        isDeclined ? Text(copy: "申请没有通过", bundle: .module) : Text(copy: "等队长同意", bundle: .module)
    }
}
#endif
