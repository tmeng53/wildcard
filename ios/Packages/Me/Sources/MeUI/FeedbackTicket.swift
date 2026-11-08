#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI
import UIKit

/// 意见反馈's ticket, as the character editor's: the words above the tear line, with a notch cut
/// on either side, and the screenshots and the W on the stub under it.
struct FeedbackTicket: View {
    @Bindable var model: FeedbackModel
    var isWriting: FocusState<Bool>.Binding
    /// The + tile: opens the photo picker the page holds.
    let addScreenshot: () -> Void
    @Environment(\.sceneTheme) private var theme

    /// Where `TextEditor` starts its first line inside its frame, which the placeholder matches.
    private static let editorInset = (top: 8.0, leading: 5.0)

    /// The words above the tear line, the screenshots on the stub under it.
    var body: some View {
        VStack(spacing: 0) {
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
                    .accessibilityLabel(Text("写给我们", bundle: .module))
                    .accessibilityIdentifier("feedback.text")
                Text(verbatim: "\(model.count)/\(FeedbackText.maxLength)")
                    .typeStyle(TypeRamp.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Space.m - 4)
            .padding(.top, Space.s)
            .padding(.bottom, Space.s)
            .frame(height: 148)
            tearLine
            stub
        }
        .background(
            Color(role: .bgSubtle, in: theme), in: RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
    }

    private var placeholder: Text {
        model.kind == .problem
            ? Text("哪里出问题了？", bundle: .module) : Text("你的建议", bundle: .module)
    }

    /// The perforation, with a notch cut on either side in the page's colour.
    private var tearLine: some View {
        ZStack {
            Line()
                .stroke(
                    Color(role: .fgDefault, in: theme).opacity(0.18),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
                .frame(height: 1.5)
                .padding(.horizontal, Space.m + 2)
            HStack {
                Circle().fill(Color(role: .bgCanvas, in: theme)).frame(width: 22, height: 22).offset(x: -11)
                Spacer()
                Circle().fill(Color(role: .bgCanvas, in: theme)).frame(width: 22, height: 22).offset(x: 11)
            }
        }
        .frame(height: 22)
        .accessibilityHidden(true)
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
                .accessibilityLabel(Text("加截图", bundle: .module))
                .accessibilityIdentifier("feedback.addScreenshot")
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: Space.xs - 2) {
                Text(verbatim: "W")
                    .typeStyle(TypeRamp.scoreWeek)
                    .foregroundStyle(Color(role: .bgBrand, in: theme))
                    .accessibilityHidden(true)
                Text("截图最多 3 张", bundle: .module)
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.s + 2)
        .padding(.bottom, Space.m)
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
            .accessibilityLabel(Text("去掉截图", bundle: .module))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("截图", bundle: .module))
    }
}

/// A straight line across its frame, for the dashed tear line.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
#endif
