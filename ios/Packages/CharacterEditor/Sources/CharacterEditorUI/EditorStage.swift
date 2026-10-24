#if canImport(SwiftUI)
import AvatarUI
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The character standing on its stage's floor, its nickname under its feet. A tap makes it
/// cheer; on the 性格 tab a swipe across it tries the next persona, and a held prop plays its
/// move now and then. The editor puts it in a `CharacterStage`.
struct EditorStage: View {
    @Bindable var model: CharacterEditorModel
    var isNaming: FocusState<Bool>.Binding
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: Double = 300
    private let character = CGSize(width: 200, height: 267)
    /// How far above the stage's bottom the character's box sits, so its feet land on the floor.
    private let feet: Double = 46
    /// How far a swipe must travel to change the persona.
    private let swipe: Double = 40

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if let player = model.player {
                    CharacterView(player: player)
                } else {
                    Color.clear
                }
            }
            .frame(width: character.width, height: character.height)
            .contentShape(Rectangle())
            .onTapGesture { model.cheer() }
            .gesture(personaSwipe, isEnabled: model.tab == .persona)
            .padding(.bottom, feet)
            NicknameField(nickname: $model.nickname, isFocused: isNaming)
                .padding(.bottom, Space.xs)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .task(id: model.tab == .persona && !reduceMotion) {
            guard model.tab == .persona, !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                model.propMoveIfIdle()
            }
        }
    }

    private var personaSwipe: some Gesture {
        DragGesture(minimumDistance: Space.m).onEnded { drag in
            let distance = drag.translation.width
            guard abs(distance) >= swipe else { return }
            // Swiping left brings in the next persona, as the carousel below does.
            model.choosePersona(after: distance < 0 ? 1 : -1)
        }
    }
}

/// The nickname, typed straight onto a white tag under the character's feet.
private struct NicknameField: View {
    @Binding var nickname: String
    var isFocused: FocusState<Bool>.Binding
    @Environment(\.sceneTheme) private var theme
    private let width: Double = 180
    /// Room for the pen on the trailing side, mirrored on the leading side to keep the name centered.
    private let inset: Double = 34
    private let pen: Double = 13

    var body: some View {
        TextField(text: $nickname, prompt: Text("昵称", bundle: .module)) {
            Text("昵称", bundle: .module)
        }
        .typeStyle(TypeRamp.headline)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .multilineTextAlignment(.center)
        .submitLabel(.done)
        .focused(isFocused)
        .onSubmit { isFocused.wrappedValue = false }
        .autocorrectionDisabled()
        .padding(.horizontal, inset)
        .frame(width: width, height: Sizing.minimumTapTarget)
        .overlay(alignment: .trailing) {
            Image(systemName: "pencil")
                .font(.system(size: pen, weight: .semibold))
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .padding(.trailing, Space.m)
                .accessibilityHidden(true)
        }
        .background(
            Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        )
        .accessibilityIdentifier("editor.nickname")
    }
}
#endif
