#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import SwiftUI
import Synchronization

/// A broadcast told in its celebration style (the approved pre-holiday notice, holiday stores
/// design, 2026-11-04): a card over the dimmed app with its header art, the member on it wearing
/// what it gives and waving, its words, what it gives in tiles, its button and 先不了. The app
/// pops it up with `cardPopup`, where a tap off it is 先不了 too.
///
/// Its look comes from the scene named like the store its icon shows (TURKEY TROT's `trot`, the
/// 秋日小镇's colours), else the squad's scene; the header art is that scene's
/// `<scene>-notice@3x.png`, put by an admin (`scenes/…`) or bundled.
public struct BroadcastCelebration: View {
    let model: TodayModel
    let broadcast: Broadcast
    @State private var player: CharacterPlayer?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The design's card: 22 points in from the screen's edges, its corners rounder than a card's.
    private let edge: Double = 22
    private let corner: Double = 28
    private let tile: Double = 78
    private let tileCorner: Double = 22

    public init(model: TodayModel, broadcast: Broadcast) {
        (self.model, self.broadcast) = (model, broadcast)
    }

    public var body: some View {
        let theme = Self.theme(of: broadcast, else: model.scene)
        let language = [AppLanguage.current.rawValue]
        VStack(spacing: 0) {
            header(theme)
            Text(verbatim: broadcast.title.localized(in: language))
                .typeStyle(TypeRamp.taskTitle)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
                .multilineTextAlignment(.center)
                .padding(.top, Space.s)
                .padding(.horizontal, edge)
            if let body = broadcast.body {
                Text(verbatim: body.localized(in: language))
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .multilineTextAlignment(.center)
                    .padding(.top, Space.xxs)
                    .padding(.horizontal, edge)
            }
            gifts(theme)
            buttons(language)
        }
        .padding(.bottom, Space.xxs)
        .background(Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .environment(\.sceneTheme, theme)
        .padding(.horizontal, edge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("broadcast.celebration")
        .task(id: broadcast.id) { await wave() }
    }

    /// The header art, the member standing on it.
    private func header(_ theme: SceneTheme) -> some View {
        Color(role: .bgAccentSubtle, in: theme)
            .overlay {
                if let picture = Self.headerPicture(theme) {
                    Image(uiImage: picture).resizable()
                }
            }
            .aspectRatio(Header.width / Header.height, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    let scale = proxy.size.width / Header.width
                    if let player {
                        ZStack(alignment: .bottom) {
                            Ellipse()
                                .fill(Color(role: .bgInk, in: theme).opacity(0.08))
                                .frame(width: Header.shadow.width * scale, height: Header.shadow.height * scale)
                            CharacterView(player: player)
                                .frame(width: Header.figure.width * scale, height: Header.figure.height * scale)
                        }
                        .position(x: Header.figure.midX * scale, y: Header.figure.midY * scale)
                    }
                }
            }
            .accessibilityHidden(true)
    }

    /// What it gives, each in a tile of the scene's wash with its corner in the scene's colour;
    /// nothing when it gives nothing.
    @ViewBuilder
    private func gifts(_ theme: SceneTheme) -> some View {
        if !broadcast.gifts.isEmpty, let unlocks = model.unlockNotices {
            HStack(spacing: Space.xs) {
                ForEach(broadcast.gifts, id: \.self) { gift in
                    unlocks.picture(gift.kind, gift.id)
                        .padding(Space.xs)
                        .frame(width: tile, height: tile)
                        .background(Color(role: .bgAccentSubtle, in: theme))
                        .overlay(alignment: .topLeading) {
                            Corner().fill(Color(role: .bgAccent, in: theme)).frame(
                                width: tileCorner, height: tileCorner)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: Radius.ticket, style: .continuous))
                }
            }
            .padding(.top, Space.s)
            .accessibilityHidden(true)
        }
    }

    /// Its button, which opens its place, and 先不了; a broadcast without a button is put away
    /// with 好的.
    private func buttons(_ language: [String]) -> some View {
        VStack(spacing: 0) {
            if let action = broadcast.action {
                Button {
                    model.closeCelebration(opening: true)
                } label: {
                    Text(verbatim: action.label.localized(in: language)).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("broadcast.celebration.open")
                Button {
                    model.closeCelebration(opening: false)
                } label: {
                    Text("先不了", bundle: .module)
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("broadcast.celebration.later")
            } else {
                Button {
                    model.closeCelebration(opening: false)
                } label: {
                    Text("好的", bundle: .module).frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.bottom, Space.s)
                .accessibilityIdentifier("broadcast.celebration.later")
            }
        }
        .padding(.top, Space.m)
        .padding(.horizontal, edge)
    }

    /// The member in their own look wearing what it gives, waving now and then; their own look
    /// alone when a gift's art isn't here yet.
    private func wave() async {
        var look = model.myLook
        let choices = try? PlaceholderCharacter.editorChoices()
        for gift in broadcast.gifts where gift.kind != .store {
            if let slot = choices?.slot(of: gift.id) { look.variants[slot] = gift.id }
        }
        let persona = model.myPersona
        guard
            let figure = (try? PlaceholderCharacter.figure(wearing: look))
                ?? (try? PlaceholderCharacter.figure(wearing: model.myLook)),
            let idle = try? PlaceholderCharacter.clip(
                "idle", persona: persona, species: PlaceholderCharacter.species(of: look)),
            let made = try? CharacterPlayer(figure: figure, idle: idle)
        else { return }
        player = made
        guard !reduceMotion, let wave = try? PlaceholderCharacter.clip(for: Move.wave, persona: persona) else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Header.waveEvery))
            try? made.play(wave)
        }
    }

    /// The scene named like the store its icon shows, if this build or the catalog knows it.
    static func theme(of broadcast: Broadcast, else fallback: SceneTheme) -> SceneTheme {
        guard let icon = broadcast.icon, icon.kind == .store, let scene = SceneTheme(rawValue: icon.id),
            SceneTheme.Base(rawValue: scene.rawValue) != nil || SceneTheme.listing(scene) != nil
        else { return fallback }
        return scene
    }

    /// The scene's notice art: the one an admin put (`scenes/<scene>-notice@3x.png`), else the
    /// one this build ships; nil without either. Read once per launch.
    static func headerPicture(_ scene: SceneTheme) -> UIImage? {
        let name = "\(scene.rawValue)-notice"
        if let kept = pictures.withLock({ $0[name] }) { return kept }
        let downloaded = ArtTree.downloadedFile("\(name)@3x.png", in: "scenes")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { UIImage(data: $0, scale: 3) }
        guard let picture = downloaded ?? UIImage(named: name, in: .module, with: nil) else { return nil }
        pictures.withLock { $0[name] = picture }
        return picture
    }

    private static let pictures = Mutex<[String: UIImage]>([:])
}

/// The header's design, in its own 346 × 176 points: where the member stands (the character's
/// 240 × 320 canvas at 0.36, feet at 160) and their shadow.
private enum Header {
    static let width: Double = 346
    static let height: Double = 176
    static let figure = CGRect(x: 173 - 120 * 0.36, y: 160 - 312 * 0.36, width: 240 * 0.36, height: 320 * 0.36)
    static let shadow = CGSize(width: 92 * 0.36, height: 18 * 0.36)
    /// Seconds between waves.
    static let waveEvery: Double = 2.6
}

/// The tile's corner flag: a right triangle in its top-left corner.
private struct Corner: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
#endif
