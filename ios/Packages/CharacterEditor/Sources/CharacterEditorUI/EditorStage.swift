#if canImport(SwiftUI)
import AvatarArt
import AvatarUI
import CharacterEditorDomain
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The character standing on its stage's floor with its feet in view, its nickname under them,
/// undo and shuffle in the top corners. A tap makes it cheer. On the 性格 tab it says its 口头禅
/// in a bubble over its head, and a swipe across it tries the next persona. The editor puts it
/// in a `CharacterStage`, which may be shorter than `height` while the keyboard is up; the
/// character scales with it.
struct EditorStage: View {
    @Bindable var model: CharacterEditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shuffles = 0

    static let height: Double = 300
    /// The character's box on the full stage, 3:4 like the canvas, and how far down it starts:
    /// its feet land on the floor band, above the nickname.
    private let character = CGSize(width: 156, height: 208)
    private let characterTop: Double = 20
    /// How far a swipe must travel to change the persona.
    private let swipe: Double = 40

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.height / Self.height, 1)
            ZStack(alignment: .top) {
                figure
                    .frame(width: character.width * scale, height: character.height * scale)
                    .contentShape(Rectangle())
                    .onTapGesture { model.cheer() }
                    .gesture(personaSwipe, isEnabled: model.tab == .persona)
                    .padding(.top, characterTop * scale)
                if model.tab == .persona {
                    SpeechBubble(shout)
                        // Clear of the corner buttons.
                        .padding(.horizontal, Space.xxl + Space.xs)
                        .padding(.top, Space.xs)
                        .transition(.speech(reduceMotion: reduceMotion))
                        .accessibilityIdentifier("editor.shout")
                }
                corners
                NicknameField(nickname: $model.nickname)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, Space.s)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: model.tab == .persona)
        }
    }

    @ViewBuilder
    private var figure: some View {
        if let player = model.player {
            CharacterView(player: player)
        } else {
            Color.clear
        }
    }

    /// The 口头禅 as typed, or the persona's own line while it's empty.
    private var shout: Text {
        let typed = model.catchphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? model.draft.persona.defaultCatchphrase : Text(verbatim: typed)
    }

    /// Undo on the leading corner, shuffle on the trailing one: glass, since they sit on the stage.
    private var corners: some View {
        HStack {
            HeaderButton(Text("撤销", bundle: .module), systemImage: "arrow.uturn.backward", on: .scene) {
                model.undo()
            }
            .disabled(!model.draft.canUndo)
            .accessibilityIdentifier("editor.undo")
            Spacer(minLength: 0)
            HeaderButton(Text("随机换一个", bundle: .module), systemImage: "dice", on: .scene) {
                shuffles += 1
                model.shuffle()
            }
            .accessibilityIdentifier("editor.shuffle")
            // A whole new look is a moment of its own; undo stays quiet.
            .haptic(.appear, trigger: shuffles)
        }
        .padding(Space.xs)
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
    @Environment(\.sceneTheme) private var theme
    private let width: Double = 176
    /// Room for the pen on the trailing side, mirrored on the leading side to keep the name centered.
    private let inset: Double = 34
    private let pen: Double = 13

    var body: some View {
        TextField(text: $nickname, prompt: Text("昵称", bundle: .module)) {
            Text("昵称", bundle: .module)
        }
        .typeStyle(TypeRamp.headline)
        .foregroundStyle(Color(role: .fgDefault, in: theme))
        .tint(Color(role: .bgAccent, in: theme))
        .multilineTextAlignment(.center)
        .submitLabel(.done)
        .autocorrectionDisabled()
        .padding(.horizontal, inset)
        .frame(width: width, height: Sizing.control)
        .overlay(alignment: .trailing) {
            Image(systemName: "pencil")
                .font(.system(size: pen, weight: .semibold))
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .padding(.trailing, Space.s)
                .accessibilityHidden(true)
        }
        .background(
            Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
        )
        .accessibilityIdentifier("editor.nickname")
    }
}
#endif
