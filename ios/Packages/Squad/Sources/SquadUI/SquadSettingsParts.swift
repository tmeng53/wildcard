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

/// Who picks this week's scene.
struct SceneLineText: View {
    let line: SceneLine

    var body: some View {
        switch line {
        case .youWon: Text("你是上周冠军，能选一次", bundle: .module)
        case .winnersPick(let names):
            let winners = names.formatted(.list(type: .and).locale(AppLanguage.current.locale))
            Text("上周冠军 \(winners) 来选", bundle: .module)
        case .youPickAsCaptain, .captainPicks: Text("上周没有冠军，队长选一次", bundle: .module)
        }
    }
}

/// The five scenes as tiles, when the squad last trained at the one chosen, and 「确认」.
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
                Text("确认", bundle: .module).loadingLabel(picker.phase == .saving).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(.regular))
            .disabled(!picker.canConfirm)
            .accessibilityIdentifier("squad.scene.confirm")
            if case .failed(.unavailable) = picker.phase {
                InlineFailure()
            }
        }
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: picker.selection)
    }
}

/// The invite code in scoreboard digits (a tap copies its invite link), how many more can join,
/// and 分享.
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
            .accessibilityLabel(Text("复制邀请链接 \(squad.inviteCode)", bundle: .module))
            .accessibilityIdentifier("squad.copyInvite")
            InviteShareLink(squad: squad) {
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
        // The invite link, like 分享, so a paste in a chat opens the invite page (or the app).
        UIPasteboard.general.string = squad.inviteLink?.absoluteString ?? squad.inviteCode
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
    /// A change to this member is saving: the ··· menu waits as 三拍.
    let isSaving: Bool
    /// Opens their player card; nil on my own row.
    let open: (() -> Void)?
    /// The captain confirmed a change to this member.
    let act: (MemberAction) -> Void
    @Environment(\.sceneTheme) private var theme
    @State private var isManaging = false

    private var name: String { Self.name(of: member) }

    /// The member's nickname, or 新队友 until they make their character.
    static func name(of member: SquadMemberRow) -> String {
        member.character?.nickname.text ?? String(localized: "新队友", bundle: .module.inAppLanguage)
    }

    /// 转让队长 and 移出小队, each asking first.
    private var manageItems: [GlassMenuItem] {
        let hand = MemberAction.handCaptaincy(member.id, name: name)
        let remove = MemberAction.remove(member.id, name: name)
        return [
            GlassMenuItem(
                Text("转让队长", bundle: .module), systemImage: "crown", id: "squad.member.handCaptaincy",
                confirm: .init(hand.title, label: Text("转让", bundle: .module), id: "squad.handCaptaincy.confirm")
            ) { act(hand) },
            GlassMenuItem(
                Text("移出小队", bundle: .module), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive,
                id: "squad.member.remove",
                confirm: .init(remove.title, label: Text("移出", bundle: .module), id: "squad.remove.confirm")
            ) { act(remove) },
        ]
    }

    var body: some View {
        HStack(spacing: Space.s) {
            if let open {
                // A teammate's face and name open their player card.
                Button(action: open) { who }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityHint(Text("看球员卡", bundle: .module))
                    .accessibilityIdentifier("squad.member.card")
            } else {
                who
            }
            if member.hasCrown {
                // Tags keep their words; a long nickname gives way instead.
                Tag(Text("上周冠军", bundle: .module), systemImage: "crown")
                    .fixedSize()
            }
            if member.isCaptain {
                Text("队长", bundle: .module)
                    .typeStyle(TypeRamp.footnoteEmphasis)
                    .foregroundStyle(Color(role: .fgDefault, in: theme))
                    .padding(.horizontal, Space.s)
                    .frame(minHeight: Sizing.tag)
                    .background(Color(role: .bgSubtle, in: theme), in: Capsule())
                    .lineLimit(1)
                    .fixedSize()
            }
            if member.isManageable {
                LoadingSwap(isSaving) {
                    Button {
                        isManaging = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: Sizing.icon - 3, weight: .semibold))
                            .foregroundStyle(Color(role: .fgMuted, in: theme))
                            .frame(width: Sizing.minimumTapTarget, height: Sizing.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("管理 \(name)", bundle: .module))
                    .accessibilityIdentifier("squad.member.more")
                    .glassMenu(isPresented: $isManaging, items: manageItems)
                }
                .foregroundStyle(Color(role: .fgMuted, in: theme))
                .frame(minWidth: Sizing.minimumTapTarget, minHeight: Sizing.minimumTapTarget)
            }
        }
        .frame(minHeight: SquadSettingsMetrics.row)
        .overlay(alignment: .top) {
            if showsDivider {
                Hairline()
            }
        }
        // Contain, so the row's identifier doesn't replace its ··· button's.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("squad.member")
    }

    /// Their face, nickname and 我.
    private var who: some View {
        HStack(spacing: Space.s) {
            LookHead(character: member.character)
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
        }
        .frame(minHeight: SquadSettingsMetrics.row)
        .contentShape(Rectangle())
    }
}

