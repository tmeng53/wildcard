#if os(iOS)
import AvatarArt
import AvatarDomain
import AvatarUI
import CheckInUI
import Contracts
import DesignSystem
import DesignSystemUI
import ScenePickDomain
import ScenePickUI
import SquadDomain
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// The pieces of 小队设置: the scene line and picker, the invite card, a member's row and head.

/// Who picks this week's scene, or who picked it.
struct SceneLineText: View {
    let line: SceneLine

    var body: some View {
        switch line {
        case .youWon: Text("你是上周冠军，能选一次", bundle: .module)
        case .winnersPick(let names):
            let winners = names.formatted(.list(type: .and))
            Text("上周冠军 \(winners) 来选", bundle: .module)
        case .youPickAsCaptain, .captainPicks: Text("上周没有冠军，队长选一次", bundle: .module)
        case .youPicked: Text("你选的，下周冠军再换", bundle: .module)
        case .captainPicked: Text("队长选的，下周冠军再换", bundle: .module)
        case .winnerPicked(let name?): Text("\(name) 选的，下周冠军再换", bundle: .module)
        case .winnerPicked(nil): Text("冠军选的，下周冠军再换", bundle: .module)
        }
    }
}

/// The five scenes as tiles, when the squad last trained at the one chosen, and 「就它了」.
struct ScenePickerGrid: View {
    let picker: ScenePicker
    let onPicked: (Unboxing, SceneTheme) -> Void
    /// The pick was refused (someone else picked first, or the week moved on).
    let onRefused: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.xs, alignment: .top), count: 5)

    var body: some View {
        VStack(spacing: Space.s) {
            LazyVGrid(columns: columns, spacing: Space.xs) {
                ForEach(picker.options) { option in
                    SceneTile(
                        scene: option.scene, name: option.scene.name, isOpened: option.isOpened,
                        isSelected: picker.selection == option.scene, height: SquadSettingsMetrics.tile
                    ) {
                        picker.select(option.scene)
                    }
                    .accessibilityIdentifier("squad.scene.\(option.scene.rawValue)")
                }
            }
            if let last = picker.selectionLastTrained {
                LastTrainedLine(last: last)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
            Button {
                Task {
                    if let reveal = await picker.confirm(), let scene = picker.selection {
                        onPicked(reveal, scene)
                    } else if case .failed(.notAllowed) = picker.phase {
                        onRefused()
                    }
                }
            } label: {
                Text("就它了", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(.regular))
            .disabled(!picker.canConfirm)
            .accessibilityIdentifier("squad.scene.confirm")
            if case .failed(.unavailable) = picker.phase {
                Text("网络开小差了，没选上", bundle: .module)
                    .typeStyle(TypeRamp.footnote)
            }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: picker.selection)
    }
}

/// The invite code in scoreboard digits (tap to copy), how many more can join, and 分享.
struct InviteCard: View {
    let squad: Squad
    let openSpots: Int
    @State private var copied = false
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        HStack(spacing: Space.s) {
            Button(action: copy) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(verbatim: squad.inviteCode)
                        .typeStyle(TypeRamp.scoreCard)
                        .foregroundStyle(Color(role: .fgDefault, in: theme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("squad.inviteCode")
                    Group {
                        if copied {
                            Text("已复制", bundle: .module)
                        } else if openSpots > 0 {
                            Text("还能来 \(openSpots) 人", bundle: .module)
                        } else {
                            Text("满员了", bundle: .module)
                        }
                    }
                    .typeStyle(TypeRamp.footnote)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("复制邀请码 \(squad.inviteCode)", bundle: .module))
            .accessibilityIdentifier("squad.copyInvite")
            ShareLink(item: String(localized: "来外卡和我一起练！小队「\(squad.name)」的邀请码：\(squad.inviteCode)", bundle: .module)) {
                Label {
                    Text("分享", bundle: .module)
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .fixedSize()
            .accessibilityIdentifier("squad.share")
        }
        .card()
    }

    private func copy() {
        #if canImport(UIKit)
        UIPasteboard.general.string = squad.inviteCode
        #endif
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// A member: their character's head, nickname, 我, 上周冠军 and 队长, and for the captain a ···
/// menu to hand the captaincy on or remove them.
struct MemberRow: View {
    let member: SquadMemberRow
    let showsDivider: Bool
    let act: (MemberAction) -> Void
    @Environment(\.sceneTheme) private var theme

    private var name: String { member.character?.nickname.text ?? String(localized: "新队友", bundle: .module) }

    var body: some View {
        HStack(spacing: Space.s) {
            MemberHead(character: member.character)
            HStack(spacing: Space.xs) {
                Text(verbatim: name)
                    .typeStyle(TypeRamp.body)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .lineLimit(1)
                if member.isMe {
                    Text("我", bundle: .module)
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if member.hasCrown {
                Tag(Text("上周冠军", bundle: .module), systemImage: "crown")
            }
            if member.isCaptain {
                Text("队长", bundle: .module)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .padding(.horizontal, Space.s)
                    .frame(minHeight: Sizing.tag)
                    .background(Color(role: .bgSubtle, in: theme), in: Capsule())
                    .lineLimit(1)
            }
            if member.isManageable {
                Menu {
                    Button {
                        act(.handCaptaincy(member.id, name: name))
                    } label: {
                        Label {
                            Text("转让队长", bundle: .module)
                        } icon: {
                            Image(systemName: "crown")
                        }
                    }
                    .accessibilityIdentifier("squad.member.handCaptaincy")
                    Button(role: .destructive) {
                        act(.remove(member.id, name: name))
                    } label: {
                        Label {
                            Text("移出小队", bundle: .module)
                        } icon: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    .accessibilityIdentifier("squad.member.remove")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: Sizing.icon - 3, weight: .semibold))
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                        .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("管理 \(name)", bundle: .module))
                .accessibilityIdentifier("squad.member.more")
            }
        }
        .frame(minHeight: SquadSettingsMetrics.row)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(Color(role: .borderDefault, in: theme))
                    .frame(height: Sizing.hairline)
            }
        }
        .accessibilityIdentifier("squad.member")
    }
}

/// A member's face, still, in a circle; an empty circle until they make their character.
struct MemberHead: View {
    let character: MemberCharacter?
    @State private var drawing: (drawing: FigureDrawing, placements: [Placement])?
    @Environment(\.sceneTheme) private var theme

    /// The face on the rig's 240 by 320 canvas.
    private static let face = CGRect(x: 40, y: 74, width: 160, height: 160)

    var body: some View {
        ZStack {
            Circle().fill(Color(role: .bgSubtle, in: theme))
            if let drawing {
                CharacterCanvas(drawing: drawing.drawing, placements: drawing.placements, crop: Self.face)
                    .clipShape(Circle())
            }
        }
        .frame(width: SquadSettingsMetrics.head, height: SquadSettingsMetrics.head)
        .accessibilityHidden(true)
        .task(id: character) {
            guard let character else { return }
            let outfit = Outfit(character.look)
            drawing = try? CharacterPlayer(
                figure: PlaceholderCharacter.figure(wearing: outfit),
                idle: PlaceholderCharacter.clip(
                    "idle", persona: Persona(character.look), species: PlaceholderCharacter.species(of: outfit))
            ).restFrame
        }
    }
}

/// 小队设置 couldn't be read: one line and a way to try again.
struct SquadFailed: View {
    let retry: () -> Void
    @Environment(\.sceneTheme) private var theme

    var body: some View {
        VStack(spacing: Space.m) {
            Text("网络开小差了", bundle: .module)
                .typeStyle(TypeRamp.headline)
                .foregroundStyle(Color(role: .fgDefault, in: theme))
            Button(action: retry) { Text("再试一次", bundle: .module) }
                .buttonStyle(PrimaryButtonStyle(.regular))
                .accessibilityIdentifier("squad.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
