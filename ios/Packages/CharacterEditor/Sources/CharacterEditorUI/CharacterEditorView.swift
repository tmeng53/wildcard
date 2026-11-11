#if os(iOS)
import AvatarDomain
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The character editor: the character on its ticket at the top, with its nickname on the stub
/// under its feet and the day the member signed up in the corner; tabs of choices below; and one
/// button to finish. In sign-up it shows the step, a back button and the title 创建你的外卡运动员;
/// from 我 it is a pushed page: the system's back, the member's 球衣号码 when the app passes one
/// and undo and shuffle in the bar, and it saves.
public struct CharacterEditorView: View {
    @Bindable private var model: CharacterEditorModel
    private let context: EditorContext
    private let issued: Date?
    private let onBack: () -> Void
    private let onDone: (EditedCharacter) -> Void
    private let jerseyNumber: JerseyNumberEntry?
    @FocusState private var isNaming: Bool
    @Environment(\.sceneTheme) private var theme

    public init(
        model: CharacterEditorModel, context: EditorContext, issued: Date?, onBack: @escaping () -> Void,
        onDone: @escaping (EditedCharacter) -> Void, jerseyNumber: JerseyNumberEntry? = nil
    ) {
        self.model = model
        self.context = context
        self.issued = issued
        self.onBack = onBack
        self.onDone = onDone
        self.jerseyNumber = jerseyNumber
    }

    public var body: some View {
        VStack(spacing: 0) {
            if case .signUp(let step, let total) = context {
                EditorHeader(model: model, step: step, total: total, onBack: onBack)
            }
            if showsTitle {
                Text(copy: "创建你的外卡运动员", bundle: .module)
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
            // Without the title, the ticket keeps clear of the header's round buttons.
            .padding(.top, showsTitle ? 0 : Space.s)
            // The title, tabs and choices make room while the nickname is typed, so the page fits
            // above the keyboard and 确认 stays in reach.
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
        .actionBar {
            DoneBar(
                context: context, result: model.result, isNaming: isNaming, onNamed: { isNaming = false },
                onDone: onDone)
        }
        .toolbar {
            if context == .profile {
                EditorBarItems(model: model, jerseyNumber: jerseyNumber)
            }
        }
        .onAppear { model.start() }
        // A brand screen wherever it opens: sign-up, or a page over 我 or 商店街 that doesn't take
        // their tone. Its button, tabs, picks and swatches never wear the squad's scene.
        .accentTone(.brand)
    }

    /// 创建你的外卡运动员 shows in sign-up, out of the way while the nickname is typed.
    private var showsTitle: Bool {
        guard case .signUp = context else { return false }
        return !isNaming
    }
}

/// The member's 球衣号码 as the editor opened from 我 shows it, and what a tap on it opens: the
/// number lives on the player card, whose page the app passes in.
public struct JerseyNumberEntry {
    /// The number as the card prints it ("07"), nil before the member picks one.
    public let number: String?
    public let open: () -> Void

    public init(number: String?, open: @escaping () -> Void) {
        self.number = number
        self.open = open
    }
}

/// Sign-up's header: back on the leading side, the step segments in the middle, undo and shuffle
/// on the trailing side.
private struct EditorHeader: View {
    let model: CharacterEditorModel
    let step: Int
    let total: Int
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            HeaderButton(Text(copy: "返回", bundle: .module), systemImage: "chevron.left", action: onBack)
                .accessibilityIdentifier("editor.back")
            StepSegments(step: step, of: total)
                .padding(.horizontal, Space.xs)
                .accessibilityIdentifier("editor.steps")
            HeaderButton(Text(copy: "撤销", bundle: .module), systemImage: "arrow.uturn.backward") { model.undo() }
                .disabled(!model.draft.canUndo)
                .accessibilityIdentifier("editor.undo")
            HeaderButton(Text(copy: "随机换一个", bundle: .module), systemImage: "dice") { model.shuffle() }
                .accessibilityIdentifier("editor.shuffle")
        }
        .padding(.horizontal, Space.pageMargin)
        .padding(.vertical, Space.xs)
    }
}

/// From 我, in the pushed page's bar beside the system's back: the 球衣号码 in the middle, undo
/// and shuffle on the trailing side.
private struct EditorBarItems: ToolbarContent {
    let model: CharacterEditorModel
    let jerseyNumber: JerseyNumberEntry?

    var body: some ToolbarContent {
        if let jerseyNumber {
            ToolbarItem(placement: .principal) {
                Button(action: jerseyNumber.open) {
                    Text(copy: "球衣号码 \(jerseyNumber.number ?? "--")", bundle: .module)
                }
                .buttonStyle(TextButtonStyle(.plain))
                .accessibilityIdentifier("editor.jerseyNumber")
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                model.undo()
            } label: {
                Label {
                    Text(copy: "撤销", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            .disabled(!model.draft.canUndo)
            .accessibilityIdentifier("editor.undo")
            Button {
                model.shuffle()
            } label: {
                Label {
                    Text(copy: "随机换一个", bundle: .module)
                } icon: {
                    Image(systemName: "dice")
                }
            }
            .accessibilityIdentifier("editor.shuffle")
        }
    }
}

/// The finishing button, full width on the page: 确认 in sign-up, 保存 from 我. It waits
/// for a nickname. While the nickname is typed it is 好了 and only puts the keyboard away, so
/// the button under the name never finishes the character by surprise.
private struct DoneBar: View {
    let context: EditorContext
    let result: EditedCharacter?
    let isNaming: Bool
    let onNamed: () -> Void
    let onDone: (EditedCharacter) -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Button {
            if isNaming {
                onNamed()
            } else if let result {
                onDone(result)
            }
        } label: {
            Group {
                if isNaming {
                    Text(copy: "好了", bundle: .module)
                } else if context == .profile {
                    Text(copy: "保存", bundle: .module)
                } else {
                    Text(copy: "确认", bundle: .module)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!isNaming && result == nil)
        .accessibilityIdentifier(isNaming ? "editor.named" : "editor.done")
    }
}
#endif
