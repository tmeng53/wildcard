import CharacterEditorUI
import CheckInUI
import DesignSystemUI
import SwiftUI

/// The app target only wires packages together. It opens on 今天, backed by an in-memory squad
/// until the Backend adapter lands; `-styleguide` opens the design system's style guide and
/// `-character-editor` the character editor instead. After the first check-in it asks for
/// notifications; a tapped one brings the member back to 今天 with the board read again.
@main
struct WildcardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var today: TodayModel
    @State private var editor = CharacterEditorDemo.model()

    // An init, not a property initializer: those run outside the main actor, and the post
    // callback is the main actor's.
    init() {
        _today = State(
            initialValue: TodayModel(
                service: InMemoryCheckInService.sampleSquad(now: .now),
                writer: LaunchOptions.disclaimerWriter,
                photoSource: LaunchOptions.photoSource,
                posted: Self.askForNotifications))
    }

    /// After a post, once the cheer has played: the first one brings up the permission prompt.
    private static func askForNotifications() {
        guard LaunchOptions.asksForNotifications else { return }
        Task {
            try? await Task.sleep(for: Push.promptDelay)
            await Push.registration.checkedIn()
        }
    }

    var body: some Scene {
        WindowGroup {
            if let editor {
                CharacterEditorView(model: editor, context: CharacterEditorDemo.context, onBack: {}, onDone: { _ in })
            } else if LaunchOptions.showsStyleGuide {
                StyleGuideView()
            } else {
                TodayView(model: today)
                    .onAppear { delegate.opened = { [today] in Task { await today.load() } } }
            }
        }
    }
}