/// A member's face, still, in a `MemberHead`; an empty circle until they make their character.
struct LookHead: View {
    let character: MemberCharacter?
    var size = SquadSettingsMetrics.head
    @State private var player: CharacterPlayer?

    var body: some View {
        MemberHead(player: player, size: size)
            .task(id: character) {
                guard let character else { return }
                let outfit = Outfit(character.look)
                player = try? CharacterPlayer(
                    figure: PlaceholderCharacter.figure(wearing: outfit),
                    idle: PlaceholderCharacter.clip(
                        "idle", persona: Persona(character.look), species: PlaceholderCharacter.species(of: outfit)))
            }
    }
}

/// 小队设置 couldn't be read: one line and a way to try again.
struct SquadFailed: View {
    let retry: () -> Void

    var body: some View {
        StateView.offline(retryIdentifier: "squad.retry", retry: retry)
            .frame(maxHeight: .infinity)
    }
}

/// What the captain is about to do to a member, asked first in the glass menu.
enum MemberAction: Hashable {
    case handCaptaincy(MemberID, name: String)
    case remove(MemberID, name: String)

    var title: Text {
        switch self {
        case .handCaptaincy(_, let name): Text("把队长转给 \(name)？", bundle: .module)
        case .remove(_, let name): Text("把 \(name) 移出小队？", bundle: .module)
        }
    }
}

enum SquadSettingsMetrics {
    /// The scene's thumbnail on 本周场地.
    static let thumbnail = CGSize(width: 56, height: 72)
    /// A member's row.
    static let row = 56.0
    /// A member's head.
    static let head = 36.0
    /// A scene tile's face in the picker.
    static let tile = 64.0
}

/// 分享 and the head row's 邀请: the squad's invite link (wildcardsquad.com/join/<code>), which
/// opens the app on 加入小队 for someone who has it and shows the squad to someone who doesn't,
/// under a line naming the squad.
struct InviteShareLink<ShareLabel: View>: View {
    let squad: Squad
    @ViewBuilder let label: () -> ShareLabel

    var body: some View {
        // Looked up in the app's language, which the share sheet doesn't know.
        let message = Text(
            verbatim: String(localized: "来外卡和我一起训练！小队「\(squad.name)」", bundle: .module.inAppLanguage))
        if let link = squad.inviteLink {
            ShareLink(item: link, message: message, label: label)
        } else {
            // A code the app can't read (never sent by the API): the code itself, as before links.
            ShareLink(item: squad.inviteCode, message: message, label: label)
        }
    }
}

extension Squad {
    /// What 分享 sends and the code's tap copies: wildcardsquad.com/join/<code>. Nil for a code the
    /// app can't read (the API never sends one).
    var inviteLink: URL? { (try? InviteCode(inviteCode)).map(InviteLink.url(for:)) }
}
#endif
