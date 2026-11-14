#if os(iOS)
import AvatarUI
import DailyPushDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The captain's push about a request to join, long-pressed (Tracy, 2026-11-12): who asked on the
/// brand's graphite, then their character, name and note on white, with 拒绝 and 同意, answered
/// without opening the app. After 同意 the character cheers and the button reads 已同意.
public struct JoinRequestPushView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: JoinRequestPushModel

    private static let markSize: Double = 22
    private static let figure = CGSize(width: 96, height: 132)

    public init(model: JoinRequestPushModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: Space.xs) {
                character
                Text(verbatim: model.push.nickname)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: .gym))
                if let note = model.push.note {
                    Text(verbatim: note)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: .gym))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                JoinAnswerButtons(model: model)
                    .padding(.top, Space.xxs)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity)
        }
        .background(Color(role: .bgCanvas, in: .gym))
        // A push isn't in any squad's scene: it wears the brand.
        .environment(\.sceneTheme, .gym)
        .accentTone(.brand)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s - 2) {
            HStack(spacing: Space.xs) {
                Image("AppMark", bundle: .module)
                    .resizable()
                    .frame(width: Self.markSize, height: Self.markSize)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.thumbnail - 1, style: .continuous))
                    .accessibilityHidden(true)
                Text(copy: "外卡", bundle: .module)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
                Spacer(minLength: 0)
                Text(model.arrived, format: .dateTime.hour().minute())
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgSubtle, in: .gym))
            }
            Text(copy: "\(model.push.nickname) 申请加入小队", bundle: .module)
                .typeStyle(TypeRamp.calloutEmphasis)
                .foregroundStyle(Color(role: .fgOnBrand, in: .gym))
                .lineLimit(2)
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(role: .bgBrand, in: .gym))
    }

    @ViewBuilder private var character: some View {
        if let player = model.player {
            let moving = model.cheering != nil && !reduceMotion
            Figure(player: player, moving: moving)
                .frame(width: Self.figure.width, height: Self.figure.height)
                .accessibilityHidden(true)
                .task(id: model.cheering) {
                    guard let until = model.cheering else { return }
                    try? await Task.sleep(for: .seconds(max(until.timeIntervalSinceNow, 0)))
                    model.cheered()
                }
        }
    }
}

/// 拒绝 and 同意 side by side, then where the answer stands: 已同意 or 已拒绝 once it went through,
/// 满员了 when the squad has no room, 已处理 when it was answered elsewhere.
private struct JoinAnswerButtons: View {
    let model: JoinRequestPushModel

    var body: some View {
        switch model.answer.state {
        case .approved: done(Text(copy: "已同意", bundle: .module))
        case .declined: done(Text(copy: "已拒绝", bundle: .module))
        case .closed: done(Text(copy: "已处理", bundle: .module))
        case .open, .sending, .failed, .full: buttons
        }
    }

    private var buttons: some View {
        let state = model.answer.state
        return VStack(spacing: Space.xxs) {
            HStack(spacing: Space.xs) {
                Button {
                    model.reply(approve: false)
                } label: {
                    label(Text(copy: "拒绝", bundle: .module), sending: state == .sending(approve: false))
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!model.answer.canDecline)
                .accessibilityIdentifier("joinPush.decline")
                Button {
                    model.reply(approve: true)
                } label: {
                    label(Text(copy: "同意", bundle: .module), sending: state == .sending(approve: true))
                }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .disabled(!model.answer.canApprove)
                .accessibilityIdentifier("joinPush.approve")
            }
            if state == .full {
                Text(copy: "满员了", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: .gym))
            }
        }
    }

    private func label(_ text: Text, sending: Bool) -> some View {
        ZStack {
            text.opacity(sending ? 0 : 1)
            if sending { ProgressView() }
        }
        .frame(maxWidth: .infinity)
    }

    private func done(_ text: Text) -> some View {
        text
            .typeStyle(TypeRamp.calloutEmphasis)
            .foregroundStyle(Color(role: .fgMuted, in: .gym))
            .frame(maxWidth: .infinity, minHeight: Sizing.control)
            .accessibilityIdentifier("joinPush.answered")
    }
}
#endif
