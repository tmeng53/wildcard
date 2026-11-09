#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import PhotosUI
import SwiftUI
import UIKit

/// 意见反馈 (设置 › 关于), as approved 2026-11-08: the character writing at its desk beside the
/// heading; the graphite 喜欢外卡吗？ card, whose 写评价 opens the App Store's own review sheet;
/// then 写给我们: 出问题了 or 提个建议, and the words and up to 3 screenshots on one ticket (the
/// character editor's ticket: a tear line, notches either side, the W). 发送 floats at the bottom.
/// Once it is sent, `TicketCheck` plays with 谢谢你的反馈 / 我们很快处理, and the page goes back
/// to 设置 on its own. It needs no squad, and it is the app's 联系我们: the email is on it too.
struct FeedbackView: View {
    @Bindable var model: FeedbackModel
    let character: MeCharacter?
    /// The App Store's 撰写评论 sheet for the app.
    let writeReview: URL
    @State private var picked: [PhotosPickerItem] = []
    @State private var isPicking = false
    @FocusState private var isWriting: Bool
    @Environment(\.sceneTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    /// How long 谢谢你的反馈 stays once the check is drawn, before the page goes back.
    private static let sentHold: Duration = .seconds(1.6)
    /// The gap between the rating card's stars.
    private static let starGap = 3.0

    var body: some View {
        Group {
            if model.phase == .sent {
                sent
            } else {
                page
            }
        }
        .background(Color(role: .bgCanvas, in: theme))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feedback.page")
    }

    // MARK: - Writing

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ratingCard
                    .padding(.top, Space.m)
                SectionLabel(Text("写给我们", bundle: .module))
                    .padding(.top, Space.l)
                    .padding(.bottom, Space.xs)
                kinds
                FeedbackTicket(model: model, isWriting: $isWriting) { isPicking = true }
                    .padding(.top, Space.s)
                failure
                Text("也可以发邮件到 [support@wildcardsquad.com](mailto:support@wildcardsquad.com)", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .tint(Color(role: .fgDefault, in: theme))
                    .padding(.top, Space.s)
                    .padding(.horizontal, Space.xxs)
                    .accessibilityIdentifier("feedback.email")
            }
            .padding(.horizontal, Space.pageMargin)
            .padding(.top, Space.xs)
            .padding(.bottom, Space.l)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .barTitleOnScroll(Text("意见反馈", bundle: .module))
        .actionBar {
            Button {
                isWriting = false
                Task { await model.send() }
            } label: {
                Text("发送", bundle: .module)
                    .frame(maxWidth: .infinity)
                    .loadingLabel(model.phase == .sending)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.canSend)
            .accessibilityIdentifier("feedback.send")
        }
        .photosPicker(
            isPresented: $isPicking, selection: $picked,
            maxSelectionCount: max(FeedbackText.maxScreenshots - model.screenshots.count, 1),
            selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current
        )
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { await add(items) }
        }
    }

    /// The heading, as on every pushed page, with the character writing beside it.
    private var header: some View {
        HStack(alignment: .bottom, spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("意见反馈", bundle: .module)
                    .typeStyle(TypeRamp.largeTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                Text("每一条我们都会看", bundle: .module)
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                // Only while the beta's reward runs: its switch is turned off on the server.
                if Switchboard.shared.isOn(.feedbackReward, at: .now) {
                    Text("公测期间提出反馈，领取神秘奖励", bundle: .module)
                        .typeStyle(TypeRamp.callout)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .accessibilityIdentifier("feedback.betaReward")
                }
            }
            Spacer(minLength: 0)
            MeStage(character: character, mood: .writing, size: CGSize(width: 90, height: 112))
                .accessibilityHidden(true)
        }
    }

    /// 喜欢外卡吗？ with 写评价, which opens the App Store's review sheet: the stars are only a
    /// picture, since a rating can be given only there.
    private var ratingCard: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs - 2) {
                HStack(spacing: Self.starGap) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill").font(.system(size: Sizing.smallIcon))
                    }
                }
                .accessibilityHidden(true)
                Text("喜欢外卡吗？", bundle: .module)
                    .typeStyle(TypeRamp.headline)
            }
            .foregroundStyle(Color(role: .fgOnBrand, in: theme))
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                openURL(writeReview)
            } label: {
                Text("写评价", bundle: .module)
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .bgBrand, in: theme))
                    .padding(.horizontal, Space.m)
                    .frame(minHeight: Sizing.compactControl)
                    .background(Color(role: .fgOnBrand, in: theme), in: Capsule())
                    .padding(.vertical, (Sizing.minimumTapTarget - Sizing.compactControl) / 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("feedback.review")
        }
        .padding(.horizontal, Space.cardPadding)
        .padding(.vertical, Space.s)
        .background(
            Color(role: .bgBrand, in: theme), in: RoundedRectangle(cornerRadius: Radius.card + 4, style: .continuous))
    }

    private var kinds: some View {
        HStack(spacing: Space.xs) {
            PickPill(
                Text("出问题了", bundle: .module), systemImage: "ladybug", look: .solid,
                isSelected: model.kind == .problem
            ) { model.kind = .problem }
            .accessibilityIdentifier("feedback.problem")
            PickPill(
                Text("提个建议", bundle: .module), systemImage: "lightbulb", look: .solid,
                isSelected: model.kind == .idea
            ) { model.kind = .idea }
            .accessibilityIdentifier("feedback.idea")
        }
        .accentTone(.ink)
    }

    /// Why the last 发送 didn't go; what was written stays.
    @ViewBuilder private var failure: some View {
        if case .failed(let error) = model.phase {
            Group {
                switch error {
                case .limit: Text("今天已经发了 10 条，明天再发", bundle: .module)
                case .unavailable, .signedOut: Text("网络开小差了，没发出去", bundle: .module)
                }
            }
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .padding(.top, Space.s)
            .padding(.horizontal, Space.xxs)
            .accessibilityIdentifier("feedback.failed")
        }
    }

    // MARK: - Sent

    private var sent: some View {
        VStack {
            Spacer()
            TicketCheck(label: Text("已发送", bundle: .module)) {
                VStack(spacing: Space.xs - 2) {
                    Text("谢谢你的反馈", bundle: .module)
                        .typeStyle(TypeRamp.taskTitle)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                    Text("我们很快处理", bundle: .module)
                        .typeStyle(TypeRamp.callout)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                .multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.pageMargin)
        .haptic(.appear, trigger: model.phase)
        .accessibilityIdentifier("feedback.sent")
        .task {
            try? await Task.sleep(for: .seconds(TicketCheckTiming.duration) + Self.sentHold)
            dismiss()
        }
    }

    // MARK: - Screenshots

    /// Loads each picked screenshot and makes a JPEG of it off the main actor; one that can't be
    /// read is left out.
    private func add(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let jpeg = await Task.detached(priority: .userInitiated, operation: { Self.jpeg(from: data) }).value {
                model.add(screenshot: jpeg)
            }
        }
    }

    /// A screenshot as a JPEG, its longer side at most 2048 pixels: enough to read any text on it.
    private nonisolated static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        let scale = min(1, 2048 / max(longest, 1))
        let size = CGSize(
            width: (image.size.width * image.scale * scale).rounded(),
            height: (image.size.height * image.scale * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
#endif
