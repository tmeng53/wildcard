#if os(iOS)
import AvatarArt
import AvatarUI
import DesignSystem
import DesignSystemUI
import SwiftUI

/// While 我 reads the overview: the character jogging in place, with no words, on the page's
/// own white (character states, 加载; loader design A). `MeView` covers the page with it once the
/// wait has lasted.
struct MeLoading: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        LoadingCharacter()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(role: .bgCanvas, in: theme))
            .accessibilityIdentifier("me.loading")
    }
}

/// 我 couldn't be read: the character, one line and a way to try again (character states, 出错).
struct MeFailed: View {
    let retry: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.m) {
            StateCharacter()
            Text("网络开小差了", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            Button(action: retry) { Text("再试一次", bundle: .module) }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .accessibilityIdentifier("me.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The stand-in character for a state screen, before the member's own is read. It plays the
/// idle until the state clips (jogging in place, sitting on the ground) are in the art.
struct StateCharacter: View {
    @State private var player: CharacterPlayer?

    var body: some View {
        Group {
            if let player { CharacterView(player: player) }
        }
        .frame(width: 120, height: 160)
        .task {
            player = try? CharacterPlayer(
                figure: PlaceholderCharacter.figure(wearing: PlaceholderCharacter.lifter),
                idle: PlaceholderCharacter.clip("idle", persona: .energetic))
        }
    }
}
#endif
