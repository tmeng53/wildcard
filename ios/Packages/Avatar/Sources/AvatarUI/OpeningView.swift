#if canImport(SwiftUI)
import AvatarArt
import AvatarDomain
import DesignSystem
import DesignSystemUI
import Foundation
import SwiftUI

/// A full-screen opening an admin drew (a holiday's 「感恩节快乐」): its layers on the stage,
/// moved by its clip once and its loop for as long as it shows, with the squad cheering where
/// the timeline puts them, posed for a group photo so everyone shows whole and, once the clip has played, the button that enters. The stage
/// fills the screen, cropping its edges on a phone of another shape. With Reduce Motion on, it
/// opens on the clip's last frame, standing still, with the button already there.
public struct OpeningView<Label: View>: View {
    let opening: Opening
    let art: [String: ArtworkView]
    let squad: [CharacterPlayer]
    let language: String
    let squadName: String?
    let label: Label
    let onPlayed: () -> Void
    let onEnter: () -> Void
    @State private var start = Date.now
    @State private var played = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `language` picks each text layer's words (`zh-Hans`, `en`, `zh-Hant`), falling back to
    /// `zh-Hans`, and `squadName` fills their `{squad}`; `onPlayed` runs once the clip has played
    /// (for the squad to cheer), and `onEnter` when the button labelled `label` is tapped.
    public init(
        _ loaded: OpeningArt.Loaded, squad: [CharacterPlayer], squadName: String?, language: String,
        onPlayed: @escaping () -> Void = {}, onEnter: @escaping () -> Void, @ViewBuilder label: () -> Label
    ) {
        opening = loaded.opening
        art = loaded.art.mapValues(ArtworkView.init)
        self.squad = squad
        self.language = language
        self.squadName = squadName
        self.onPlayed = onPlayed
        self.onEnter = onEnter
        self.label = label()
    }

    public var body: some View {
        GeometryReader { geometry in
            let stage = opening.stage
            let scale = max(geometry.size.width / stage.width, geometry.size.height / stage.height)
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { timeline in
                let time = reduceMotion ? opening.clip.duration : timeline.date.timeIntervalSince(start)
                ZStack(alignment: .topLeading) {
                    ForEach(opening.layers, id: \.id) { layer in
                        self.layer(layer, at: time)
                    }
                }
                .frame(width: stage.width, height: stage.height, alignment: .topLeading)
                .scaleEffect(scale)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(Color(opening.background))
        .clipped()
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if played || reduceMotion {
                Button(action: onEnter) {
                    label
                        .typeStyle(TypeRamp.action)
                        .foregroundStyle(Color(opening.button.text))
                        .frame(maxWidth: .infinity, minHeight: Sizing.primaryControl)
                        .background(Color(opening.button.background), in: .capsule)
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xxl)
                .transition(.opacity)
            }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: played)
        .task {
            start = .now
            if !reduceMotion { try? await Task.sleep(for: .seconds(opening.clip.duration)) }
            played = true
            onPlayed()
        }
    }

    @ViewBuilder private func layer(_ layer: Opening.Layer, at time: Double) -> some View {
        let placement = opening.placement(of: layer.id, at: time)
        let frame = layer.frame
        content(layer.content, id: layer.id)
            .frame(width: frame.width, height: frame.height)
            .scaleEffect(x: placement.scaleX, y: placement.scaleY)
            .rotationEffect(.degrees(placement.rotation))
            .opacity(placement.opacity)
            .offset(x: frame.x + placement.x, y: frame.y + placement.y)
    }

    @ViewBuilder private func content(_ content: Opening.Content, id: PartID) -> some View {
        switch content {
        case .art(let file):
            art[file].accessibilityHidden(true)
        case .text(let words, let color, let size, let font):
            Text(verbatim: Opening.words(words, language: language, squad: squadName))
                .font(Self.font(font, size: size))
                .foregroundStyle(Color(color))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .lineLimit(2)
        case .squad:
            SquadPhotoView(players: squad)
        }
    }

    /// The display face is the wordmark's (Barlow Condensed); the body face is the app's text face.
    private static func font(_ font: Opening.Font, size: Double) -> Font {
        switch font {
        case .display:
            ScoreboardFont.register()
            return .custom(Face.scoreboard(.extraBold).postScriptName, fixedSize: size)
        case .body:
            return .custom(Face.text(.semibold).postScriptName, fixedSize: size).weight(.heavy)
        }
    }
}
#endif
