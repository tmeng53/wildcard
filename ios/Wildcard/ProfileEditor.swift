import AvatarArt
import CharacterEditorUI
import CheckInUI
import Contracts
import DesignSystemUI
import MeDomain
import MeUI
import SwiftUI

/// The character editor opened from 我, pushed over 我 or 商店街 like 我's other pages, so going
/// back is the system's: it saves the character on 保存, and its 球衣号码 pushes the number page
/// over it, which saves on its own and comes back to the editor.
struct ProfileEditor: View {
    let model: CharacterEditorModel
    let profile: MeModel
    /// 今天, which wears the saved character at once.
    let today: TodayModel
    let close: () -> Void
    @State private var pickingNumber = false

    var body: some View {
        CharacterEditorView(
            model: model, context: .profile, issued: profile.overview?.joinedAt, onBack: close,
            onDone: { edited in
                close()
                let character = MeCharacter(
                    nickname: edited.nickname, outfit: edited.outfit, persona: edited.persona)
                let save: @MainActor () async -> Void = { await profile.save(character) }
                Task {
                    if let nickname = try? Nickname(edited.nickname) {
                        let look = CharacterLook(outfit: edited.outfit, persona: edited.persona)
                        await today.wear(MemberCharacter(nickname: nickname, look: look), save: save)
                    } else {
                        await save()
                    }
                }
            },
            jerseyNumber: JerseyNumberEntry(number: profile.overview?.cardNumber?.text) { pickingNumber = true }
        )
        // Once something changed, the editor's own back asks first, in place of the system's.
        // 保存 is its own bar at the bottom, so the tab bar goes while it is up.
        .pushedPage(canGoBack: !model.draft.canUndo, hidesTabBar: true)
        .navigationDestination(isPresented: $pickingNumber) {
            JerseyNumberView(model: profile) { pickingNumber = false }
        }
    }
}
