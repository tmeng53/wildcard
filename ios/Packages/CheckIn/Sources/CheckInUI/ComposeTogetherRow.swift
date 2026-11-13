#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInDomain
import Contracts
import DesignSystem
import DesignSystemUI
import SportsUI
import SwiftUI

/// 一起练 on a 训练 (approved 2026-11-10): first the squadmates who trained around the same time,
/// as 检测到的运动's chips (one who named the member says 标了你, and a tap also starts the 训练
/// from theirs), then every squadmate's head, picked or not with a tap, several at once. Shown only
/// for a post that goes to the squad.
struct ComposeTogetherRow: View {
    @Environment(\.sceneTheme) private var theme
    let model: ComposeModel
    let together: TrainingTogether

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            SectionLabel(Text(copy: "一起练", bundle: .module))
            if !together.hints.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Space.xs) {
                        ForEach(together.hints) { hint in
                            chip(hint)
                        }
                    }
                    .padding(.vertical, Space.xxs / 4)
                }
                .scrollIndicators(.hidden)
                .horizontalScrollFade()
            }
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Space.s) {
                    ForEach(together.mates, id: \.member) { mate in
                        head(mate)
                    }
                }
                .padding(.vertical, Space.xxs)
            }
            .scrollIndicators(.hidden)
            .horizontalScrollFade()
        }
        .accessibilityIdentifier("compose.together")
    }

    private func mate(_ id: MemberID) -> SquadmateToday? {
        together.mates.first { $0.member == id }
    }

    private func name(_ mate: SquadmateToday?) -> Text {
        if let nickname = mate?.character?.nickname.text {
            Text(verbatim: nickname)
        } else {
            Text(copy: "队友", bundle: .module)
        }
    }

    private func chip(_ hint: TrainingTogether.Hint) -> some View {
        let isPicked = model.trainedWith.contains(hint.mate)
        let squadmate = mate(hint.mate)
        return Button {
            model.take(hint)
        } label: {
            HStack(spacing: Space.xs) {
                MateFace(mate: squadmate, id: hint.mate, size: Self.chipHead)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.xxs) {
                        name(squadmate)
                        Text(verbatim: "·")
                        hint.activity.name
                    }
                    .typeStyle(TypeRamp.calloutEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    Group {
                        switch (hint.namedMe, hint.startTime) {
                        case (true, let start?): Text(copy: "标了你 · \(start.wire)", bundle: .module)
                        case (true, nil): Text(copy: "标了你", bundle: .module)
                        case (false, let start?): Text(verbatim: start.wire)
                        case (false, nil): Text(copy: "今天也练了", bundle: .module)
                        }
                    }
                    .typeStyle(TypeRamp.caption)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .lineLimit(1)
            .padding(.horizontal, Space.s)
            .frame(height: Self.chipHeight, alignment: .leading)
            .background(
                Color(role: .bgCanvas, in: theme), in: RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Radius.pick, style: .continuous)
                    .strokeBorder(
                        Color(role: isPicked ? .fgDefault : .borderDefault, in: theme),
                        lineWidth: isPicked ? Sizing.selectionStroke : 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .haptic(.pick, trigger: isPicked)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityIdentifier("compose.together.hint.\(hint.mate)")
    }

    private func head(_ squadmate: SquadmateToday) -> some View {
        let isPicked = model.trainedWith.contains(squadmate.member)
        return Button {
            model.toggle(mate: squadmate.member)
        } label: {
            VStack(spacing: Space.xxs) {
                MateFace(mate: squadmate, id: squadmate.member, size: Self.head)
                    .padding(Self.gap)
                    .overlay {
                        if isPicked {
                            Circle()
                                .strokeBorder(Color(role: .fgDefault, in: theme), lineWidth: Sizing.selectionStroke)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isPicked { CheckBadge() }
                    }
                name(squadmate)
                    .typeStyle(isPicked ? TypeRamp.captionEmphasis : TypeRamp.caption)
                    .foregroundStyle(Color(role: isPicked ? .fgDefault : .fgMuted, in: theme))
                    .lineLimit(1)
            }
            .frame(width: Self.head + Self.gap * 2 + Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .haptic(.pick, trigger: isPicked)
        .accentTone(.brand)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityIdentifier("compose.together.mate.\(squadmate.member)")
    }

    private static let head: Double = 48
    private static let gap: Double = 4
    private static let chipHead: Double = 28
    private static let chipHeight: Double = 48
}

/// A squadmate's face, still: the character they made, or their stand-in before they made one.
struct MateFace: View {
    let mate: SquadmateToday?
    let id: MemberID
    let size: Double
    @State private var player: CharacterPlayer?

    var body: some View {
        MemberHead(player: player, size: size)
            .task(id: mate?.character) {
                let look = mate.map(SquadCast.look) ?? StandInCharacter.look(of: id)
                let persona = mate.map(SquadCast.persona) ?? StandInCharacter.persona(of: id)
                player = try? CharacterPlayer(
                    figure: PlaceholderCharacter.figure(wearing: look),
                    idle: PlaceholderCharacter.clip(
                        "idle", persona: persona, species: PlaceholderCharacter.species(of: look)))
            }
    }
}
#endif
