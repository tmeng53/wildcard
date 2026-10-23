#if canImport(SwiftUI)
import AvatarArt
import AvatarUI
import DesignSystem
import DesignSystemUI
import MeDomain
import SwiftUI

/// Where 我's rows lead outside the tab. The app decides: the squad and past 战报 open their
/// tabs until they have pages of their own.
public struct MeDestinations {
    public var squad: () -> Void
    public var pastRecaps: () -> Void
    public var editCharacter: () -> Void
    /// The published policy pages.
    public var privacyPolicy: URL
    public var terms: URL

    public init(
        squad: @escaping () -> Void, pastRecaps: @escaping () -> Void, editCharacter: @escaping () -> Void,
        privacyPolicy: URL, terms: URL
    ) {
        self.squad = squad
        self.pastRecaps = pastRecaps
        self.editCharacter = editCharacter
        self.privacyPolicy = privacyPolicy
        self.terms = terms
    }
}

/// 我: the member's player card (tap it to turn it over) and 编辑角色, with a small 设置 button
/// that opens the settings menu, and from there 注销账号. Each page replaces the last in place.
/// These pages keep out of the scene's colours: ink and white only.
public struct MeView: View {
    @Bindable private var model: MeModel
    private let destinations: MeDestinations
    @State private var isSettingsOpen = false
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: MeModel, destinations: MeDestinations) {
        self.model = model
        self.destinations = destinations
    }

    public var body: some View {
        ZStack {
            if model.isDeletionOpen {
                DeleteAccountView(model: model) { model.closeDeletion() }
                    .transition(.move(edge: .trailing))
            } else if isSettingsOpen {
                SettingsView(model: model, destinations: destinations) { isSettingsOpen = false }
                    .transition(.move(edge: .trailing))
            } else {
                content
            }
        }
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: model.isDeletionOpen)
        .animation(.wildcard(Motion.page, reduceMotion: reduceMotion), value: isSettingsOpen)
        .task { await model.reload() }
    }

    @ViewBuilder private var content: some View {
        switch model.load {
        case .loading:
            MeLoading()
        case .failed:
            MeFailed { Task { await model.reload() } }
        case .loaded(let overview):
            ScrollView {
                VStack(spacing: Space.l) {
                    HStack {
                        Spacer()
                        Button {
                            isSettingsOpen = true
                        } label: {
                            Text("设置", bundle: .module)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("me.settings")
                    }
                    PlayerCard(overview: overview)
                    VStack(spacing: Space.xs) {
                        Button(action: destinations.editCharacter) {
                            Text("编辑角色", bundle: .module)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("me.editCharacter")
                        if model.saveFailed {
                            SaveFailed()
                        }
                    }
                }
                .padding(.horizontal, Space.pageMargin)
                .padding(.top, Space.xs)
                .padding(.bottom, Space.l)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(role: .bgCanvas, in: theme))
            .refreshable { await model.reload() }
            .accessibilityIdentifier("me.page")
        }
    }
}

/// The last change didn't save; says so until the next one.
struct SaveFailed: View {
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        Text("网络开小差了，没存上", bundle: .module)
            .typeStyle(TypeRamp.footnote)
            .foregroundStyle(Color(role: .fgMuted, in: theme))
            .accessibilityIdentifier("me.saveFailed")
    }
}

/// The member's character on a little floor shadow. It plays its persona's idle and changes
/// clothes in place when the character is edited.
struct MeStage: View {
    let character: MeCharacter?
    var size = CGSize(width: 160, height: 200)
    /// The shadow's colour, so it shows on the page and in the card's window alike.
    var floor: ColorRole = .bgSubtle
    @State private var player: CharacterPlayer?
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(Color(role: floor, in: theme))
                .frame(width: size.width * 0.6, height: Space.xs)
            Group {
                if let player {
                    CharacterView(player: player)
                } else {
                    Color.clear
                }
            }
            .frame(width: size.width, height: size.height - Space.xxs)
            .padding(.bottom, Space.xxs)
        }
        .frame(width: size.width, height: size.height)
        .task(id: character) { dress() }
    }

    private func dress() {
        guard let character else { return }
        do {
            let figure = try PlaceholderCharacter.figure(wearing: character.outfit)
            let idle = try PlaceholderCharacter.clip("idle", persona: character.persona)
            if let player {
                try player.wear(figure, idle: idle)
            } else {
                player = try CharacterPlayer(figure: figure, idle: idle)
            }
        } catch {
            // Art that doesn't build leaves the stage empty; the rest of 我 still works.
            player = nil
        }
    }
}
#endif
