#if canImport(SwiftUI)
import AvatarDomain
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The character editor: the character on its stage at the top, with its nickname under its
/// feet; tabs of choices below; and one button to finish. In sign-up it shows the step and a
/// back button; from 我 it shows 取消 and saves.
public struct CharacterEditorView: View {
    @Bindable private var model: CharacterEditorModel
    private let context: EditorContext
    private let onBack: () -> Void
    private let onDone: (EditedCharacter) -> Void
    @Environment(\.sceneTheme) private var theme

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
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                EditorHeader(model: model, context: context, onBack: onBack)
                EditorStage(model: model)
            }
            .background {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: Radius.xl, bottomTrailingRadius: Radius.xl, style: .continuous
                )
                .fill(Color(role: .signatureWash, in: theme))
                .ignoresSafeArea(edges: .top)
            }
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
        .background(Color(role: .canvas, in: theme))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DoneBar(context: context, result: model.result, onDone: onDone)
        }
        .onAppear { model.start() }
    }
}

/// Back or 取消 on the leading side, the sign-up step in the middle, undo and shuffle on the
/// trailing side. The buttons are Liquid Glass, since they float over the scene.
private struct EditorHeader: View {
    let model: CharacterEditorModel
    let context: EditorContext
    let onBack: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ZStack {
            if case .signUp(let step, let total) = context {
                StepBar(step: step, total: total)
            }
            HStack(spacing: Space.xxs) {
                switch context {
                case .signUp:
                    GlassIconButton(systemImage: "chevron.left", label: Text("返回", bundle: .module), action: onBack)
                        .accessibilityIdentifier("editor.back")
                case .profile:
                    Button(action: onBack) {
                        Text("取消", bundle: .module)
                            .typeStyle(TypeRamp.body)
                            .foregroundStyle(Color(role: .textPrimary, in: theme))
                            .padding(.horizontal, Space.xs)
                            .frame(minHeight: Sizing.minimumTapTarget)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityIdentifier("editor.cancel")
                }
                Spacer(minLength: 0)
                GlassIconButton(
                    systemImage: "arrow.uturn.backward", label: Text("撤销", bundle: .module), action: { model.undo() }
                )
                .disabled(!model.draft.canUndo)
                .accessibilityIdentifier("editor.undo")
                GlassIconButton(systemImage: "dice", label: Text("随机换一个", bundle: .module), action: { model.shuffle() })
                    .accessibilityIdentifier("editor.shuffle")
            }
        }
        .padding(.horizontal, Space.s)
        .frame(minHeight: Sizing.minimumTapTarget + Space.xxs)
    }
}

/// Four short bars, the steps done and this one in the scene's color.
private struct StepBar: View {
    let step: Int
    let total: Int
    @Environment(\.sceneTheme) private var theme
    private let barHeight: Double = 5
    private let width: Double = 150

    var body: some View {
        HStack(spacing: Space.xxs + 2) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(Color(role: index <= step ? .signature : .divider, in: theme))
                    .frame(height: barHeight)
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("第 \(step) 步，共 \(total) 步", bundle: .module))
        .accessibilityIdentifier("editor.steps")
    }
}

/// A round Liquid Glass button with a symbol, for controls over the scene.
private struct GlassIconButton: View {
    let systemImage: String
    let label: Text
    let action: () -> Void
    @Environment(\.sceneTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    private let glyph: Double = 18

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(Color(role: isEnabled ? .textPrimary : .textTertiary, in: theme))
                .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(label)
    }
}

/// The finishing button on a frosted bar: 就这样 in sign-up, 保存 from 我. It waits for a
/// nickname.
private struct DoneBar: View {
    let context: EditorContext
    let result: EditedCharacter?
    let onDone: (EditedCharacter) -> Void
    @Environment(\.sceneTheme) private var theme
    private let minimumWidth: Double = 200

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
            .typeStyle(TypeRamp.action)
            .padding(.horizontal, Space.xl)
            .frame(minWidth: minimumWidth)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(result == nil)
        .accessibilityIdentifier("editor.done")
        .frame(maxWidth: .infinity)
        .padding(.top, Space.s)
        .padding(.bottom, Space.xs)
        .background {
            // Frost down to the screen's bottom edge, under the home indicator.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(Palette.white).opacity(Frost.cardFill))
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color(role: .divider, in: theme)).frame(height: 1)
        }
    }
}
#endif
