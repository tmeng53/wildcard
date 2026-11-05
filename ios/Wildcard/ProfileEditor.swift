import CharacterEditorUI
import DesignSystem
import DesignSystemUI
import MeDomain
import MeUI
import SwiftUI

/// The character editor opened from 我: it saves the character on 保存, and its 球衣号码 opens the
/// number page over it, which saves on its own and comes back to the editor.
struct ProfileEditor: View {
    let model: CharacterEditorModel
    let profile: MeModel
    let close: () -> Void
    @State private var pickingNumber = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CharacterEditorView(
                model: model, context: .profile, issued: profile.overview?.joinedAt, onBack: close,
                onDone: { edited in
                    close()
                    Task {
                        await profile.save(
                            MeCharacter(nickname: edited.nickname, outfit: edited.outfit, persona: edited.persona))
                    }
                },
                jerseyNumber: JerseyNumberEntry(number: profile.overview?.cardNumber?.text) { pickingNumber = true })
            if pickingNumber {
                JerseyNumberView(model: profile) { pickingNumber = false }
                    .swipesBack { pickingNumber = false }
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: pickingNumber)
    }
}
