#if os(iOS)
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI
import UIKit

/// The emoji bar over the whole feed while it is open, over its post's button: a tap anywhere
/// else closes it. It shares the feed's frame, so `FeedView.space` is its own.
struct EmojiBarLayer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel

    var body: some View {
        GeometryReader { proxy in
            if let open = model.picking, let post = model.store.post(open), let button = model.buttons[open] {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                EmojiBar(mine: post.reactions.kind(of: model.viewer)) { emoji in
                    model.react(.pick(emoji), on: post)
                } close: {
                    close()
                }
                .fixedSize()
                .position(
                    x: max(
                        min(button.maxX, proxy.size.width - Space.pageMargin) - EmojiBar.width / 2,
                        Space.pageMargin + EmojiBar.width / 2),
                    y: max(button.minY - Space.xs - EmojiBar.height / 2, EmojiBar.height / 2)
                )
                .transition(.scale(scale: 0.4, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.picking)
    }

    private func close() {
        withAnimation(.wildcard(Motion.sheet.exit, reduceMotion: reduceMotion)) { model.picking = nil }
    }
}

/// The six common emoji and ＋, which opens the emoji keyboard for any other: a white capsule
/// over the card. Mine is on the scene's wash; picking it again takes it back.
struct EmojiBar: View {
    @Environment(\.sceneTheme) private var theme
    let mine: Emoji?
    let pick: (Emoji) -> Void
    let close: () -> Void
    @State private var typing = false

    static let height: Double = 52
    private static let emojiSize: Double = 28
    private static let inset = Space.xxs + 2
    /// Every emoji and ＋ a tap target wide, inside the capsule's ends.
    static var width: Double { Double(common.count + 1) * Sizing.minimumTapTarget + 2 * inset }

    /// The bar's emoji, in the approved order.
    static let common: [Emoji] = ["❤️", "💪", "😂", "🤤", "😮", "😡"].compactMap { try? Emoji($0) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.common, id: \.self) { emoji in
                Button {
                    pick(emoji)
                } label: {
                    Text(verbatim: emoji.text)
                        .font(.system(size: Self.emojiSize))
                        .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                        .background {
                            if emoji == mine { Circle().fill(Color(role: .bgAccentSubtle, in: theme)) }
                        }
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(emoji == mine ? .isSelected : [])
                .accessibilityIdentifier("feed.emoji.\(emoji.text)")
            }
            Button {
                typing = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: Sizing.smallIcon, weight: .semibold))
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .frame(width: Sizing.compactControl, height: Sizing.compactControl)
                    .background(Color(role: .bgSubtle, in: theme), in: Circle())
                    .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("更多表情", bundle: .module))
            .accessibilityIdentifier("feed.emoji.more")
            .background {
                EmojiField(isActive: $typing) { emoji in
                    pick(emoji)
                }
                .frame(width: 1, height: 1)
                .opacity(0)
            }
        }
        .padding(.horizontal, Self.inset)
        .frame(height: Self.height)
        .background(Color(role: .bgCanvas, in: theme), in: Capsule())
        .overlay { Capsule().stroke(Color(role: .borderDefault, in: theme), lineWidth: Sizing.hairline) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("选一个回应", bundle: .module))
        .accessibilityIdentifier("feed.emojiBar")
    }
}

/// A hidden text field that brings up the emoji keyboard, so any emoji can be a reaction. The
/// first emoji typed is picked and the keyboard goes away; anything else is ignored.
private struct EmojiField: UIViewRepresentable {
    @Binding var isActive: Bool
    let picked: (Emoji) -> Void

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.parent = self
        if isActive, !field.isFirstResponder {
            field.becomeFirstResponder()
        } else if !isActive, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiField

        init(parent: EmojiField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            let typed = field.text ?? ""
            field.text = ""
            guard let first = typed.last.map(String.init), let emoji = try? Emoji(first) else { return }
            parent.isActive = false
            parent.picked(emoji)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isActive = false
        }
    }
}

/// Opens on the emoji keyboard when the person has one, else on their own keyboard.
private final class EmojiTextField: UITextField {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}
#endif
