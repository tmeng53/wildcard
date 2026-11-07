import CharacterEditorUI
import DesignSystemUI
import MeDomain
import MeUI
import SwiftUI

/// The character editor opened from 我: it saves the character on 保存, and its 球衣号码 pushes the
/// number page over it, which saves on its own and comes back to the editor.
struct ProfileEditor: View {
    let model: CharacterEditorModel
    let profile: MeModel
    let close: () -> Void
    @State private var pickingNumber = false

    var body: some View {
        NavigationStack {
            CharacterEditorView(
                model: model, context: .profile, issued: profile.overview?.joinedAt, onBack: close,
                onDone: { edited in
                    close()
                    Task {
                        await profile.save(
                            MeCharacter(nickname: edited.nickname, outfit: edited.outfit, persona: edited.persona))
                    }
                },
                jerseyNumber: JerseyNumberEntry(number: profile.overview?.cardNumber?.text) { pickingNumber = true }
            )
            .navigationRoot()
            .navigationDestination(isPresented: $pickingNumber) {
                JerseyNumberView(model: profile) { pickingNumber = false }
            }
        }
    }
}
