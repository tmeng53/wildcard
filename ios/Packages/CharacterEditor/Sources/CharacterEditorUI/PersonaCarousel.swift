#if canImport(SwiftUI)
import AvatarArt
import DesignSystem
import DesignSystemUI
import SwiftUI

/// The personas as a row of names that snaps like a camera's mode dial: whichever name comes
/// to rest in the middle is the persona, and the character above plays it. Tapping a name
/// scrolls it to the middle.
struct PersonaCarousel: View {
    let model: CharacterEditorModel
    @State private var centered: Persona?
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let itemWidth: Double = 120
    private let itemHeight: Double = 64
    private let selectedScale: Double = 1.18
    private let dot: Double = 6
    private let selectedDot: Double = 18

    var body: some View {
        VStack(spacing: Space.xs) {
            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Persona.allCases, id: \.self) { persona in
                            item(persona)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, max((proxy.size.width - itemWidth) / 2, 0), for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centered, anchor: .center)
                .scrollIndicators(.hidden)
                .mask {
                    // The names fade toward the edges, so the middle one reads as the choice.
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0), .init(color: .black, location: 0.3),
                            .init(color: .black, location: 0.7), .init(color: .clear, location: 1),
                        ], startPoint: .leading, endPoint: .trailing)
                }
            }
            .frame(height: itemHeight)
            dots
        }
        .padding(.top, Space.xxl)
        .onAppear { centered = model.draft.persona }
        .onChange(of: centered) { _, persona in
            if let persona { model.choose(persona) }
        }
        .onChange(of: model.draft.persona) { _, persona in
            // A swipe on the stage picks too; bring its name to the middle.
            guard centered != persona else { return }
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { centered = persona }
        }
        .haptic(.pick, trigger: model.draft.persona)
    }

    private func item(_ persona: Persona) -> some View {
        let isSelected = persona == model.draft.persona
        return Button {
            withAnimation(.wildcard(Motion.page, reduceMotion: reduceMotion)) { centered = persona }
        } label: {
            EditorNames.persona(persona)
                .typeStyle(TypeRamp.action)
                .foregroundStyle(Color(role: isSelected ? .fgDefault : .fgSubtle, in: theme))
                .scaleEffect(isSelected && !reduceMotion ? selectedScale : 1)
                .frame(width: itemWidth, height: itemHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.wildcard(Motion.celebrate, reduceMotion: reduceMotion), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("editor.persona.\(persona.rawValue)")
    }

    private var dots: some View {
        HStack(spacing: dot) {
            ForEach(Persona.allCases, id: \.self) { persona in
                let isSelected = persona == model.draft.persona
                Capsule()
                    .fill(Color(role: isSelected ? .fgDefault : .borderDefault, in: theme))
                    .frame(width: isSelected ? selectedDot : dot, height: dot)
            }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: model.draft.persona)
        .accessibilityHidden(true)
    }
}
#endif
