import CharacterEditorUI
import CheckInDomain
import CheckInUI
import DesignSystemUI
import Foundation
import SwiftUI

/// The app target only wires packages together. It opens on 今天, backed by an in-memory squad
/// until sign-in and the squad step land; `-styleguide` opens the design system's style guide and
/// `-character-editor` the character editor instead.
@main
struct WildcardApp: App {
    @State private var today = TodayModel(
        store: TodayStore(
            backend: InMemoryCheckInBackend.sampleSquad(now: .now), outbox: InMemoryOutbox(), now: { Date() },
            newID: { UUID() }),
        writer: LaunchOptions.disclaimerWriter,
        photoSource: LaunchOptions.photoSource)
    @State private var editor = CharacterEditorDemo.model()

    var body: some Scene {
        WindowGroup {
            if let editor {
                CharacterEditorView(model: editor, context: CharacterEditorDemo.context, onBack: {}, onDone: { _ in })
            } else if LaunchOptions.showsStyleGuide {
                StyleGuideView()
            } else {
                TodayView(model: today)
            }
        }
    }
}
