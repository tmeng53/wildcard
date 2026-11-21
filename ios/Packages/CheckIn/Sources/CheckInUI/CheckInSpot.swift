#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI

/// 打卡 and its burst; while my post goes out behind the scene, what became of it; and for a
/// moment after my pat lands, 「你拍了拍小米」 (Tracy, 2026-11-21), in the same capsule.
struct CheckInSpot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var model: TodayModel
    let openPost: (CheckIn) -> Void

    var body: some View {
        Group {
            if let outgoing = model.outgoing {
                OutgoingPill(
                    outgoing: outgoing, progress: model.outgoingProgress, open: openPost,
                    dismiss: { model.dismissOutgoing() }
                )
                .frame(height: Sizing.primaryControl)
                .transition(.blurReplace)
            } else if let told = model.pats.told {
                PatToldPill(told: told)
                    .id(told.id)
                    .transition(.blurReplace)
            } else {
                CheckInBurst(
                    isOpen: $model.isBurstOpen, unavailable: model.unavailable, identifierPrefix: "today"
                ) { kind in
                    model.pick(kind)
                }
                .transition(.blurReplace)
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.outgoing == nil)
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.pats.told)
    }
}

/// 「你拍了拍小米」: 打卡's capsule, with the hand that taps, saying whom my pat landed on.
private struct PatToldPill: View {
    let told: PatStage.Told

    var body: some View {
        Button {
        } label: {
            Label {
                Text(copy: "你拍了拍\(told.name)", bundle: .module)
            } icon: {
                Image(systemName: "hand.tap.fill")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .allowsHitTesting(false)
        .accessibilityIdentifier("today.patTold")
    }
}
#endif
