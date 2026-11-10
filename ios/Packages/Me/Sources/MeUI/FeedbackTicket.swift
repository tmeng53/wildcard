#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI
import UIKit

/// 意见反馈's ticket, on the shared `TicketCard`: the words above the tear line, and the
/// screenshots and the W stamp on the stub under it.
struct FeedbackTicket: View {
    @Bindable var model: FeedbackModel
    var isWriting: FocusState<Bool>.Binding
    /// The + tile: opens the photo picker the page holds.
    let addScreenshot: () -> Void
    @Environment(\.sceneTheme) private var theme

    /// Where `TextEditor` starts its first line inside its frame, which the placeholder matches.
    private static let editorInset = (top: 8.0, leading: 5.0)
    /// The face's height: the editor and the count under it.
    private static let faceHeight = 132.0

    /// The words above the tear line, the screenshots on the stub under it.
    var body: some View {
        TicketCard {
            VStack(spacing: Space.xxs) {
                TextEditor(text: $model.text)
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .scrollContentBackground(.hidden)
                    .focused(isWriting)
                    .frame(minHeight: 100, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if model.text.isEmpty {
                            placeholder
                                .typeStyle(TypeRamp.body)
                                .foregroundStyle(Color(role: .fgMuted, in: theme))
                                .padding(.top, Self.editorInset.top)
                                .padding(.leading, Self.editorInset.leading)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel(Text(copy: "写给我们", bundle: .module))
                    .accessibilityIdentifier("feedback.text")
                Text(verbatim: "\(model.count)/\(FeedbackText.maxLength)")
                    .typeStyle(TypeRamp.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .frame(height: Self.faceHeight)
        } stub: {
            stub
        }
    }

    private var placeholder: Text {
        model.kind == .problem
            ? Text(copy: "哪里出问题了？", bundle: .module) : Text(copy: "你的建议", bundle: .module)
    }

    private var stub: some View {
        HStack(alignment: .bottom, spacing: Space.xs + 2) {
            ForEach(model.screenshots) { shot in
                Thumbnail(jpeg: shot.jpeg) { model.remove(screenshot: shot.id) }
            }
            if model.canAddScreenshot {
                Button {
                    addScreenshot()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: Sizing.icon, weight: .medium))
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .frame(width: Thumbnail.size.width, height: Thumbnail.size.height)
                        .background(
                            Color(role: .bgCanvas, in: theme),
                            in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                                .strokeBorder(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline)
                        }
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text(copy: "加截图", bundle: .module))
                .accessibilityIdentifier("feedback.addScreenshot")
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Space.xs - 2) {
                TicketStamp()
                Text(copy: "截图最多 3 张", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}

/// A screenshot on the ticket's stub, with × to take it off.
private struct Thumbnail: View {
    static let size = CGSize(width: 60, height: 80)
    /// How far the remove badge sits in from the picture's corner.
    private static let badgeInset = 3.0

    let jpeg: Data
    let remove: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Group {
            if let image = UIImage(data: jpeg) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(role: .borderDefault, in: theme)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Radius.pick, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(role: .fgOnBrand, in: theme))
                    .frame(width: 20, height: 20)
                    .background(Color(role: .bgBrand, in: theme).opacity(0.75), in: Circle())
                    .padding(Self.badgeInset)
                    // A bigger place to tap than the badge, spilling past the picture's corner.
                    .contentShape(Rectangle().inset(by: -8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(copy: "去掉截图", bundle: .module))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(copy: "截图", bundle: .module))
    }
}
#endif
