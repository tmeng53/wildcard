#if canImport(SwiftUI)
import AvatarDomain
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// The character editor: the character on its stage at the top, with its nickname under its
/// feet and undo and shuffle in the stage's corners; tabs of choices below; and one button to
/// finish. In sign-up it shows a back button and the steps; from 我 it shows 取消 and 我的角色
/// and saves.
public struct CharacterEditorView: View {
    @Bindable private var model: CharacterEditorModel
    private let context: EditorContext
    private let onBack: () -> Void
    private let onDone: (EditedCharacter) -> Void
    @Environment(\.sceneTheme) private var theme
    @State private var isTyping = false

    /// What the page under the stage needs: the tabs, two rows of tiles and the done button;
    /// with the keyboard up, the tabs and the field being typed in.
    private let roomBelowStage: Double = 430
    private let roomBelowStageTyping: Double = 290
    /// The stage never shrinks past a character that still reads, with the keyboard up.
    private let smallestStage: Double = 150

    public init(
        model: CharacterEditorModel, context: EditorContext, onBack: @escaping () -> Void,
        onDone: @escaping (EditedCharacter) -> Void
    ) {
        self.model = model
        self.context = context
        self.onBack = onBack
        self.onDone = onDone
    }

    public var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                EditorHeader(context: context, onBack: onBack)
                CharacterStage {
                    EditorStage(model: model)
                }
                .frame(height: stageHeight(in: proxy.size.height))
                .padding(.horizontal, Space.pageMargin)
                CategoryBar(
                    model.tabs.map {
                        CategoryBarItem(
                            id: $0, title: EditorNames.tab($0), accessibilityIdentifier: "editor.tab.\($0.rawValue)")
                    },
                    selection: $model.tab
                )
                .padding(.top, Space.s)
                ChoicesPanel(model: model)
                // While typing, the keyboard covers where the button sits; it comes back after.
                if !isTyping {
                    DoneBar(context: context, result: model.result, onDone: onDone)
                }
            }
        }
        .background(Color(role: .bgCanvas, in: theme))
        .onAppear { model.start() }
        .modifier(KeyboardWatch(isShown: $isTyping))
    }

    /// The full stage, shrinking on a small phone or while typing so the field stays in view.
    private func stageHeight(in height: Double) -> Double {
        let room = isTyping ? roomBelowStageTyping : roomBelowStage
        return min(EditorStage.height, max(smallestStage, height - room))
    }
}

/// Keeps `isShown` in step with the software keyboard.
private struct KeyboardWatch: ViewModifier {
    @Binding var isShown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { isShown = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { isShown = false }
            }
        #else
        content
        #endif
    }
}

/// In sign-up, back and the step segments, as every sign-up step has them; from 我, 取消 and
/// the page's name.
private struct EditorHeader: View {
    let context: EditorContext
    let onBack: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.l) {
            switch context {
            case .signUp(let step, let total):
                HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: onBack)
                    .accessibilityIdentifier("editor.back")
                StepSegments(step: step, of: total)
                    .accessibilityIdentifier("editor.steps")
                // Keeps the segments centered: as wide as the back button.
                Color.clear.frame(width: Sizing.control, height: Sizing.control)
            case .profile:
                Button(action: onBack) {
                    Text("取消", bundle: .module)
                }
                .buttonStyle(TextButtonStyle(.plain))
                .accessibilityIdentifier("editor.cancel")
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("我的角色", bundle: .module)
                    .typeStyle(TypeRamp.headline)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                Color.clear.frame(maxWidth: .infinity, maxHeight: Sizing.control)
            }
        }
        .frame(height: Sizing.control)
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.xs)
    }
}

/// The finishing button, full width on the page: 就这样 in sign-up, 保存 from 我. It waits
/// for a nickname, and for a 口头禅 that fits.
private struct DoneBar: View {
    let context: EditorContext
    let result: EditedCharacter?
    let onDone: (EditedCharacter) -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button {
            if let result { onDone(result) }
        } label: {
            Group {
                if context == .profile {
                    Text("保存", bundle: .module)
                } else {
                    Text("就这样", bundle: .module)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(result == nil)
        .accessibilityIdentifier("editor.done")
        .padding(.horizontal, Space.pageMargin)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xs)
        .background(Color(role: .bgCanvas, in: theme).ignoresSafeArea(edges: .bottom))
    }
}
#endif
