#if canImport(SwiftUI)
import AvatarDomain
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The character editor: the character on its ticket at the top, with its nickname on the stub
/// under its feet and the day the member signed up in the corner; tabs of choices below; and one
/// button to finish. In sign-up it shows the step, a back button and the title 创建你的外卡运动员;
/// from 我 it shows 取消 and saves.
public struct CharacterEditorView: View {
    @Bindable private var model: CharacterEditorModel
    private let context: EditorContext
    private let issued: Date?
    private let onBack: () -> Void
    private let onDone: (EditedCharacter) -> Void
    @FocusState private var isNaming: Bool
    @Environment(\.sceneTheme) private var theme

    public init(
        model: CharacterEditorModel, context: EditorContext, issued: Date?, onBack: @escaping () -> Void,
        onDone: @escaping (EditedCharacter) -> Void
    ) {
        self.model = model
        self.context = context
        self.issued = issued
        self.onBack = onBack
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            EditorHeader(model: model, context: context, onBack: onBack)
            if case .signUp = context, !isNaming {
                Text("创建你的外卡运动员", bundle: .module)
                    .typeStyle(TypeRamp.taskTitle)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.pageMargin)
                    .padding(.bottom, Space.s)
            }
            CharacterStage(issued: issued) {
                EditorStage(model: model)
            } stub: {
                NicknameField(nickname: $model.nickname, isFocused: $isNaming)
            }
            .frame(height: EditorStage.height)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("editor.stage")
            .padding(.horizontal, Space.pageMargin)
            // The title, tabs and choices make room while the nickname is typed, so the page fits
            // above the keyboard and 就这样 stays in reach.
            if !isNaming {
                CategoryBar(
                    model.tabs.map {
                        CategoryBarItem(
                            id: $0, title: EditorNames.tab($0), accessibilityIdentifier: "editor.tab.\($0.rawValue)")
                    },
                    selection: $model.tab
                )
                .padding(.top, Space.s)
                ChoicesPanel(model: model)
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(role: .bgCanvas, in: theme))
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DoneBar(context: context, result: model.result, onDone: onDone)
        }
        .onAppear { model.start() }
        // A brand screen wherever it opens: sign-up, or a cover over 我 that doesn't inherit
        // 我's tone. Its button, tabs, picks and swatches never wear the squad's scene.
        .accentTone(.brand)
    }
}

/// Back or 取消 on the leading side, the sign-up step segments in the middle, undo and shuffle
/// on the trailing side.
private struct EditorHeader: View {
    let model: CharacterEditorModel
    let context: EditorContext
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            switch context {
            case .signUp:
                HeaderButton(Text("返回", bundle: .module), systemImage: "chevron.left", action: onBack)
                    .accessibilityIdentifier("editor.back")
            case .profile:
                Button(action: onBack) {
                    Text("取消", bundle: .module)
                }
                .buttonStyle(TextButtonStyle(.plain))
                .accessibilityIdentifier("editor.cancel")
            }
            if case .signUp(let step, let total) = context {
                StepSegments(step: step, of: total)
                    .padding(.horizontal, Space.xs)
                    .accessibilityIdentifier("editor.steps")
            } else {
                Spacer(minLength: 0)
            }
            HeaderButton(Text("撤销", bundle: .module), systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.draft.canUndo)
                .accessibilityIdentifier("editor.undo")
            HeaderButton(Text("随机换一个", bundle: .module), systemImage: "dice") { model.shuffle() }
                .accessibilityIdentifier("editor.shuffle")
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.xs)
    }
}

/// The finishing button, full width on the page: 就这样 in sign-up, 保存 from 我. It waits
/// for a nickname.
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
