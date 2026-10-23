#if os(iOS)
import AvatarUI
import Contracts
import DesignSystem
import DesignSystemUI
import FeedDomain
import SwiftUI

/// The emoji row at the bottom of a card: the most-left emoji (up to 3), how many reacted and
/// the latest three faces; tapping them lists who left what. At the right, my button: a smiley
/// that opens the emoji bar, or my emoji on the scene's wash once I reacted. My own posts have no
/// button: nobody reacts to their own post.
struct ReactionRow: View {
    @Environment(\.sceneTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: FeedModel
    let post: FeedPost
    @State private var showsWho = false

    private static let buttonWidth: Double = 44
    private static let headOverlap: Double = 8

    var body: some View {
        let reactions = post.reactions
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                if !reactions.isEmpty {
                    summary(reactions)
                }
                Spacer(minLength: 0)
                if post.canRespond(model.viewer) {
                    myButton(reactions.kind(of: model.viewer))
                }
            }
            if showsWho, !reactions.isEmpty {
                who(reactions)
                    .transition(.opacity)
            }
        }
        .animation(.wildcard(Motion.sheet, reduceMotion: reduceMotion), value: showsWho)
    }

    private func summary(_ reactions: Responses<Emoji>) -> some View {
        Button {
            showsWho.toggle()
        } label: {
            HStack(spacing: Space.xs - 2) {
                Text(verbatim: reactions.topKinds(3).map(\.text).joined())
                    .typeStyle(TypeRamp.headline)
                Text(verbatim: "\(reactions.all.count)")
                    .typeStyle(TypeRamp.callout)
                    .foregroundStyle(Color(role: .fgMuted, in: theme))
                    .contentTransition(.numericText())
                HStack(spacing: -Self.headOverlap) {
                    ForEach(reactions.latestMembers(3), id: \.self) { member in
                        Face(player: model.head(of: member))
                    }
                }
                .padding(.leading, Space.xxs)
            }
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.wildcard(Motion.change, reduceMotion: reduceMotion), value: reactions.all.count)
        .accessibilityLabel(Text("\(reactions.all.count) 个回应", bundle: .module))
        .accessibilityHint(Text("看谁回应了", bundle: .module))
        .accessibilityIdentifier("feed.reactions")
    }

    /// Who left which emoji, the most left first.
    private func who(_ reactions: Responses<Emoji>) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            ForEach(reactions.groups, id: \.kind) { group in
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(verbatim: group.kind.text)
                        .typeStyle(TypeRamp.body)
                    Text(verbatim: group.members.map(name).joined(separator: "、"))
                        .typeStyle(TypeRamp.footnote)
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func name(_ member: MemberID) -> String {
        if member == model.viewer { return String(localized: "我", bundle: .module) }
        return model.name(of: member) ?? String(localized: "队友", bundle: .module)
    }

    private func myButton(_ mine: Emoji?) -> some View {
        Button {
            withAnimation(.wildcard(Motion.sheet, reduceMotion: reduceMotion)) { model.picking = post.id }
        } label: {
            Group {
                if let mine {
                    Text(verbatim: mine.text).typeStyle(TypeRamp.headline)
                } else {
                    Image(systemName: "face.smiling")
                        .font(.system(size: Sizing.icon, weight: .regular))
                        .foregroundStyle(Color(role: .fgMuted, in: theme))
                }
            }
            .frame(width: Self.buttonWidth, height: Sizing.compactControl)
            .background(Color(role: mine == nil ? .bgCanvas : .bgAccentSubtle, in: theme), in: Capsule())
            .frame(minHeight: Sizing.minimumTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(FeedView.space))
        } action: { frame in
            model.buttons[post.id] = frame
        }
        .accessibilityLabel(
            mine.map { Text("我的回应：\($0.text)", bundle: .module) } ?? Text("回应", bundle: .module)
        )
        .accessibilityIdentifier("feed.react")
    }
}

/// A teammate's head in a small white circle, as on the home's squad card.
private struct Face: View {
    @Environment(\.sceneTheme) private var theme
    let player: CharacterPlayer?

    var body: some View {
        Circle()
            .fill(Color(role: .bgCanvas, in: theme))
            .overlay {
                if let player {
                    CharacterHead(player: player).padding(Sizing.ringGap)
                }
            }
            .overlay { Circle().stroke(Color(role: .bgSubtle, in: theme), lineWidth: Sizing.ringGap) }
            .frame(width: Sizing.characterHead, height: Sizing.characterHead)
            .accessibilityHidden(true)
    }
}
#endif
