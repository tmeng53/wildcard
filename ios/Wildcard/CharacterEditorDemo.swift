import CharacterEditorUI
import Foundation

/// Opens the character editor on its own, until sign-up and 我 wire it into their flows.
/// `-character-editor` starts from a random look, as sign-up will; UI tests add
/// `-character-editor-sample` for a fixed look, and `-character-editor-profile` to open it as
/// from 我.
@MainActor
enum CharacterEditorDemo {
    static func model() -> CharacterEditorModel? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-character-editor") else { return nil }
        let sample = arguments.contains("-character-editor-sample")
        return try? CharacterEditorModel.placeholder(
            look: sample ? CharacterEditorModel.sampleLook : nil, nickname: "Tracy")
    }

    static var context: EditorContext {
        ProcessInfo.processInfo.arguments.contains("-character-editor-profile") ? .profile : .signUp(step: 2, total: 4)
    }
}
