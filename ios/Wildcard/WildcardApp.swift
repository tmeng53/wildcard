import CharacterEditorUI
import DesignSystemUI
import SwiftUI

/// The app target only wires packages together. Until the first feature screen lands, it
/// opens on the design system's style guide; `-character-editor` opens the character editor.
@main
struct WildcardApp: App {
    @State private var editor = CharacterEditorDemo.model()

    var body: some Scene {
        WindowGroup {
            if let editor {
                CharacterEditorView(model: editor, context: CharacterEditorDemo.context, onBack: {}, onDone: { _ in })
            } else {
                StyleGuideView()
            }
        }
    }
}
